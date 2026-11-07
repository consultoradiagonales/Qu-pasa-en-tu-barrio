"""Base histórica pública (OSINT) para comparar pronósticos y calibrar probabilidades.

Tablas en data/historico/ (CSV) y derivados (JSON). Todas las fuentes son de uso público:
  lluvia_era5_diaria.csv        Lluvia diaria ERA5 (Copernicus/ECMWF, vía Open-Meteo) desde 1981 en un punto por
                                sección electoral. Se actualiza en forma incremental.
  verificacion_modelos.csv      Lluvia diaria pronosticada por cada modelo con 1, 2 y 3 días de anticipación
                                (Open-Meteo, corridas anteriores) y la observada por ERA5 ese día, en los mismos puntos.
  alertas_smn.csv               Registro de las alertas oficiales del SMN (API CAP) que lee cada corrida.
  smn_horarios_AAAA-MM.csv      Datos horarios de las estaciones bonaerenses del SMN (datos abiertos, día anterior).
  pronosticos_condi_AAAA-MM.csv Lo que pronosticó ConDi para cada partido, una vez por día (para verificarlo después).
  climatologia_lluvia.json      Frecuencia histórica de lluvias por mes (sale de lluvia_era5_diaria).
  calibracion.json              Verificación por modelo y probabilidades calibradas (sale de verificacion_modelos).
  catalogo.json                 Qué hay en cada tabla, de dónde sale, período y cantidad de registros.
"""
import csv
import io
import json
import logging
import time
import zipfile
from datetime import date, timedelta
from pathlib import Path

import httpx

from app.engine import calibration as cal
from app.providers.openmeteo import label
from app.util import iso, utcnow

log = logging.getLogger("argwx.historico")
ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
ARCHIVE_CUSTOMER = "https://customer-archive-api.open-meteo.com/v1/archive"
PREVIOUS = "https://previous-runs-api.open-meteo.com/v1/forecast"
SMN_ZIP = "https://ssl.smn.gob.ar/dpd/zipopendata.php"
TZ = "America/Argentina/Buenos_Aires"
START = date(1980, 12, 1)
ERA5_LAG_DAYS = 7          # ERA5 se publica con unos 5 días de demora
VERIF_DAYS = 400           # profundidad disponible de las corridas anteriores (verificado: desde 30/9/2025)
LEADS = (1, 2, 3)
ERA5_FILE, VERIF_FILE, ALERTS_FILE = "lluvia_era5_diaria.csv", "verificacion_modelos.csv", "alertas_smn.csv"
CLIMA_FILE, CALIB_FILE, CATALOG_FILE = "climatologia_lluvia.json", "calibracion.json", "catalogo.json"
WEIGHTED_FILE = "modelo_ponderado.json"


# ------------------------------------------------------------------ utilidades
def _get(client, url, params, timeout=180):
    for attempt in range(3):
        try:
            r = client.get(url, params=params, timeout=httpx.Timeout(timeout, connect=30))
        except httpx.TransportError:
            if attempt == 2:
                raise
            time.sleep(20 * (attempt + 1))
            continue
        if r.status_code == 429 and attempt < 2:
            time.sleep(65)
            continue
        return r
    return r


def read_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def _num(v):
    try:
        return float(v) if v not in (None, "") else None
    except ValueError:
        return None


def _today() -> date:
    return (utcnow() - timedelta(hours=3)).date()  # día en la Argentina


# ------------------------------------------------------------------ 1. lluvia observada (ERA5)
def fetch_era5(client, settings, points: list[dict], start: date, end: date) -> dict[str, dict[str, float]]:
    url = ARCHIVE_CUSTOMER if settings.open_meteo_api_key else ARCHIVE
    params = {"latitude": ",".join(str(p["lat"]) for p in points), "longitude": ",".join(str(p["lon"]) for p in points),
              "start_date": start.isoformat(), "end_date": end.isoformat(), "daily": "precipitation_sum",
              "timezone": TZ, "models": "era5"}
    if settings.open_meteo_api_key:
        params["apikey"] = settings.open_meteo_api_key
    r = _get(client, url, params, timeout=300)
    if r.status_code == 400:  # por si el modelo no se acepta: mejor combinación disponible del reanálisis
        params.pop("models")
        r = _get(client, url, params, timeout=300)
    r.raise_for_status()
    data = r.json()
    data = data if isinstance(data, list) else [data]
    out = {}
    for p, loc in zip(points, data):
        d = loc.get("daily") or {}
        out[p["id"]] = {t: v for t, v in zip(d.get("time") or [], d.get("precipitation_sum") or []) if v is not None}
    return out


def update_era5(client, settings, folder: Path, points: list[dict]) -> dict:
    """Agrega a lluvia_era5_diaria.csv los días que faltan (la primera vez trae desde 1981)."""
    path, ids = folder / ERA5_FILE, [p["id"] for p in points]
    rows = {r["fecha"]: r for r in read_csv(path)}
    complete = rows and all(i in next(iter(rows.values())) for i in ids)
    end = _today() - timedelta(days=ERA5_LAG_DAYS)
    start = max(date.fromisoformat(max(rows)) - timedelta(days=10), START) if complete else START
    if start <= end:
        new = fetch_era5(client, settings, points, start, end)
        for pid, series in new.items():
            for t, v in series.items():
                rows.setdefault(t, {"fecha": t})[pid] = round(v, 1)
    ordered = [rows[k] for k in sorted(rows)]
    write_csv(path, ["fecha", *ids], ordered)
    return {"dias": len(ordered), "desde": ordered[0]["fecha"] if ordered else None,
            "hasta": ordered[-1]["fecha"] if ordered else None, "nuevos_desde": start.isoformat()}


def era5_series(folder: Path, ids: list[str]) -> dict[str, dict]:
    """{punto: {"time": [...], "rain": [...]}} desde el CSV (para climatología y El Niño)."""
    rows = read_csv(folder / ERA5_FILE)
    return {pid: {"time": [r["fecha"] for r in rows], "rain": [_num(r.get(pid)) for r in rows]} for pid in ids}


def climatology_file(folder: Path, points: list[dict]) -> dict:
    ids = [p["id"] for p in points]
    series = era5_series(folder, ids)
    times = series[ids[0]]["time"] if ids else []
    if not times:
        raise RuntimeError("Sin serie ERA5")
    last_full = int(times[-1][:4]) - (0 if times[-1].endswith("12-31") else 1)  # solo años completos
    res = cal.climatology(series, max(int(times[0][:4]), 1981), last_full)
    res.update({"fuente": "ERA5 (Copernicus/ECMWF) vía Open-Meteo: lluvia diaria del reanálisis, no de pluviómetro",
                "por_seccion": {str(p["seccion"]): p["id"] for p in points},
                "puntos_info": {p["id"]: {"name": p["name"], "seccion": p["seccion"]} for p in points}})
    (folder / CLIMA_FILE).write_text(json.dumps(res, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return {"periodo": res["periodo"], "puntos": len(res["puntos"])}


# ------------------------------------------------------------------ 2. verificación de los modelos
def fetch_previous(client, point: dict, models: list[str], past_days: int) -> dict[tuple, dict]:
    """Lluvia diaria pronosticada por cada modelo con 1, 2 y 3 días de anticipación: {(fecha, plazo): {modelo: mm}}."""
    hourly = ",".join(f"precipitation_previous_day{lead}" for lead in LEADS)
    r = _get(client, PREVIOUS, {"latitude": point["lat"], "longitude": point["lon"], "hourly": hourly,
                                "models": ",".join(models), "past_days": past_days, "forecast_days": 1,
                                "timezone": TZ})
    r.raise_for_status()
    h = r.json().get("hourly") or {}
    times = h.get("time") or []
    out: dict[tuple, dict] = {}
    for m in models:
        for lead in LEADS:
            vals = h.get(f"precipitation_previous_day{lead}_{m}") or (h.get(f"precipitation_previous_day{lead}")
                                                                      if len(models) == 1 else None)
            if not vals:
                continue
            per_day: dict[str, list] = {}
            for t, v in zip(times, vals):
                per_day.setdefault(t[:10], []).append(v)
            for day, xs in per_day.items():
                if len(xs) >= 24 and None not in xs:  # solo días completos
                    out.setdefault((day, lead), {})[label(m)] = round(sum(xs), 1)
    return out


def update_verification(client, folder: Path, points: list[dict], models: list[str]) -> dict:
    path, labels = folder / VERIF_FILE, list(dict.fromkeys(label(m) for m in models))
    rows = {(r["fecha"], r["punto"], r["plazo"]): r for r in read_csv(path)}
    last = max((k[0] for k in rows), default=None)
    past = VERIF_DAYS if not last else min(VERIF_DAYS, (_today() - date.fromisoformat(last)).days + 5)
    today = _today().isoformat()
    for p in points:
        for (day, lead), fc in fetch_previous(client, p, models, past).items():
            if day >= today:
                continue
            row = rows.setdefault((day, p["id"], str(lead)), {"fecha": day, "punto": p["id"], "plazo": str(lead)})
            row.update(fc)
        time.sleep(2)
    obs = era5_series(folder, [p["id"] for p in points])
    obs_by = {pid: dict(zip(s["time"], s["rain"])) for pid, s in obs.items()}
    for (day, pid, _), row in rows.items():
        v = obs_by.get(pid, {}).get(day)
        row["observado"] = "" if v is None else v
    ordered = [rows[k] for k in sorted(rows)]
    write_csv(path, ["fecha", "punto", "plazo", "observado", *labels], ordered)
    with_obs = sum(1 for r in ordered if r["observado"] != "")
    return {"filas": len(ordered), "con_observacion": with_obs, "desde": ordered[0]["fecha"] if ordered else None}


def verification_rows(folder: Path, models: list[str]) -> list[dict]:
    """Pares pronóstico-observación en formato largo, desde verificacion_modelos.csv."""
    labels = list(dict.fromkeys(label(m) for m in models))
    long = []
    for r in read_csv(folder / VERIF_FILE):
        o = _num(r.get("observado"))
        if o is None:
            continue
        for lab in labels:
            f = _num(r.get(lab))
            if f is not None:
                long.append({"punto": r["punto"], "fecha": r["fecha"], "modelo": lab, "plazo": int(r["plazo"]),
                             "pronostico": f, "observado": o})
    return long


def weighted_model_file(folder: Path, models: list[str], points: list[dict]) -> dict:
    """Ajusta y valida el modelo ponderado ARGWX (ver app/engine/weighting.py)."""
    from app.engine import weighting

    long = verification_rows(folder, models)
    if not long:
        raise RuntimeError("Sin pares pronóstico-observación todavía")
    info = {p["id"]: {"name": p["name"], "seccion": p["seccion"]} for p in points}
    res = weighting.build_model_file(long, info)
    (folder / WEIGHTED_FILE).write_text(json.dumps(res, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    val = res["validacion"]
    return {"dias": res["dias"], "mejora_vs_mediana_pct": val.get("mejora_vs_mediana_pct")}


def calibration_file(folder: Path, models: list[str]) -> dict:
    labels = list(dict.fromkeys(label(m) for m in models))
    long = verification_rows(folder, models)
    if not long:
        raise RuntimeError("Sin pares pronóstico-observación todavía")
    days = sorted({x["fecha"] for x in long})
    res = {"periodo": [days[0], days[-1]], "dias": len(days), "pares": len(long), "modelos": labels,
           "verdad": "ERA5 (reanálisis): suaviza las tormentas locales; es la referencia común para todos los modelos",
           "verificacion": cal.verification(long), "calibracion": cal.calibration(long)}
    (folder / CALIB_FILE).write_text(json.dumps(res, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return {"dias": len(days), "pares": len(long)}


# ------------------------------------------------------------------ 3. SMN: registro de alertas y datos horarios
def update_alert_registry(folder: Path, smn_json: dict | None) -> dict:
    path = folder / ALERTS_FILE
    fields = ["visto", "desde", "hasta", "fenomeno", "nivel", "titulo", "provincias", "partidos_pba"]
    rows = read_csv(path)
    seen = {(r["titulo"], r["nivel"], r["desde"], r["provincias"]) for r in rows}
    now, added = iso(utcnow()), 0
    for a in (smn_json or {}).get("alerts", []):
        row = {"visto": now, "desde": a.get("valid_from") or "", "hasta": a.get("valid_to") or "",
               "fenomeno": a.get("hazard") or "", "nivel": a.get("level") or "", "titulo": a.get("title") or "",
               "provincias": "|".join(a.get("provincias") or []), "partidos_pba": "|".join(a.get("partidos_pba") or [])}
        key = (row["titulo"], row["nivel"], row["desde"], row["provincias"])
        if key not in seen:
            seen.add(key)
            rows.append(row)
            added += 1
    write_csv(path, fields, rows)
    return {"alertas": len(rows), "nuevas": added}


def parse_hourly(txt: str) -> list[dict]:
    """datohorario: FECHA HORA TEMP HUM PNM DD FF NOMBRE (ancho fijo). Sin lluvia: el SMN no la publica acá."""
    lines = txt.splitlines()
    head = next((ln for ln in lines if "NOMBRE" in ln), None)
    if head is None:
        return []
    col = head.index("NOMBRE")
    out = []
    for ln in lines:
        parts = ln[:col].split()
        if len(parts) != 7 or not (parts[0].isdigit() and len(parts[0]) == 8):
            continue
        d = parts[0]
        out.append({"fecha": f"{d[4:8]}-{d[2:4]}-{d[0:2]}", "hora": int(parts[1]), "temp_c": _num(parts[2]),
                    "humedad": _num(parts[3]), "presion_hpa": _num(parts[4]), "viento_dir": _num(parts[5]),
                    "viento_kmh": _num(parts[6]), "estacion": ln[col:].strip()})
    return out


def pba_station_names(client) -> set[str]:
    from app.providers.extras import _zip_text, parse_stations

    st = parse_stations(_zip_text(client, "estaciones"))
    return {v["name"] for v in st.values() if v["provincia"] in ("BUENOS AIRES", "CAPITAL FEDERAL")}


def update_smn_hourly(client, folder: Path, station_names: set[str]) -> dict:
    r = _get(client, SMN_ZIP, {"dato": "datohorario"}, timeout=90)
    r.raise_for_status()
    z = zipfile.ZipFile(io.BytesIO(r.content))
    rows = []
    for name in z.namelist():
        raw = z.read(name)
        try:
            txt = raw.decode("utf-8")
        except UnicodeDecodeError:
            txt = raw.decode("latin-1")
        rows += [x for x in parse_hourly(txt) if not station_names or x["estacion"] in station_names]
    if not rows:
        raise RuntimeError("Archivo horario del SMN vacío o con otro formato")
    month = rows[0]["fecha"][:7]
    path = folder / f"smn_horarios_{month}.csv"
    prev = read_csv(path)
    have = {(x["fecha"], x["hora"], x["estacion"]) for x in prev}
    new = [x for x in rows if (x["fecha"], str(x["hora"]), x["estacion"]) not in have]
    write_csv(path, ["fecha", "hora", "estacion", "temp_c", "humedad", "presion_hpa", "viento_dir", "viento_kmh"],
              prev + new)
    return {"archivo": path.name, "nuevas": len(new), "estaciones": len({x["estacion"] for x in rows})}


# ------------------------------------------------------------------ 4. lo que pronosticó ConDi (para verificar después)
def append_forecasts(folder: Path, alertas: dict | None) -> dict:
    if not alertas or alertas.get("data_mode") != "live":
        raise RuntimeError("Sin alertas en vivo para registrar")
    day = alertas["generated_at"][:10]
    path = folder / f"pronosticos_condi_{day[:7]}.csv"
    rows = read_csv(path)
    if any(r["emitido"] == day for r in rows):
        return {"archivo": path.name, "nuevas": 0}
    new = []
    for w, win in alertas["windows"].items():
        for m in win["municipios"]:
            pr = m.get("prob_lluvia") or {}
            new.append({"emitido": day, "ventana_h": w, "desde": win.get("valid_from"), "partido": m["id"],
                        "nivel": m["alert_level"], "fenomeno": m.get("hazard") or "", "consenso": m.get("consensus"),
                        "lluvia_mediana_mm": m.get("lluvia_mm"),
                        **{f"modelos_{t}mm": (pr.get(t) or {}).get("k") for t in ("10", "30", "60")},
                        "modelos": (pr.get("10") or {}).get("n"),
                        "lluvia_ponderada_mm": (m.get("ponderado") or {}).get("lluvia_mm"),
                        "nivel_ponderado": (m.get("ponderado") or {}).get("nivel")})
    fields = ["emitido", "ventana_h", "desde", "partido", "nivel", "fenomeno", "consenso", "lluvia_mediana_mm",
              "modelos", "modelos_10mm", "modelos_30mm", "modelos_60mm", "lluvia_ponderada_mm", "nivel_ponderado"]
    write_csv(path, fields, rows + new)
    return {"archivo": path.name, "nuevas": len(new)}


# ------------------------------------------------------------------ 5. alturas de ríos observadas (INA / Prefectura)
def append_river_obs(folder: Path, observed: dict | None) -> dict:
    if not observed or not observed.get("estaciones"):
        raise RuntimeError("Sin alturas observadas")
    rows_new = []
    for st in observed["estaciones"]:
        for t, v in st.get("serie_30d") or []:
            rows_new.append({"fecha": t, "estacion": st["estacion"], "rio": st.get("rio") or "", "altura_m": v,
                             "alerta_m": st.get("alerta"), "evacuacion_m": st.get("evacuacion"),
                             "red": st.get("red") or ""})
    out = {}
    for row in rows_new:
        path = folder / f"rios_observados_{row['fecha'][:7]}.csv"
        out.setdefault(path, []).append(row)
    added = 0
    fields = ["fecha", "estacion", "rio", "altura_m", "alerta_m", "evacuacion_m", "red"]
    for path, rows in out.items():
        prev = read_csv(path)
        have = {(r["fecha"], r["estacion"]) for r in prev}
        new = [r for r in rows if (r["fecha"], r["estacion"]) not in have]
        added += len(new)
        write_csv(path, fields, sorted(prev + new, key=lambda r: (r["fecha"], r["estacion"])))
    return {"nuevas": added, "estaciones": len(observed["estaciones"])}


# ------------------------------------------------------------------ catálogo
TABLES = [
    (ERA5_FILE, "Lluvia diaria observada por el reanálisis ERA5 en un punto por sección electoral, desde 1981.",
     "ERA5 · Copernicus Climate Change Service / ECMWF, vía Open-Meteo (CC BY 4.0)"),
    (VERIF_FILE, "Lluvia diaria pronosticada por cada modelo con 1, 2 y 3 días de anticipación, y la observada (ERA5).",
     "Corridas anteriores de los modelos vía Open-Meteo (CC BY 4.0); observación ERA5"),
    (ALERTS_FILE, "Alertas oficiales del SMN leídas en cada actualización (fenómeno, nivel, vigencia, zonas).",
     "Servicio Meteorológico Nacional, API CAP oficial"),
    ("smn_horarios_*.csv", "Datos horarios de las estaciones del SMN en la provincia y CABA: temperatura, humedad, "
     "presión y viento (el SMN no publica la lluvia en este archivo).", "Servicio Meteorológico Nacional, datos abiertos"),
    ("pronosticos_condi_*.csv", "Lo que pronosticó ConDi para cada partido, una vez por día, para verificarlo después.",
     "ConDi · ARGWX (consenso de 9 modelos)"),
    ("rios_observados_*.csv", "Alturas de los ríos observadas en escalas de la provincia, con los niveles oficiales de "
     "alerta y evacuación.", "Prefectura Naval Argentina y Red Hidrológica Nacional, vía API pública del INA"),
    (CLIMA_FILE, "Frecuencia histórica de lluvias de 10 a 110 mm por mes y percentiles (sale de la tabla ERA5).",
     "Cálculo propio sobre ERA5"),
    (CALIB_FILE, "Aciertos y falsas alarmas de cada modelo y probabilidad calibrada según cuántos modelos coinciden.",
     "Cálculo propio sobre la tabla de verificación"),
]


def write_catalog(folder: Path) -> dict:
    items = []
    for pattern, desc, source in TABLES:
        files = sorted(folder.glob(pattern))
        n, first, last = 0, None, None
        for f in files:
            if f.suffix == ".csv":
                rows = read_csv(f)
                n += len(rows)
                keys = [r.get("fecha") or r.get("emitido") or r.get("desde") or r.get("visto") or "" for r in rows]
                keys = [k[:10] for k in keys if k]
                if keys:
                    first = min([first, min(keys)] if first else [min(keys)])
                    last = max([last, max(keys)] if last else [max(keys)])
        items.append({"tabla": pattern, "archivos": [f.name for f in files], "descripcion": desc, "fuente": source,
                      "registros": n if any(f.suffix == ".csv" for f in files) else None, "desde": first, "hasta": last,
                      "bytes": sum(f.stat().st_size for f in files)})
    res = {"generated_at": iso(utcnow()), "tablas": items,
           "nota": "Datos de uso público. ERA5 es un reanálisis (no un pluviómetro): sirve de referencia común para "
                   "comparar modelos. Las tablas que se acumulan (alertas, horarios, pronósticos) crecen con cada "
                   "actualización desde el 4/11/2026."}
    (folder / CATALOG_FILE).write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    return {"tablas": len(items), "archivos": sum(len(i["archivos"]) for i in items)}
