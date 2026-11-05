"""Crecidas de ríos, arroyos y canales de la Provincia de Buenos Aires, y agua en el suelo.

Cómo se calcula (fuentes gratuitas, sin IA):
1. Inventario DPH/IGN/GCBA y complemento OSM (hydrography.py). Incluye cauces cortos y sin nombre.
   Los tramos cartográficos y las cuencas son independientes de la cobertura de monitoreo.
2. Lluvia en la cuenca: lluvia prevista a 72 h (suma de las medianas diarias de 9 modelos) promediada en los
   partidos que cruza cada curso, más la lluvia de los últimos 30 días (suelo ya cargado de agua).
3. Caudal: GloFAS (Copernicus) vía Open-Meteo Flood API, que ya incorpora el pronóstico de lluvia de ECMWF.
   En puntos del cauce se compara el máximo esperado de los próximos 7 días (mediana del ensamble) con el
   caudal típico de las últimas 3 semanas. En los 7 ríos con estación de referencia (rios.json) se usa además
   la comparación con la historia 1984-hoy.
El nivel de cada curso es el mayor de los criterios. Los umbrales son iniciales y propios: hay que calibrarlos
con registros de crecidas (Autoridad del Agua de la Provincia, INA).
"""
import logging
import math
import re
import time

import httpx
from datetime import timedelta
from statistics import mean, median

from app.engine.geo import haversine_km, normalize, point_in_polygon
from app.engine.levels import LEVELS, idx, max_level
from app.util import utcnow

log = logging.getLogger("argwx.hydro")
VERSION = 3
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
FLOOD = "https://flood-api.open-meteo.com/v1/flood"
FORECAST = "https://api.open-meteo.com/v1/forecast"
QUERY = """[out:json][timeout:300];
area["ISO3166-2"="AR-B"]["boundary"="administrative"]->.a;
way["waterway"~"^(river|canal|stream)$"]["name"](area.a);
out tags geom;
node["place"~"^(city|town|village)$"]["name"](area.a);
out body;"""
EXCLUDE = set()  # el estuario se incluye, con evaluación costera independiente
PLACE_RANK = {"city": 0, "town": 1, "village": 2}

# Umbrales iniciales (a calibrar)
RAIN72 = {"YELLOW": 40, "ORANGE": 70, "RED": 110}   # mm promedio en los partidos que cruza el curso, 72 h
WET_30D = 150                                       # mm en 30 días: suelo cargado, sube un nivel
RECENT_7D = 50                                      # mm en 7 días: lluvia reciente que confirma una subida de caudal
RATIO = {"YELLOW": 2, "ORANGE": 4, "RED": 8}        # caudal máximo 7 días / caudal típico 3 semanas
MIN_RISE = 5.0                                      # m³/s: subidas menores no cuentan
MIN_Q = 1.0                                         # m³/s: por debajo, GloFAS no representa el cauce ahí
GLOFAS_KM = 15                                      # largo mínimo para consultar caudal
MAX_SAMPLES = 400                                   # tope de puntos de caudal por corrida
NEAR_KM = 4                                         # localidades ribereñas
PAST_DAYS, FUTURE_DAYS = 21, 8
# Humedad del suelo: el primer modelo/capa que responda (no todos los modelos tienen la misma capa).
SOIL_OPTIONS = [(None, "soil_moisture_9_to_27cm"), ("icon_seamless", "soil_moisture_9_to_27cm"),
                ("ecmwf_ifs025", "soil_moisture_7_to_28cm"), ("gfs_seamless", "soil_moisture_10_to_40cm")]


def _many(data):
    return data if isinstance(data, list) else [data]


def _get(client, url, params, timeout=120):
    """GET con reintentos: 429 (límite por minuto) y cortes de conexión, que en las APIs gratuitas son frecuentes."""
    for attempt in range(3):
        try:
            r = client.get(url, params=params, timeout=httpx.Timeout(timeout, connect=30))
        except httpx.TransportError as exc:
            if attempt == 2:
                raise
            log.warning("%s: %s; reintento", url, type(exc).__name__)
            time.sleep(20 * (attempt + 1))
            continue
        if r.status_code == 429 and attempt < 2:
            time.sleep(65)
            continue
        r.raise_for_status()
        return r.json()


def kind_of(name: str, waterways: set) -> str:
    n = normalize(name)
    if n.startswith(("arroyo", "ao ", "a ", "canada ", "zanjon ")):
        return "arroyo"
    if n.startswith("canal"):
        return "canal"
    if n.startswith(("rio ", "riacho ")):
        return "río"
    return "río" if "river" in waterways else "canal" if "canal" in waterways else "arroyo"


def ref_key(name: str) -> str:
    """'Río Salado' -> 'salado'; 'Salado (cuenca alta)' -> 'salado' (para unir con las estaciones de referencia)."""
    n = normalize(name.split("(")[0])
    return n[4:] if n.startswith("rio ") else n


# ------------------------------------------------------------------ geometría
def _bbox(pts):
    lats, lons = [p[0] for p in pts], [p[1] for p in pts]
    return (min(lats), min(lons), max(lats), max(lons))


def _gap_km(a, b) -> float:
    dlat = max(0.0, b[0] - a[2], a[0] - b[2])
    dlon = max(0.0, b[1] - a[3], a[1] - b[3])
    return math.hypot(dlat * 110.57, dlon * 111.32 * math.cos(math.radians((a[0] + a[2]) / 2)))


def _seg_km(p, a, b) -> float:
    """Distancia (km) del punto p al segmento ab, en proyección local."""
    kx, ky = 111.32 * math.cos(math.radians(p[0])), 110.57
    ax, ay, bx, by = (a[1] - p[1]) * kx, (a[0] - p[0]) * ky, (b[1] - p[1]) * kx, (b[0] - p[0]) * ky
    dx, dy = bx - ax, by - ay
    d2 = dx * dx + dy * dy
    t = 0.0 if d2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / d2))
    return math.hypot(ax + t * dx, ay + t * dy)


def simplify(pts: list, tol: float = 0.01) -> list:
    """Douglas-Peucker (tolerancia en grados, ~1 km): suficiente para dibujar y medir cercanía."""
    if len(pts) < 3:
        return list(pts)
    k = math.cos(math.radians(pts[0][0]))
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay, bx, by = pts[i][1] * k, pts[i][0], pts[j][1] * k, pts[j][0]
        dx, dy = bx - ax, by - ay
        d2 = dx * dx + dy * dy
        best, bi = 0.0, None
        for m in range(i + 1, j):
            px, py = pts[m][1] * k, pts[m][0]
            t = 0.0 if d2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / d2))
            d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > best:
                best, bi = d, m
        if bi is not None and best > tol:
            keep[bi] = True
            stack += [(i, bi), (bi, j)]
    return [p for p, f in zip(pts, keep) if f]


def _clusters(ways: list[dict], gap_km: float = 5) -> list[list[dict]]:
    """Tramos con el mismo nombre que se tocan (o casi) forman un mismo curso; si están lejos, son otro."""
    left, out = list(range(len(ways))), []
    while left:
        comp, queue = [], [left.pop()]
        while queue:
            i = queue.pop()
            comp.append(ways[i])
            near = [j for j in left if _gap_km(ways[i]["bb"], ways[j]["bb"]) <= gap_km]
            for j in near:
                left.remove(j)
            queue.extend(near)
        out.append(comp)
    return out


def _farthest(points: list, k: int) -> list:
    if len(points) <= k:
        return list(points)
    chosen = [points[0]]
    while len(chosen) < k:
        chosen.append(max(points, key=lambda p: min(haversine_km(p[0], p[1], c[0], c[1]) for c in chosen)))
    return chosen


def _partido_index(geojson: dict) -> list[tuple]:
    out = []
    for f in geojson["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        rings = [[(c[1], c[0]) for c in p[0]] for p in polys]
        out.append((f["properties"]["id"], rings, _bbox([pt for r in rings for pt in r])))
    return out


def partido_at(lat, lon, index, munis, near_km: float = 8) -> str | None:
    for pid, rings, (a, c, b, d) in index:
        if a <= lat <= b and c <= lon <= d and any(point_in_polygon(lat, lon, r) for r in rings):
            return pid
    near = min(munis, key=lambda m: haversine_km(lat, lon, m["lat"], m["lon"]))
    return near["id"] if haversine_km(lat, lon, near["lat"], near["lon"]) <= near_km else None


# ------------------------------------------------------------------ red hídrica (OpenStreetMap)
def fetch_network_elements(client) -> list[dict]:
    errors = []
    for url in OVERPASS:
        try:
            r = client.post(url, data={"data": QUERY}, timeout=360)
            r.raise_for_status()
            elements = r.json()["elements"]
            if any(e.get("type") == "way" for e in elements):
                return elements
            errors.append(f"{url}: respuesta sin cursos de agua")
        except Exception as exc:
            errors.append(f"{url}: {type(exc).__name__}: {exc}"[:200])
    raise RuntimeError("Overpass no respondió: " + " | ".join(errors))


def build_network(elements: list[dict], geojson: dict, munis: list[dict]) -> dict:
    index = _partido_index(geojson)
    places = []
    for e in elements:
        tags = e.get("tags") or {}
        if e.get("type") == "node" and "lat" in e and tags.get("name"):
            places.append({"nombre": tags["name"], "rank": PLACE_RANK.get(tags.get("place"), 3), "lat": e["lat"],
                           "lon": e["lon"], "partido": partido_at(e["lat"], e["lon"], index, munis)})
    groups: dict[str, dict] = {}
    for e in elements:
        tags = e.get("tags") or {}
        name = tags.get("name")
        pts = [(g["lat"], g["lon"]) for g in (e.get("geometry") or []) if g]
        if e.get("type") != "way" or not name or len(pts) < 2 or normalize(name) in EXCLUDE:
            continue
        km = sum(haversine_km(*pts[i], *pts[i + 1]) for i in range(len(pts) - 1))
        groups.setdefault(normalize(name), {"name": name, "ways": []})["ways"].append(
            {"pts": pts, "km": km, "bb": _bbox(pts), "ww": tags.get("waterway")})

    courses, used = [], set()
    for g in groups.values():
        for comp in _clusters(g["ways"]):
            tipo = kind_of(g["name"], {w["ww"] for w in comp})
            km = sum(w["km"] for w in comp)
            lines = [simplify(w["pts"], 0.0002) for w in comp]
            verts = [(p[0], p[1], partido_at(p[0], p[1], index, munis)) for ln in lines for p in ln]
            partidos = list(dict.fromkeys(v[2] for v in verts if v[2]))
            if not partidos:
                continue
            bb = _bbox([p for ln in lines for p in ln])
            segs = [(a, b) for ln in lines for a, b in zip(ln, ln[1:])]
            near = []
            for pl in places:
                if not (bb[0] - 0.05 <= pl["lat"] <= bb[2] + 0.05 and bb[1] - 0.06 <= pl["lon"] <= bb[3] + 0.06):
                    continue
                d = min(_seg_km((pl["lat"], pl["lon"]), a, b) for a, b in segs)
                if d <= NEAR_KM:
                    near.append((pl["rank"], d, pl))
            near.sort(key=lambda x: (x[0], x[1]))
            base = normalize(g["name"]).replace(" ", "-")
            rid, n = base, 2
            while rid in used:
                rid, n = f"{base}-{n}", n + 1
            used.add(rid)
            courses.append({"id": rid, "nombre": g["name"], "tipo": tipo, "km": round(km, 1), "partidos": partidos,
                            "localidades": [[pl["nombre"], pl["partido"]] for _, _, pl in near[:15]],
                            "bbox": [round(x, 3) for x in bb],
                            "trazo": [[[round(a, 5), round(b, 5)] for a, b in ln] for ln in lines],
                            "_verts": [v for v in verts if v[2]]})

    # Puntos de caudal (GloFAS) sobre el cauce: más en los cursos más largos, sin repetir celda de 0,05°.
    seen, total = set(), 0
    for c in sorted(courses, key=lambda c: -c["km"]):
        c["muestras"] = []
        if c["km"] < GLOFAS_KM or total >= MAX_SAMPLES:
            continue
        for lat, lon, pid in _farthest(c["_verts"], min(4, 1 + int(c["km"] // 60))):
            cell = (round(lat * 20), round(lon * 20))
            if cell in seen or total >= MAX_SAMPLES:
                continue
            seen.add(cell)
            total += 1
            c["muestras"].append({"lat": round(lat, 3), "lon": round(lon, 3), "partido": pid})
    for c in courses:
        c.pop("_verts")
    courses.sort(key=lambda c: (c["tipo"] != "río", -c["km"], c["nombre"]))
    return {"version": VERSION, "fuente": "OpenStreetMap (Overpass API) · © colaboradores de OpenStreetMap, ODbL",
            "cursos": courses}


# ------------------------------------------------------------------ agua en el suelo y lluvia reciente
def soil_category(sm: float | None) -> str | None:
    """Humedad volumétrica (m³/m³). Bandas orientativas: varían con el tipo de suelo."""
    if sm is None:
        return None
    return "muy húmedo" if sm >= 0.40 else "húmedo" if sm >= 0.30 else "adecuado" if sm >= 0.15 else "seco"


def _soil_now(loc: dict, var: str) -> float | None:
    vals = (loc.get("hourly") or {}).get(var) or []
    hour = (utcnow() - timedelta(hours=3)).hour  # hora argentina: índice dentro del día de hoy
    if hour < len(vals) and vals[hour] is not None:
        return vals[hour]
    return next((v for v in vals if v is not None), None)


def fetch_soil(client, munis: list[dict]) -> dict:
    out, option = {}, None
    for i in range(0, len(munis), 50):
        batch = munis[i:i + 50]
        base = {"latitude": ",".join(f"{m['lat']:.3f}" for m in batch),
                "longitude": ",".join(f"{m['lon']:.3f}" for m in batch), "timezone": "America/Argentina/Buenos_Aires"}
        rain = _many(_get(client, FORECAST, {**base, "daily": "precipitation_sum", "past_days": 30, "forecast_days": 1}))
        soil = None
        for model, var in ([option] if option else SOIL_OPTIONS):
            extra = {"models": model} if model else {}
            try:
                data = _many(_get(client, FORECAST, {**base, "hourly": var, "forecast_days": 1, **extra}))
            except Exception as exc:
                log.warning("Humedad del suelo %s/%s: %s", model, var, exc)
                continue
            if any(_soil_now(loc, var) is not None for loc in data):
                soil, option = data, (model, var)
                break
        for j, (m, r) in enumerate(zip(batch, rain)):
            daily = [v for v in ((r.get("daily") or {}).get("precipitation_sum") or [])[:30] if v is not None]
            sm = _soil_now(soil[j], option[1]) if soil else None
            out[m["id"]] = {"lluvia_30d": round(sum(daily), 1) if daily else None,
                            "lluvia_7d": round(sum(daily[-7:]), 1) if daily else None,
                            "humedad_suelo": round(sm, 3) if sm is not None else None, "suelo": soil_category(sm)}
        time.sleep(2)
    model, var = option or (None, None)
    layer = var.replace("soil_moisture_", "").replace("_to_", "-").replace("cm", " cm") if var else None
    return {"fuente": "Open-Meteo: lluvia de los últimos 30 días y humedad del suelo "
                      f"({layer or 'sin datos'}, modelo {model or 'de mejor ajuste'})",
            "nota": "Bandas orientativas de humedad: seco < 0,15; adecuado < 0,30; húmedo < 0,40; muy húmedo ≥ 0,40 m³/m³. "
                    "Es un valor de modelo, no una medición en el lote: sirve para comparar partidos, no para decidir "
                    "una labor.",
            "municipios": out}


# ------------------------------------------------------------------ caudales (GloFAS)
def _key(s: dict) -> str:
    return f"{s['lat']},{s['lon']}"


def fetch_discharge(client, samples: list[dict]) -> dict:
    out = {}
    for i in range(0, len(samples), 50):
        batch = samples[i:i + 50]
        data = _many(_get(client, FLOOD, {"latitude": ",".join(str(s["lat"]) for s in batch),
                                          "longitude": ",".join(str(s["lon"]) for s in batch),
                                          "daily": "river_discharge,river_discharge_median",
                                          "past_days": PAST_DAYS, "forecast_days": FUTURE_DAYS}, timeout=180))
        for s, loc in zip(batch, data):
            d = loc.get("daily") or {}
            out[_key(s)] = {"time": d.get("time") or [], "q": d.get("river_discharge") or [],
                            "med": d.get("river_discharge_median") or []}
        if i + 50 < len(samples):
            time.sleep(12)  # Open-Meteo limita las consultas por minuto
    return out


def point_status(series: dict | None, today: str) -> dict | None:
    if not series or not series.get("time"):
        return None
    t, q, med = series["time"], series["q"], series.get("med") or []
    i = t.index(today) if today in t else (PAST_DAYS if len(t) > PAST_DAYS else None)
    if i is None:
        return None
    past = [v for v in q[:i] if v is not None]
    if len(past) < 14:
        return None
    base = median(past)
    if base < MIN_Q:
        return {"representado": False, "q_tipico": round(base, 2)}
    fut = []
    for j in range(i, min(i + 7, len(t))):
        v = med[j] if j < len(med) and med[j] is not None else (q[j] if j < len(q) else None)
        if v is not None:
            fut.append((t[j], v))
    if not fut:
        return None
    peak_t, fmax = max(fut, key=lambda x: x[1])
    ratio = fmax / base
    level = "GREEN"
    if fmax - base >= MIN_RISE:
        for name, r in RATIO.items():
            if ratio >= r:
                level = name
    return {"representado": True, "q_hoy": round(q[i], 1) if i < len(q) and q[i] is not None else None,
            "q_tipico": round(base, 1), "q_max_7d": round(fmax, 1), "relacion": round(ratio, 1),
            "pico": peak_t, "nivel": level}


def export_discharge(client, network: dict) -> dict:
    samples = [s for c in network["cursos"] for s in c["muestras"]]
    raw = fetch_discharge(client, samples)
    today = utcnow().date().isoformat()
    pts = {k: st for k, st in ((_key(s), point_status(raw.get(_key(s)), today)) for s in samples) if st}
    return {"hoy": today, "fuente": "GloFAS (Copernicus) vía Open-Meteo Flood API", "puntos": pts}


# ------------------------------------------------------------------ estado de crecida por curso
def rain_level(basin_rain: float | None, basin_30d: float | None) -> str:
    level = "GREEN"
    for name, limit in RAIN72.items():
        if basin_rain is not None and basin_rain >= limit:
            level = name
    if basin_30d is not None and basin_30d >= WET_30D and (basin_rain or 0) >= 20:
        level = LEVELS[min(idx(level) + 1, idx("RED"))] if level != "GREEN" else "YELLOW"
    return level


def _dm(day: str | None) -> str:
    """'2026-11-07' -> '7/11'."""
    return f"{int(day[8:10])}/{int(day[5:7])}" if day else "–"


def rain72_by_partido(alertas: dict | None) -> dict:
    """Suma de las medianas de lluvia de las ventanas 0-24, 24-48 y 48-72 h de alertas_pba.json."""
    vals: dict[str, list] = {}
    for w in ("24", "48", "72"):
        for m in ((alertas or {}).get("windows", {}).get(w) or {}).get("municipios", []):
            vals.setdefault(m["id"], []).append(m.get("lluvia_mm"))
    return {k: round(sum(v), 1) for k, v in vals.items() if len(v) == 3 and None not in v}


def _near_course(lat, lon, course, km=5.0) -> bool:
    segs = [(a, b) for ln in course["trazo"] for a, b in zip(ln, ln[1:])]
    bb = course["bbox"]
    if not segs or not (bb[0] - 0.06 <= lat <= bb[2] + 0.06 and bb[1] - 0.07 <= lon <= bb[3] + 0.07):
        return False
    return min(_seg_km((lat, lon), a, b) for a, b in segs) <= km


def _river_key(name: str | None) -> str:
    k = re.sub(r"[^a-z]", "", normalize(name or ""))
    k = re.sub(r"^(rio|arroyo|canal)", "", k)
    return re.sub(r"(inferior|superior|inf|sup|medio)$", "", k)


def same_river(station_river: str | None, course_name: str) -> bool:
    """Une la escala con el curso por nombre (si la escala lo informa) además de la cercanía."""
    sk = _river_key(station_river)
    return not sk or sk in _river_key(course_name) or _river_key(course_name) in sk


def compute_floods(network: dict, caudales: dict | None, soil: dict | None, rain72: dict, refs: dict | None,
                   names: dict, observed: dict | None = None) -> dict:
    status = (caudales or {}).get("puntos", {})
    soil_m = (soil or {}).get("municipios", {})
    ref_by: dict[str, list] = {}
    for r in (refs or {}).get("rios", []):
        ref_by.setdefault(ref_key(r["rio"]), []).append(r)
    # Ríos de referencia que no están en la red de OpenStreetMap (p. ej. el Negro, cuyo cauce es el límite
    # provincial): se agregan igual para que su estado figure en la lista.
    mapped = {ref_key(c["nombre"]) for c in network["cursos"] if c["tipo"] == "río"}
    extra = []
    for key, rs in ref_by.items():
        if key in mapped:
            continue
        lat, lon = rs[0]["lat"], rs[0]["lon"]
        extra.append({"id": "ref-" + key.replace(" ", "-"), "nombre": "Río " + rs[0]["rio"].split(" (")[0], "tipo": "río",
                      "km": None, "partidos": list(dict.fromkeys(p for r in rs for p in r["partidos"])),
                      "localidades": [], "muestras": [], "trazo": [],
                      "bbox": [round(lat - 0.25, 3), round(lon - 0.3, 3), round(lat + 0.25, 3), round(lon + 0.3, 3)]})
    out = []
    for c in network["cursos"] + extra:
        rains = [(p, rain72[p]) for p in c["partidos"] if rain72.get(p) is not None]
        basin = round(mean(v for _, v in rains), 1) if rains else None
        wet = [soil_m[p]["lluvia_30d"] for p in c["partidos"] if (soil_m.get(p) or {}).get("lluvia_30d") is not None]
        basin30 = round(mean(wet), 1) if wet else None
        recent = [soil_m[p]["lluvia_7d"] for p in c["partidos"] if (soil_m.get(p) or {}).get("lluvia_7d") is not None]
        basin7 = round(mean(recent), 1) if recent else None
        # El estuario exige alturas/mareas/viento; un conducto urbano exige un
        # modelo pluvial local. No transformar lluvia municipal en crecida allí.
        special = c.get("monitoreo") in ("costero", "urbano")
        if special:
            rains, basin, basin30, basin7 = [], None, None, None
        lv_rain = rain_level(basin, basin30)
        # Ríos con punto de referencia: se usa ese punto (cauce principal, historia 1984-hoy) y no los puntos de la
        # red, que en ríos anchos o en el delta pueden caer en celdas de GloFAS fuera del cauce principal.
        ref = ref_by.get(ref_key(c["nombre"])) if c["tipo"] == "río" and not special else None
        lv_ref = max_level(*(r["nivel_7d"] for r in ref)) if ref else "GREEN"
        pts = [] if ref or special else [{**s, **status[_key(s)]} for s in c["muestras"] if _key(s) in status]
        rep = [p for p in pts if p.get("representado")]
        lv_model = max_level(*(p["nivel"] for p in rep)) if rep else "GREEN"
        # Como en el consenso del motor, una sola fuente no alcanza para Naranja o Roja: la subida de caudal de
        # GloFAS frente a las últimas 3 semanas queda en Amarilla salvo que la confirme la lluvia (prevista, de la
        # última semana o del último mes).
        confirmed = idx(lv_rain) >= 1 or (basin7 or 0) >= RECENT_7D or (basin30 or 0) >= WET_30D
        lv_flow = lv_model if confirmed else LEVELS[min(idx(lv_model), 1)]
        # Escalas oficiales (Prefectura / Red Hidrológica Nacional) sobre el curso: la observación prevalece.
        obs = [st for st in (observed or {}).get("estaciones", [])
               if same_river(st.get("rio"), c["nombre"]) and _near_course(st["lat"], st["lon"], c)]
        classified_obs = [st for st in obs if st.get("alerta") is not None or st.get("evacuacion") is not None]
        lv_obs = max_level(*(st["nivel"] for st in classified_obs)) if classified_obs else "GREEN"
        level = max_level(lv_rain, lv_flow, lv_ref, lv_obs)
        evaluated = bool(rains or rep or ref or classified_obs)
        if not evaluated:
            level = None

        motivos = []
        if not evaluated:
            motivos.append("Sin evaluación hidrológica: no hay datos aplicables a este tramo. No equivale a ausencia de riesgo.")
        if c.get("monitoreo") == "costero":
            motivos.append("Estuario: estado de las alturas observadas disponibles, no pronóstico de sudestada. Mareas y viento requieren un modelo costero específico.")
        elif c.get("monitoreo") == "urbano":
            motivos.append("Cauce urbano: el inventario no estima capacidad de conductos ni anegamiento de calles.")
        if basin is not None:
            where = f"promedio de {len(rains)} partidos" if len(rains) > 1 else f"en {names.get(rains[0][0], rains[0][0])}"
            motivos.append(f"Lluvia prevista en la cuenca: {basin:g} mm en 72 h ({where})")
            top_p, top_v = max(rains, key=lambda x: x[1])
            if len(rains) > 1 and top_v >= RAIN72["YELLOW"]:
                motivos.append(f"Máximo en {names.get(top_p, top_p)}: {top_v:g} mm")
        if basin30 is not None and basin30 >= WET_30D:
            motivos.append(f"Suelo cargado: {basin30:g} mm de lluvia en los últimos 30 días")
        hot = sorted((p for p in rep if p["nivel"] != "GREEN"), key=lambda p: (-idx(p["nivel"]), p["pico"]))
        if hot:
            h = hot[0]
            motivos.append(f"Caudal (GloFAS) en {names.get(h['partido'], h['partido'])}: de {h['q_tipico']:g} a "
                           f"{h['q_max_7d']:g} m³/s ({h['relacion']:g} veces el típico de las últimas 3 semanas); pico "
                           f"estimado el {_dm(h['pico'])}")
            if idx(lv_model) > idx(lv_flow):
                motivos.append("Señal de un solo modelo, sin lluvia fuerte que la confirme: se informa como Amarilla")
        for st in obs:
            if st["nivel"] != "GREEN":
                motivos.append(f"Altura observada en {st['estacion']}: {st['altura_m']:g} m (alerta {st['alerta']} m, "
                               f"evacuación {st['evacuacion']} m) · {st['red']}")
        for r in ref or []:
            if r["nivel_7d"] != "GREEN":
                motivos.append(f"Punto de referencia GloFAS en {r['lugar']}: caudal {r['estado_7d'].lower()} frente "
                               "a la historia 1984-hoy del modelo")

        # Señal: dónde se detecta (caudal, lluvia fuerte o estación de referencia). Si el curso tiene alerta, el agua
        # recorre todo el cauce: se listan todos los partidos que cruza, primero los de la señal.
        senal, afectados = [], []
        if level is not None and level != "GREEN":
            senal += [p["partido"] for p in hot]
            senal += [p for p, v in sorted(rains, key=lambda x: -x[1]) if v >= RAIN72["YELLOW"]]
            senal += [p for r in ref or [] if r["nivel_7d"] != "GREEN" for p in r["partidos"] if p in c["partidos"]]
            senal = list(dict.fromkeys(senal))
            afectados = list(dict.fromkeys(senal + c["partidos"]))
        locs = sorted((loc for loc in c["localidades"] if loc[1] in afectados), key=lambda loc: loc[1] not in senal)
        out.append({**{k: c[k] for k in ("alias", "cuencas", "cuenca_ids", "fuentes", "jurisdicciones", "sin_nombre", "monitoreo", "nota", "area", "registros") if k in c},
                    "id": c["id"], "nombre": c["nombre"], "tipo": c["tipo"], "km": c["km"], "nivel": level,
                    "evaluado": evaluated,
                    "nivel_lluvia": lv_rain, "nivel_caudal": lv_flow, "caudal_confirmado": bool(rep) and confirmed,
                    "nivel_referencia": lv_ref if ref else None, "lluvia_72h": basin, "lluvia_7d": basin7,
                    "lluvia_30d": basin30, "motivos": motivos, "partidos": c["partidos"],
                    "partidos_senal": senal, "partidos_afectados": afectados, "localidades_afectadas": locs,
                    "localidades": c["localidades"], "pico": min((p["pico"] for p in hot), default=None),
                    "con_caudal": bool(rep or ref), "puntos": pts, "bbox": c["bbox"], "trazo": c["trazo"],
                    "nivel_observado": lv_obs if classified_obs else None,
                    "observado": [{k: st.get(k) for k in ("estacion", "altura_m", "alerta", "evacuacion", "estado", "nivel",
                                                          "fecha", "cambio_24h")} for st in obs]})
    out.sort(key=lambda x: (-idx(x["nivel"]), -(x["lluvia_72h"] or 0), -(x["km"] or 0)))
    por_nivel = {lv: sum(1 for x in out if x["nivel"] == lv) for lv in LEVELS[:4]}
    return {
        "resumen": {"cursos": len(out), "por_nivel": por_nivel, "en_alerta": sum(idx(x["nivel"]) > 0 for x in out),
                    "con_caudal": sum(1 for x in out if x["con_caudal"]),
                    "evaluados": sum(1 for x in out if x["evaluado"]),
                    "sin_evaluacion": sum(1 for x in out if not x["evaluado"]),
                    "por_tipo": {t: sum(1 for x in out if x["tipo"] == t) for t in ("río", "canal", "arroyo", "estuario")},
                    "fecha_caudal": (caudales or {}).get("hoy")},
        "metodo": "Nivel = el mayor entre (a) la lluvia prevista a 72 h en los partidos que cruza el curso "
                  f"(Amarilla ≥ {RAIN72['YELLOW']} mm, Naranja ≥ {RAIN72['ORANGE']}, Roja ≥ {RAIN72['RED']}; sube un "
                  f"nivel si llovió ≥ {WET_30D} mm en 30 días), (b) el caudal GloFAS de los próximos 7 días respecto "
                  f"del típico de las últimas 3 semanas (Amarilla ≥ {RATIO['YELLOW']}×, Naranja ≥ {RATIO['ORANGE']}×, "
                  f"Roja ≥ {RATIO['RED']}×, con una subida mínima de {MIN_RISE:g} m³/s; sin lluvia que lo confirme "
                  f"—≥ {RAIN72['YELLOW']} mm previstos, ≥ {RECENT_7D} mm en 7 días o ≥ {WET_30D} mm en 30 días— queda en "
                  "Amarilla, porque es una sola fuente) y (c) en los ríos con punto de referencia GloFAS, el caudal "
                  "frente a su historia 1984-hoy. Umbrales iniciales, a calibrar.",
        "nota": "GloFAS representa bien los ríos grandes; en arroyos chicos y en la llanura del Salado pesa más el "
                "criterio de lluvia. Si un curso tiene alerta se listan todos los partidos que cruza (primero donde "
                "está la señal) y las localidades a menos de 4 km del cauce: es una referencia de cercanía, no un "
                "mapa de zonas inundables. Suelo cargado y crecidas pueden demorar la siembra y "
                "la cosecha y afectar cultivos en lotes bajos.",
        "cobertura": network.get("cobertura"), "cartografia": network.get("fuentes", []),
        "fuentes": "Red hídrica: DPH Buenos Aires, IGN, GCBA y © colaboradores de OpenStreetMap (ODbL). Caudales: GloFAS "
                   "(Copernicus). Lluvia: 9 modelos vía Open-Meteo.",
        "cursos": out}
