"""Genera el dashboard estático (GitHub Pages) con datos reales.

Vistas:
  1. Tormentas sobre la Argentina: alertas oficiales del SMN + consenso de modelos (tormentas previstas).
  2. El Niño en la Provincia de Buenos Aires: estado ENSO, historia del ONI y cómo cambió la lluvia
     bonaerense en cada fase (ERA5 1981-hoy vía Open-Meteo).
  3. Alertas ARGWX en los 135 partidos.

Uso: python -m app.cli export-site CARPETA_SALIDA [CARPETA_CACHE]
Cada parte se genera por separado: si una fuente falla, el resto se publica igual y meta.json lo informa.
"""
import json
import logging
import os
import shutil
import time
from calendar import monthrange
from datetime import date, timedelta
from pathlib import Path
from statistics import mean, median

from app.config import get_settings
from app.engine.geo import point_in_polygon
from app.engine.levels import COLOR, LABEL
from app.providers import enso, openmeteo, smn
from app.services.municipalities import SECCION_NOMBRE, by_id, load_municipalities
from app.services.sync import http_client
from app.util import iso, utcnow

log = logging.getLogger("argwx.export")
APP = Path(__file__).parent
SEASONS_ES = {"DJF": "DEF", "JFM": "EFM", "FMA": "FMA", "MAM": "MAM", "AMJ": "AMJ", "MJJ": "MJJ", "JJA": "JJA",
              "JAS": "JAS", "ASO": "ASO", "SON": "SON", "OND": "OND", "NDJ": "NDE"}
# Un punto por sección electoral para medir el efecto de El Niño en la lluvia.
ENSO_POINTS = ["lujan", "pergamino", "canuelas", "9-de-julio", "general-pueyrredon", "bahia-blanca", "olavarria",
               "la-plata"]
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
ARCHIVE_CUSTOMER_URL = "https://customer-archive-api.open-meteo.com/v1/archive"
START_YEAR = 1981


def _fresh(cache: Path | None, name: str, max_hours: float) -> bool:
    """True si la copia publicada anteriormente tiene menos de max_hours (evita consultas innecesarias)."""
    if not cache or os.environ.get("ARGWX_FORCE", "").lower() == "true" or not (cache / name).exists():
        return False
    try:
        prev = json.loads((cache / name).read_text(encoding="utf-8"))
        from datetime import datetime

        age = utcnow() - datetime.fromisoformat(prev["generated_at"].replace("Z", ""))
        return age.total_seconds() < max_hours * 3600
    except Exception:
        return False


def _write(out: Path, name: str, data) -> None:
    (out / name).write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":"), default=str),
                            encoding="utf-8")


def _provinces() -> list[dict]:
    feats = json.loads((APP / "data" / "provincias_ar.geojson").read_text(encoding="utf-8"))["features"]
    out = []
    for f in feats:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        out.append({"name": f["properties"]["name"], "rings": [[(c[1], c[0]) for c in p[0]] for p in polys]})
    return out


def _province_of(lat: float, lon: float, provinces: list[dict]) -> str | None:
    return next((p["name"] for p in provinces if any(point_in_polygon(lat, lon, r) for r in p["rings"])), None)


# ------------------------------------------------------------------ 1. tormentas en la Argentina
def export_smn(out: Path, client, settings) -> dict:
    provinces, munis = _provinces(), load_municipalities()

    def get(url):
        resp = client.get(url)
        resp.raise_for_status()
        return resp.text

    url = settings.list_of("smn_cap_urls")[0]
    alerts, seen, rows = smn.parse_feed(get(url), fetch=get), set(), []
    for a in alerts:
        polys = [p for ar in a["areas"] for p in ar["polygons"]]
        key = (a["title"], a["level"], str(a["valid_from"]), polys[0][0] if polys else None)
        if key in seen:
            continue
        seen.add(key)
        simple = []
        for p in polys:
            step = max(1, len(p) // 200)
            pts = [(round(lat, 2), round(lon, 2)) for lat, lon in p[::step]]
            simple.append(pts)
        provs = sorted({pv for p in polys for lat, lon in p[::max(1, len(p) // 12)]
                        if (pv := _province_of(lat, lon, provinces))})
        pba = [by_id()[i]["name"] for i in smn.affected(a, munis)]
        rows.append({"title": a["title"], "level": a["level"], "label": LABEL[a["level"]], "color": COLOR[a["level"]],
                     "hazard": a["hazard"], "storm": a["hazard"] in ("tormenta", "granizo"),
                     "valid_from": iso(a["valid_from"]), "valid_to": iso(a["valid_to"]),
                     "description": (a["description"] or "")[:500], "provincias": provs, "partidos_pba": pba,
                     "polygons": simple})
    rows.sort(key=lambda r: (-["GREEN", "YELLOW", "ORANGE", "RED", "PURPLE"].index(r["level"]), r["title"]))
    _write(out, "smn_argentina.json", {"generated_at": iso(utcnow()), "source": url, "alerts": rows})
    return {"alertas": len(rows), "tormentas": sum(r["storm"] for r in rows)}


def storm_grid(step: float = 1.5) -> list[dict]:
    provinces, pts = _provinces(), []
    lat = -22.5
    while lat >= -55:
        lon = -73.5
        while lon <= -53.5:
            if _province_of(lat, lon, provinces):
                pts.append({"id": f"{lat:.1f}_{lon:.1f}", "lat": round(lat, 2), "lon": round(lon, 2)})
            lon += step
        lat -= step
    return pts


def export_storm_outlook(out: Path, client, settings, now) -> dict:
    grid = storm_grid()
    rows = openmeteo.fetch(grid, settings, client, now)
    by_point: dict = {}
    for r in rows:
        by_point.setdefault((r["municipality_id"], r["window_h"]), []).append(r)
    windows = {}
    for w in (24, 48, 72):
        items = []
        for p in grid:
            rs = by_point.get((p["id"], w), [])
            if not rs:
                continue
            storm = [r["model"] for r in rs if (r["weather_code"] or 0) >= 95]
            rain = [r["rain_mm"] for r in rs if r["rain_mm"] is not None]
            items.append({"lat": p["lat"], "lon": p["lon"], "modelos": len(rs), "modelos_tormenta": len(storm),
                          "con_tormenta": storm, "lluvia_mediana": round(median(rain), 1) if rain else None})
        windows[str(w)] = items
    _write(out, "tormentas_modelos.json", {
        "generated_at": iso(utcnow()), "grilla_grados": 1.5,
        "modelos": settings.list_of("open_meteo_models"),
        "nota": "Cantidad de modelos que prevén tormenta (código WMO 95 o mayor) en cada punto de la grilla.",
        "windows": windows})
    return {"puntos": len(grid)}


# ------------------------------------------------------------------ 2. El Niño en Buenos Aires
def export_enso(out: Path, client, settings) -> tuple[dict, list[dict]]:
    oni = enso.parse_oni(enso._get(client, settings.oni_url))
    if not oni:
        raise ValueError("ONI vacío")
    rows = list(oni)
    weekly, soi = [], []
    try:
        weekly = enso.parse_weekly(enso._get(client, settings.nino_weekly_url))
    except Exception as exc:
        log.warning("Niño semanal: %s", exc)
    try:
        soi = enso.parse_soi(enso._get(client, settings.soi_url))
    except Exception as exc:
        log.warning("SOI: %s", exc)
    status = enso.status(rows + weekly[-4:] + soi[-1:])
    status.pop("weekly_phase_nino34", None)
    _write(out, "enso.json", {
        "generated_at": iso(utcnow()), "source": "NOAA CPC", "status": status,
        "oni": [{"period": r["period"], "value": r["value"], "phase": enso.phase(r["value"])} for r in oni],
        "nino34_semanal": [{"week": r["period"], "anomaly": r["value"]} for r in weekly
                           if r["index_name"] == "NINO34"][-52:],
        "soi": [{"month": r["period"], "value": r["value"]} for r in soi][-36:]})
    return {"oni_ultimo": oni[-1]["period"], "fase": status["phase"]}, oni


def _season_months(k: int, year: int) -> list[tuple[int, int]]:
    """Meses de la estación k (0 = DEF) del año ONI `year` (mes central = k + 1)."""
    out = []
    for m in (k, k + 1, k + 2):
        if m == 0:
            out.append((year - 1, 12))
        elif m == 13:
            out.append((year + 1, 1))
        else:
            out.append((year, m))
    return out


def _fetch_archive(client, settings, pts: list[dict], end: date) -> list[dict]:
    url = ARCHIVE_CUSTOMER_URL if settings.open_meteo_api_key else ARCHIVE_URL
    params = {"latitude": ",".join(str(p["lat"]) for p in pts), "longitude": ",".join(str(p["lon"]) for p in pts),
              "start_date": f"{START_YEAR - 1}-12-01", "end_date": end.isoformat(), "daily": "precipitation_sum",
              "timezone": "America/Argentina/Buenos_Aires", "models": "era5"}
    if settings.open_meteo_api_key:
        params["apikey"] = settings.open_meteo_api_key
    resp = client.get(url, params=params, timeout=180)
    if resp.status_code == 400:  # por si el modelo no se acepta: usar la mejor combinación disponible
        params.pop("models")
        resp = client.get(url, params=params, timeout=180)
    resp.raise_for_status()
    data = resp.json()
    return [data] if isinstance(data, dict) else data


def enso_rain_composites(daily_by_point: dict[str, dict], oni: list[dict]) -> dict:
    """daily_by_point: id -> {"time": [...], "precipitation_sum": [...]}. Devuelve anomalías % por fase."""
    oni_value = {(r["period"].split()[0], int(r["period"].split()[1])): r["value"] for r in oni}
    seasonal: dict[str, dict] = {}
    for pid, daily in daily_by_point.items():
        monthly, counts = {}, {}
        for t, v in zip(daily["time"], daily["precipitation_sum"]):
            if v is None:
                continue
            ym = (int(t[:4]), int(t[5:7]))
            monthly[ym] = monthly.get(ym, 0.0) + v
            counts[ym] = counts.get(ym, 0) + 1
        complete = {ym for ym, n in counts.items() if n >= monthrange(*ym)[1] - 1}
        tot = {}
        for (season, year) in oni_value:
            k = enso.SEASONS.index(season)
            months = _season_months(k, year)
            if year >= START_YEAR and all(m in complete for m in months):
                tot[(k, year)] = sum(monthly[m] for m in months)
        seasonal[pid] = tot

    anomalies: dict[str, dict] = {}
    for pid, tot in seasonal.items():
        clim = {}
        for k in range(12):
            ref = [v for (kk, y), v in tot.items() if kk == k and 1991 <= y <= 2020]
            if len(ref) >= 20 and mean(ref) > 0:
                clim[k] = mean(ref)
        anomalies[pid] = {key: (v / clim[key[0]] - 1) * 100 for key, v in tot.items() if key[0] in clim}

    def composite(series: dict) -> dict:
        out = {ph: {"media": [None] * 12, "n": [0] * 12} for ph in ("EL_NINO", "NEUTRAL", "LA_NINA")}
        for ph in out:
            for k in range(12):
                xs = [a for (kk, y), a in series.items() if kk == k
                      and enso.phase(oni_value[(enso.SEASONS[k], y)]) == ph]
                out[ph]["n"][k] = len(xs)
                out[ph]["media"][k] = round(mean(xs), 1) if xs else None
        return out

    keys = set.intersection(*(set(a) for a in anomalies.values())) if anomalies else set()
    province = {key: mean(anomalies[p][key] for p in anomalies) for key in keys}
    comp = composite(province)
    nino = [(v, k) for k, v in enumerate(comp["EL_NINO"]["media"]) if v is not None]
    nina = [(v, k) for k, v in enumerate(comp["LA_NINA"]["media"]) if v is not None]
    years = sorted({y for (_, y) in keys})
    return {
        "periodo": f"{years[0]}-{years[-1]}" if years else None, "climatologia": "1991-2020",
        "estaciones": [{"code": s, "es": SEASONS_ES[s]} for s in enso.SEASONS],
        "provincia": comp,
        "por_punto": {p: {ph: v["media"] for ph, v in composite(a).items()} for p, a in anomalies.items()},
        "resumen": {
            "nino_max": {"estacion": SEASONS_ES[enso.SEASONS[max(nino)[1]]], "valor": max(nino)[0]} if nino else None,
            "nina_min": {"estacion": SEASONS_ES[enso.SEASONS[min(nina)[1]]], "valor": min(nina)[0]} if nina else None},
    }


def export_enso_pba(out: Path, client, settings, oni: list[dict], cache: Path | None) -> dict:
    cached = cache / "enso_pba.json" if cache else None
    if cached and cached.exists():
        try:
            prev = json.loads(cached.read_text(encoding="utf-8"))
            age = (utcnow().date() - date.fromisoformat(prev["generated_at"][:10])).days
            if age <= 30 and [p["id"] for p in prev.get("puntos", [])] == ENSO_POINTS:
                shutil.copy(cached, out / "enso_pba.json")
                return {"cache": True, "dias": age}
        except Exception as exc:
            log.warning("Cache ENSO-PBA inválida: %s", exc)
    pts = [by_id()[i] for i in ENSO_POINTS]
    end = utcnow().date() - timedelta(days=10)
    data = _fetch_archive(client, settings, pts, end)
    daily = {p["id"]: loc.get("daily") or {} for p, loc in zip(pts, data)}
    result = enso_rain_composites(daily, oni)
    result.update({
        "generated_at": iso(utcnow()),
        "fuente": "Lluvia: reanálisis ERA5 (Copernicus/ECMWF) vía Open-Meteo. Fases: ONI de NOAA CPC.",
        "metodo": "Lluvia acumulada en cada trimestre, comparada con su promedio 1991-2020; promedio de las "
                  "anomalías según la fase ENSO de ese trimestre (ONI >= +0,5 El Niño, <= -0,5 La Niña).",
        "puntos": [{"id": p["id"], "name": p["name"], "seccion": p["seccion"],
                    "seccion_nombre": SECCION_NOMBRE[p["seccion"]]} for p in pts]})
    _write(out, "enso_pba.json", result)
    return {"cache": False, "periodo": result["periodo"]}


# ------------------------------------------------------------------ 3. alertas en los 135 partidos
def export_pba_alerts(out: Path) -> dict:
    from app.db import init_db, new_session
    from app.services.municipalities import seed
    from app.services.state import compute_state, summary
    from app.services.sync import sync

    init_db()
    with new_session() as s:
        seed(s)
    sync()
    with new_session() as s:
        st = compute_state(s)
    if st["data_mode"] == "sin_datos":
        raise RuntimeError("Sin datos de modelos (posible límite de consultas de Open-Meteo)")
    keep = ("id", "name", "seccion", "alert_level", "alert_label", "color", "hazard", "confidence_label",
            "consensus", "drivers")
    windows = {str(w): {"label": v["label"], "valid_from": v["valid_from"], "valid_to": v["valid_to"],
                        "summary": summary(v["municipalities"].values()),
                        "municipios": [{**{k: e[k] for k in keep if k != "drivers"},
                                        "drivers": e["drivers"][:1] if e["alert_level"] != "GREEN" else []}
                                       for e in v["municipalities"].values()]}
               for w, v in st["windows"].items()}
    _write(out, "alertas_pba.json", {"generated_at": st["generated_at"], "data_mode": st["data_mode"],
                                     "models": st["models"], "windows": windows})
    return {"modo": st["data_mode"], "en_alerta_24h": 135 - windows["24"]["summary"]["GREEN"]}


# ------------------------------------------------------------------ copia de respaldo de los datos en vivo
LIVE_MODELS = ["gfs_seamless", "icon_seamless", "ecmwf_ifs025", "gem_seamless", "ukmo_seamless"]


def region_grid(spec: dict) -> list[tuple[float, float]]:
    """Misma grilla que tracking.js (filas de norte a sur, columnas de oeste a este)."""
    lats, lons, la, lo = [], [], spec["latN"], spec["lonW"]
    while la >= spec["latS"] - 1e-9:
        lats.append(round(la, 4))
        la -= spec["step"]
    while lo <= spec["lonE"] + 1e-9:
        lons.append(round(lo, 4))
        lo += spec["step"]
    return [(a, b) for a in lats for b in lons]


def export_live_snapshots(out: Path, client) -> dict:
    """Guarda las mismas consultas que hace el navegador, para usarlas si Open-Meteo no responde."""
    regions = json.loads((APP / "site" / "regions.json").read_text(encoding="utf-8"))
    info = {}
    for key, spec in regions.items():
        pts = region_grid(spec)
        base = {"latitude": ",".join(f"{a:.2f}" for a, _ in pts), "longitude": ",".join(f"{b:.2f}" for _, b in pts),
                "forecast_hours": 12, "timezone": "UTC", "timeformat": "unixtime", "wind_speed_unit": "kmh"}
        settings = get_settings()
        if settings.open_meteo_api_key:
            base["apikey"] = settings.open_meteo_api_key
        best = _get_retry(client, {**base, "hourly": "temperature_2m,precipitation,weather_code,"
                                   "wind_speed_10m,wind_direction_10m,wind_gusts_10m"})
        models = _get_retry(client, {**base, "hourly": "precipitation,weather_code", "models": ",".join(LIVE_MODELS)})
        _write(out, f"live_{key}.json", {"generated_at": iso(utcnow()), "region": key, "best": best.json(),
                                          "models": models.json()})
        info[key] = len(pts)
    return info


def _get_retry(client, params: dict):
    """Open-Meteo limita las consultas por minuto: ante un 429 espera y reintenta una vez."""
    for attempt in range(2):
        resp = client.get(openmeteo_url(), params=params)
        if resp.status_code != 429 or attempt:
            resp.raise_for_status()
            return resp
        time.sleep(65)
    return resp


def openmeteo_url() -> str:
    s = get_settings()
    return openmeteo.CUSTOMER_URL if s.open_meteo_api_key and "api.open-meteo.com" in s.open_meteo_url else s.open_meteo_url


# ------------------------------------------------------------------ armado
def build(out_dir: str, cache_dir: str | None = None) -> dict:
    settings = get_settings()
    out = Path(out_dir)
    shutil.copytree(APP / "site", out, dirs_exist_ok=True)
    (out / "data").mkdir(parents=True, exist_ok=True)
    (out / "geo").mkdir(exist_ok=True)
    for name in ("provincias_ar.geojson", "municipios_pba.geojson", "municipios_pba.json"):
        shutil.copy(APP / "data" / name, out / "geo" / name)
    data, cache = out / "data", Path(cache_dir) if cache_dir else None
    parts, oni = {}, []

    def run(name, fn, file=None, max_hours=0):
        if file and _fresh(cache, file, max_hours):
            shutil.copy(cache / file, data / file)
            parts[name] = {"ok": True, "reutilizado": True}
            return
        try:
            parts[name] = {"ok": True, **(fn() or {})}
        except Exception as exc:
            log.exception("Falló %s", name)
            parts[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]}
            if file and cache and (cache / file).exists():  # mejor una copia anterior que nada
                shutil.copy(cache / file, data / file)
                parts[name]["usando_copia_anterior"] = True

    with http_client(settings) as client:
        def enso_part():
            info, rows = export_enso(data, client, settings)
            oni.extend(rows)
            return info

        run("enso", enso_part)
        if not oni and cache and (cache / "enso.json").exists():
            oni.extend({"period": r["period"], "value": r["value"]}
                       for r in json.loads((cache / "enso.json").read_text(encoding="utf-8"))["oni"])
        run("smn", lambda: export_smn(data, client, settings))
        for key in ("pba", "ar"):
            if _fresh(cache, f"live_{key}.json", 3):
                shutil.copy(cache / f"live_{key}.json", data / f"live_{key}.json")
        if not all((data / f"live_{k}.json").exists() for k in ("pba", "ar")):
            run("en_vivo_respaldo", lambda: export_live_snapshots(data, client))
        if oni:
            run("enso_pba", lambda: export_enso_pba(data, client, settings, oni, cache))
        else:
            parts["enso_pba"] = {"ok": False, "error": "Sin ONI"}
            if cache and (cache / "enso_pba.json").exists():
                shutil.copy(cache / "enso_pba.json", data / "enso_pba.json")
    run("alertas_pba", lambda: export_pba_alerts(data), "alertas_pba.json", 3)
    meta = {"generated_at": iso(utcnow()), "parts": parts,
            "repo": "https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio"}
    _write(data, "meta.json", meta)
    return meta
