"""Fuentes gratuitas complementarias (sin clave), todas probadas en el CI:

- Ríos: caudal pronosticado e histórico de GloFAS (Copernicus) vía Open-Meteo Flood API.
- Costa: altura de olas (Open-Meteo Marine API).
- Ambiente: índice UV y material particulado PM2.5 (CAMS vía Open-Meteo Air Quality API).
- Probabilidades: ensamble ECMWF de 51 escenarios (Open-Meteo Ensemble API).
- Observaciones: estaciones del SMN ("tiempo presente", datos abiertos).

Los puntos de referencia de ríos y costa son aproximados (ver docstrings); el valor siempre lo da la fuente.
"""
import io
import logging
import re
import time
import unicodedata
import zipfile
from datetime import date
from statistics import quantiles

from app.engine.geo import haversine_km

log = logging.getLogger("argwx.extras")
FLOOD = "https://flood-api.open-meteo.com/v1/flood"
MARINE = "https://marine-api.open-meteo.com/v1/marine"
AIR = "https://air-quality-api.open-meteo.com/v1/air-quality"
ENSEMBLE = "https://ensemble-api.open-meteo.com/v1/ensemble"
SMN_ZIP = "https://ssl.smn.gob.ar/dpd/zipopendata.php"


def _get(client, url, params, timeout=90):
    for attempt in range(2):
        r = client.get(url, params=params, timeout=timeout)
        if r.status_code == 429 and not attempt:
            time.sleep(65)
            continue
        r.raise_for_status()
        return r.json()


def _many(data):
    return data if isinstance(data, list) else [data]


# ------------------------------------------------------------------ ríos (GloFAS)
# Puntos de referencia aproximados: se busca alrededor (±0,15°) la celda con más caudal (el cauce).
RIVERS = [
    {"id": "parana-san-nicolas", "rio": "Paraná", "lugar": "San Nicolás - Ramallo", "lat": -33.33, "lon": -60.21,
     "partidos": ["san-nicolas", "ramallo", "san-pedro"]},
    {"id": "parana-zarate", "rio": "Paraná de las Palmas", "lugar": "Zárate - Campana", "lat": -34.09, "lon": -59.02,
     "partidos": ["zarate", "campana", "escobar", "tigre", "san-fernando"]},
    {"id": "lujan", "rio": "Luján", "lugar": "Luján", "lat": -34.56, "lon": -59.11,
     "partidos": ["lujan", "pilar", "escobar", "exaltacion-de-la-cruz"]},
    {"id": "salado-belgrano", "rio": "Salado", "lugar": "General Belgrano", "lat": -35.77, "lon": -58.50,
     "partidos": ["general-belgrano", "monte", "lobos", "roque-perez", "chascomus", "las-flores", "pila", "castelli"]},
    {"id": "salado-junin", "rio": "Salado (cuenca alta)", "lugar": "Junín - Bragado", "lat": -34.80, "lon": -60.70,
     "partidos": ["junin", "bragado", "chacabuco", "alberti", "9-de-julio", "25-de-mayo"]},
    {"id": "quequen", "rio": "Quequén Grande", "lugar": "Necochea", "lat": -38.55, "lon": -58.75,
     "partidos": ["necochea", "loberia"]},
    {"id": "negro", "rio": "Negro", "lugar": "Carmen de Patagones", "lat": -40.80, "lon": -62.98,
     "partidos": ["patagones"]},
]


def _neighborhood(lat, lon, radius=0.15, step=0.05):
    n = round(radius / step)
    return [(round(lat + i * step, 3), round(lon + j * step, 3)) for i in range(-n, n + 1) for j in range(-n, n + 1)]


def _pick_channel(client, river) -> tuple[float, float]:
    cells = _neighborhood(river["lat"], river["lon"])
    data = _many(_get(client, FLOOD, {"latitude": ",".join(str(a) for a, _ in cells),
                                      "longitude": ",".join(str(b) for _, b in cells),
                                      "daily": "river_discharge", "past_days": 30, "forecast_days": 1}))
    best, best_q = cells[0], -1.0
    for cell, loc in zip(cells, data):
        q = [v for v in (loc.get("daily") or {}).get("river_discharge") or [] if v is not None]
        if q and sum(q) / len(q) > best_q:
            best, best_q = cell, sum(q) / len(q)
    return best


def river_status(forecast_max: float, ref: dict) -> tuple[str, str]:
    if forecast_max >= ref["max"]:
        return "RED", "Récord histórico"
    if forecast_max >= ref["p98"]:
        return "ORANGE", "Muy alto"
    if forecast_max >= ref["p90"]:
        return "YELLOW", "Alto"
    return "GREEN", "Normal"


def export_rivers(client, cached: dict | None) -> dict:
    """Caudal de los próximos 30 días vs. percentiles históricos 1984-hoy de la misma celda."""
    prev = {r["id"]: r for r in (cached or {}).get("rios", [])}
    out = []
    for river in RIVERS:
        old = prev.get(river["id"], {}).get("ref")
        if old and (date.today() - date.fromisoformat(old["calculado"])).days <= 30:
            ref = old
        else:
            lat, lon = _pick_channel(client, river)
            hist = _get(client, FLOOD, {"latitude": lat, "longitude": lon, "daily": "river_discharge",
                                        "start_date": "1984-01-01", "end_date": date.today().isoformat()}, timeout=180)
            q = sorted(v for v in hist["daily"]["river_discharge"] if v is not None)
            cuts = quantiles(q, n=100)
            ref = {"lat": lat, "lon": lon, "p50": round(cuts[49], 1), "p90": round(cuts[89], 1),
                   "p98": round(cuts[97], 1), "max": round(q[-1], 1), "desde": hist["daily"]["time"][0],
                   "calculado": date.today().isoformat()}
        fc = _get(client, FLOOD, {"latitude": ref["lat"], "longitude": ref["lon"],
                                  "daily": "river_discharge,river_discharge_median,river_discharge_max",
                                  "past_days": 3, "forecast_days": 30})
        d = fc["daily"]
        times, mean_q = d["time"], d.get("river_discharge") or []
        # Estado con la mediana del ensamble (lo esperable); el máximo es solo el peor escenario.
        med_q = [m if m is not None else q for m, q in zip(d.get("river_discharge_median") or mean_q, mean_q)]
        max_q = d.get("river_discharge_max") or []
        today_i = min(3, len(times) - 1)
        week = [v for v in med_q[today_i:today_i + 7] if v is not None]
        month = [v for v in med_q[today_i:] if v is not None]
        worst = [v for v in max_q[today_i:] if v is not None]
        now_q = mean_q[today_i] if today_i < len(mean_q) else None
        level, label = river_status(max(week) if week else 0, ref)
        level30, label30 = river_status(max(month) if month else 0, ref)
        trend = None
        if now_q and len(mean_q) > today_i + 7 and mean_q[today_i + 7] is not None:
            ch = (mean_q[today_i + 7] - now_q) / now_q
            trend = "crece" if ch > 0.1 else "baja" if ch < -0.1 else "estable"
        out.append({**{k: river[k] for k in ("id", "rio", "lugar", "partidos")}, "lat": ref["lat"], "lon": ref["lon"],
                    "caudal_hoy": now_q, "max_7d": max(week) if week else None, "max_30d": max(month) if month else None,
                    "nivel_7d": level, "estado_7d": label, "nivel_30d": level30, "estado_30d": label30,
                    "peor_escenario_30d": max(worst) if worst else None,
                    "tendencia": trend, "ref": ref, "serie": {"time": times[today_i:], "q": med_q[today_i:]}})
    return {"fuente": "GloFAS (Copernicus) vía Open-Meteo Flood API", "unidad": "m³/s",
            "metodo": "Caudal pronosticado (mediana del ensamble) vs. percentiles históricos de la misma celda "
                      "(1984-hoy): Alto ≥ p90, Muy alto ≥ p98, Rojo si supera el máximo registrado.", "rios": out}


# ------------------------------------------------------------------ costa (olas)
# Puntos en el mar (~10 km de la costa), aproximados, frente a cada partido costero.
COAST = [
    {"id": "la-costa", "lugar": "San Clemente - Mar de Ajó", "lat": -36.40, "lon": -56.55},
    {"id": "pinamar", "lugar": "Pinamar", "lat": -37.12, "lon": -56.75},
    {"id": "villa-gesell", "lugar": "Villa Gesell", "lat": -37.28, "lon": -56.85},
    {"id": "mar-chiquita", "lugar": "Mar Chiquita", "lat": -37.75, "lon": -57.30},
    {"id": "general-pueyrredon", "lugar": "Mar del Plata", "lat": -38.05, "lon": -57.40},
    {"id": "general-alvarado", "lugar": "Miramar", "lat": -38.33, "lon": -57.75},
    {"id": "necochea", "lugar": "Necochea - Quequén", "lat": -38.65, "lon": -58.65},
    {"id": "tres-arroyos", "lugar": "Claromecó", "lat": -38.95, "lon": -60.05},
    {"id": "monte-hermoso", "lugar": "Monte Hermoso", "lat": -39.08, "lon": -61.25},
    {"id": "coronel-rosales", "lugar": "Pehuen Có", "lat": -39.10, "lon": -61.55},
]
WAVES = {"YELLOW": 2.5, "ORANGE": 3.5, "RED": 5.0}  # metros, umbrales iniciales propios


def wave_level(h: float | None) -> str:
    lvl = "GREEN"
    for name, limit in WAVES.items():
        if h is not None and h >= limit:
            lvl = name
    return lvl


def export_coast(client) -> dict:
    data = _many(_get(client, MARINE, {"latitude": ",".join(str(p["lat"]) for p in COAST),
                                       "longitude": ",".join(str(p["lon"]) for p in COAST),
                                       "hourly": "wave_height,wave_direction,wave_period", "forecast_days": 3,
                                       "timezone": "UTC", "timeformat": "unixtime"}))
    out = []
    for p, loc in zip(COAST, data):
        h = loc.get("hourly") or {}
        hs = h.get("wave_height") or []
        w24 = [v for v in hs[:24] if v is not None]
        w72 = [v for v in hs if v is not None]
        imax = hs.index(max(w72)) if w72 else None
        out.append({**p, "ola_ahora": hs[0] if hs else None, "ola_max_24h": max(w24) if w24 else None,
                    "ola_max_72h": max(w72) if w72 else None,
                    "hora_max": h["time"][imax] if imax is not None else None,
                    "direccion": (h.get("wave_direction") or [None])[imax or 0],
                    "periodo": (h.get("wave_period") or [None])[imax or 0],
                    "nivel": wave_level(max(w24) if w24 else None)})
    return {"fuente": "Open-Meteo Marine API", "umbrales_m": WAVES, "puntos": out}


# ------------------------------------------------------------------ ambiente (UV y aire)
def uv_category(uv: float | None) -> str | None:
    if uv is None:
        return None
    return "Extremo" if uv >= 11 else "Muy alto" if uv >= 8 else "Alto" if uv >= 6 else "Moderado" if uv >= 3 else "Bajo"


def export_air(client, munis: list[dict]) -> dict:
    out = {}
    for i in range(0, len(munis), 50):
        batch = munis[i:i + 50]
        data = _many(_get(client, AIR, {"latitude": ",".join(f"{m['lat']:.3f}" for m in batch),
                                        "longitude": ",".join(f"{m['lon']:.3f}" for m in batch),
                                        "hourly": "uv_index,pm2_5", "forecast_days": 2, "timezone": "UTC"}))
        for m, loc in zip(batch, data):
            h = loc.get("hourly") or {}
            uv = [v for v in (h.get("uv_index") or [])[:24] if v is not None]
            pm = [v for v in (h.get("pm2_5") or [])[:24] if v is not None]
            out[m["id"]] = {"uv_max": round(max(uv), 1) if uv else None, "uv_categoria": uv_category(max(uv) if uv else None),
                            "pm25_max": round(max(pm), 1) if pm else None,
                            "pm25_media": round(sum(pm) / len(pm), 1) if pm else None}
    return {"fuente": "CAMS (Copernicus) vía Open-Meteo Air Quality API",
            "nota": "UV: escala de la OMS. PM2.5: la guía de la OMS (2021) para el promedio de 24 h es 15 µg/m³.",
            "municipios": out}


# ------------------------------------------------------------------ probabilidades (ensamble ECMWF)
def export_probabilities(client, points: list[dict]) -> dict:
    data = _many(_get(client, ENSEMBLE, {"latitude": ",".join(str(p["lat"]) for p in points),
                                         "longitude": ",".join(str(p["lon"]) for p in points),
                                         "hourly": "precipitation", "models": "ecmwf_ifs025", "forecast_days": 3,
                                         "timezone": "UTC"}))
    out = []
    for p, loc in zip(points, data):
        h = loc.get("hourly") or {}
        members = [v for k, v in h.items() if k.startswith("precipitation")]
        res = {"id": p["id"], "name": p["name"], "miembros": len(members), "ventanas": {}}
        for w in (24, 48):
            totals = [sum(x for x in m[w - 24:w] if x is not None) for m in members if m]
            if not totals:
                continue
            n = len(totals)
            res["ventanas"][str(w)] = {"p_10mm": round(sum(t >= 10 for t in totals) / n, 2),
                                       "p_30mm": round(sum(t >= 30 for t in totals) / n, 2),
                                       "p_60mm": round(sum(t >= 60 for t in totals) / n, 2),
                                       "mediana_mm": round(sorted(totals)[n // 2], 1), "max_mm": round(max(totals), 1)}
        out.append(res)
    return {"fuente": "Ensamble ECMWF IFS (51 escenarios) vía Open-Meteo Ensemble API",
            "nota": "Probabilidad = proporción de escenarios del ensamble que superan el umbral en la ventana.",
            "puntos": out}


# ------------------------------------------------------------------ observaciones del SMN
def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().upper()
    return re.sub(r"[^A-Z0-9]+", " ", s).strip()


def parse_stations(text: str) -> dict[str, dict]:
    """estaciones_smn.txt (ancho fijo): NOMBRE, PROVINCIA, LAT [gr] [min], LON [gr] [min], ALTURA, NRO, OACI."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^(.{31})(\D+?)\s+(-?\d+)\s+(\d+)\s+(-?\d+)\s+(\d+)\s+(-?\d+)", line)
        if not m:
            continue
        name, prov = m.group(1).strip(), m.group(2).strip()
        lat = abs(int(m.group(3))) + int(m.group(4)) / 60
        lon = abs(int(m.group(5))) + int(m.group(6)) / 60
        out[_norm(name)] = {"name": name, "provincia": prov, "lat": -lat, "lon": -lon, "altura": int(m.group(7))}
    return out


STOP = {"AERO", "AEROPUERTO", "OBSERVATORIO", "BASE", "DE", "DEL", "LA", "EL", "SAN"}


def match_station(name: str, stations: dict[str, dict]) -> dict | None:
    """Une el nombre del parte (ej. 'Azul') con el listado (ej. 'AZUL AERO')."""
    key = _norm(name)
    if key in stations:
        return stations[key]
    pref = [v for k, v in stations.items() if k.startswith(key + " ")]
    if len(pref) >= 1:
        return pref[0]
    toks = set(key.split()) - STOP
    best, score = None, 0
    for k, v in stations.items():
        common = len(toks & (set(k.split()) - STOP))
        if common > score and k.split()[0] == key.split()[0]:
            best, score = v, common
    return best


def parse_present_weather(text: str) -> list[dict]:
    """estado_tiempo*.txt: estación;fecha;hora;estado;visibilidad;temperatura;sensación;humedad;viento;presión"""
    rows = []
    for line in text.splitlines():
        f = [x.strip() for x in line.split(";")]
        if len(f) < 9 or not f[0]:
            continue

        def num(x):
            try:
                return float(x.replace(",", "."))
            except ValueError:
                return None

        wind = re.match(r"^([A-Za-zÁÉÍÓÚáéíóú ]+?)\s+(\d+)$", f[8]) if len(f) > 8 else None
        rows.append({"estacion": f[0], "fecha": f[1], "hora": f[2], "estado": f[3], "visibilidad": f[4],
                     "temp_c": num(f[5]), "humedad": num(f[7]) if len(f) > 7 else None,
                     "viento_dir": wind.group(1).strip() if wind else (f[8] if len(f) > 8 else None),
                     "viento_kmh": float(wind.group(2)) if wind else None,
                     "presion_hpa": num(f[9].split("/")[0]) if len(f) > 9 else None})
    return rows


def _zip_text(client, dato: str) -> str:
    r = client.get(SMN_ZIP, params={"dato": dato}, timeout=60)
    r.raise_for_status()
    z = zipfile.ZipFile(io.BytesIO(r.content))
    return z.read(z.namelist()[0]).decode("latin-1")


def export_smn_observations(client, munis: list[dict]) -> dict:
    stations = parse_stations(_zip_text(client, "estaciones"))
    obs = parse_present_weather(_zip_text(client, "tiepre"))
    out, unmatched = [], []
    for o in obs:
        st = match_station(o["estacion"], stations)
        if not st:
            unmatched.append(o["estacion"])
            continue
        near = min(munis, key=lambda m: haversine_km(st["lat"], st["lon"], m["lat"], m["lon"]))
        dist = haversine_km(st["lat"], st["lon"], near["lat"], near["lon"])
        out.append({**o, "lat": round(st["lat"], 3), "lon": round(st["lon"], 3), "provincia": st["provincia"],
                    "municipio": near["id"] if st["provincia"].upper().startswith("BUENOS AIRES") and dist <= 40 else None})
    return {"fuente": "SMN - datos abiertos (tiempo presente)", "estaciones": out,
            "sin_ubicacion": unmatched}
