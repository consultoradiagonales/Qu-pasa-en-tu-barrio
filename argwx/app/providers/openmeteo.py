"""Modelos numéricos vía Open-Meteo: GFS (NOAA), ICON (DWD), ECMWF IFS, GEM (Canadá) y UKMO (Reino Unido).

Se piden datos horarios para los 135 puntos (en lotes) y se agregan en ventanas de 24 h:
lluvia acumulada, ráfaga máxima, temperatura máxima/mínima y código de tiempo WMO máximo.
"""
import time
from datetime import datetime, timedelta

MODEL_LABELS = {
    "gfs_seamless": "GFS", "gfs_global": "GFS", "icon_seamless": "ICON", "icon_global": "ICON",
    "ecmwf_ifs025": "ECMWF", "ecmwf_ifs": "ECMWF", "gem_seamless": "GEM", "gem_global": "GEM",
    "ukmo_seamless": "UKMO", "ukmo_global_deterministic_10km": "UKMO",
}
HOURLY = ("precipitation", "wind_gusts_10m", "temperature_2m", "weather_code")
WINDOWS = (24, 48, 72)
BATCH = 50
CUSTOMER_URL = "https://customer-api.open-meteo.com/v1/forecast"


def label(code: str) -> str:
    return MODEL_LABELS.get(code, code.upper())


def aggregate(times: list[datetime], series: dict, now: datetime) -> list[dict]:
    first = now.replace(minute=0, second=0, microsecond=0)
    start = next((i for i, t in enumerate(times) if t >= first), None)
    if start is None:
        return []
    out = []
    for w in WINDOWS:
        a, b = start + w - 24, start + w
        if b > len(times):
            break

        def vals(var):
            return [x for x in series[var][a:b] if x is not None]

        rain, gust, temp, code = (vals(v) for v in HOURLY)
        if not rain and not temp:
            continue
        out.append({
            "window_h": w, "valid_from": times[a], "valid_to": times[b - 1] + timedelta(hours=1),
            "rain_mm": round(sum(rain), 1) if rain else None,
            "gust_kmh": round(max(gust), 1) if gust else None,
            "tmax_c": round(max(temp), 1) if temp else None,
            "tmin_c": round(min(temp), 1) if temp else None,
            "weather_code": int(max(code)) if code else None,
        })
    return out


def parse_location(loc: dict, models: list[str], now: datetime) -> dict[str, list[dict]]:
    hourly = loc.get("hourly") or {}
    times = [datetime.fromisoformat(t) for t in hourly.get("time") or []]
    result = {}
    for m in models:
        series = {}
        for var in HOURLY:
            keys = [f"{var}_{m}"] + ([var] if len(models) == 1 else [])
            data = next((hourly[k] for k in keys if k in hourly), None)
            series[var] = data if data is not None else [None] * len(times)
        windows = aggregate(times, series, now)
        if windows:
            result[label(m)] = windows
    return result


def fetch(munis: list[dict], settings, client, now: datetime) -> list[dict]:
    models = settings.list_of("open_meteo_models")
    url = settings.open_meteo_url
    if settings.open_meteo_api_key and "api.open-meteo.com" in url:
        url = CUSTOMER_URL
    rows = []
    for i in range(0, len(munis), BATCH):
        batch = munis[i:i + BATCH]
        params = {
            "latitude": ",".join(f"{m['lat']:.4f}" for m in batch),
            "longitude": ",".join(f"{m['lon']:.4f}" for m in batch),
            "hourly": ",".join(HOURLY), "models": ",".join(models), "forecast_days": 4,
            "timezone": "UTC", "wind_speed_unit": "kmh", "precipitation_unit": "mm",
        }
        if settings.open_meteo_api_key:
            params["apikey"] = settings.open_meteo_api_key
        resp = client.get(url, params=params)
        if resp.status_code == 429:  # límite de consultas por minuto: esperar y reintentar una vez
            time.sleep(65)
            resp = client.get(url, params=params)
        resp.raise_for_status()
        data = resp.json()
        data = [data] if isinstance(data, dict) else data
        if len(data) != len(batch):
            raise ValueError(f"Open-Meteo devolvió {len(data)} ubicaciones para un lote de {len(batch)}")
        for m, loc in zip(batch, data):
            for model, windows in parse_location(loc, models, now).items():
                rows += [{"municipality_id": m["id"], "model": model, **w} for w in windows]
    return rows
