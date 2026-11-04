"""Escenario SIMULADO para demostrar el motor sin conexión. NADA de esto es un dato real.

Un sistema de tormentas avanza de sudoeste a noreste por la provincia. Cada "modelo" lo ve con
otra intensidad y otra ubicación, para que se vea cómo trabaja el consenso.
"""
import math
import random
import zlib
from datetime import date, timedelta

from app.engine.geo import haversine_km

TAG = "[SIMULADO]"
# escala de lluvia, corrimiento lat, corrimiento lon, escala de viento
MODELS = {"GFS": (1.15, 0.10, 0.15, 1.10), "ICON": (1.00, -0.05, 0.35, 1.00), "ECMWF": (1.05, 0.0, 0.0, 1.0),
          "GEM": (0.75, -0.20, -0.20, 0.90), "UKMO": (0.90, 0.15, -0.30, 0.95)}
TRACK = {24: (-37.4, -61.0), 48: (-35.5, -59.3), 72: (-33.9, -57.9)}
FADE = {24: 1.0, 48: 0.85, 72: 0.7}  # la intensidad simulada baja con el plazo


def _rng(*parts) -> random.Random:
    return random.Random(zlib.crc32("|".join(map(str, parts)).encode()))


def _coast(m) -> bool:
    return m["lon"] > -57.8 and m["lat"] < -36.3


def forecasts(munis: list[dict], now) -> list[dict]:
    start, day = now.replace(minute=0, second=0, microsecond=0), now.date().isoformat()
    rows = []
    for m in munis:
        for model, (scale, dlat, dlon, gscale) in MODELS.items():
            for w, (clat, clon) in TRACK.items():
                rng = _rng(day, m["id"], model, w)
                d = haversine_km(m["lat"], m["lon"], clat + dlat, clon + dlon)
                rain = 118 * scale * FADE[w] * math.exp(-(d / 150) ** 2) + rng.uniform(0, 4)
                gust = 30 + 80 * gscale * math.exp(-(d / 180) ** 2) + rng.uniform(0, 8) + (12 if _coast(m) else 0)
                ahead = haversine_km(m["lat"], m["lon"], clat + 2.0, clon + 2.0)
                tmax = 27 + 9 * math.exp(-(ahead / 260) ** 2) - 0.4 * (-m["lat"] - 34) + rng.uniform(-1, 1)
                code = 95 if rain >= 25 else 63 if rain >= 10 else 61 if rain >= 2 else 3
                rows.append({"municipality_id": m["id"], "model": model, "window_h": w,
                             "valid_from": start + timedelta(hours=w - 24), "valid_to": start + timedelta(hours=w),
                             "rain_mm": round(rain, 1), "gust_kmh": round(gust, 1), "tmax_c": round(tmax, 1),
                             "tmin_c": round(tmax - 11, 1), "weather_code": code})
    return rows


def enso(now) -> list[dict]:
    rows, today = [], now.date()
    seasons = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
    for k in range(24, 0, -1):
        y, mth = divmod(today.year * 12 + today.month - 1 - k, 12)
        v = round(0.3 + 0.6 * math.sin((24 - k) / 6.0 - 2.3), 1)
        rows.append({"index_name": "ONI", "period": f"{seasons[mth]} {y}", "period_date": date(y, mth + 1, 1),
                     "sst": round(26.5 + v, 2), "value": v})
    for k in range(4):
        d = today - timedelta(days=7 * (3 - k))
        for name, base in (("NINO12", 0.9), ("NINO3", 0.8), ("NINO34", 0.7), ("NINO4", 0.5)):
            rows.append({"index_name": name, "period": d.isoformat(), "period_date": d,
                         "sst": round(26 + base, 1), "value": round(base + 0.05 * k, 2)})
    rows.append({"index_name": "SOI", "period": today.strftime("%Y-%m"), "period_date": today.replace(day=1),
                 "sst": None, "value": -0.8})
    return rows


def smn_alerts(munis: list[dict], now) -> list[dict]:
    start = now.replace(minute=0, second=0, microsecond=0)
    clat, clon = TRACK[24]
    storm = [m for m in munis if haversine_km(m["lat"], m["lon"], clat, clon) <= 150]
    rows = []
    for group, title, hazard in ((storm, f"{TAG} Alerta amarilla por tormentas", "tormenta"),
                                 ([m for m in munis if _coast(m)], f"{TAG} Alerta amarilla por viento", "viento")):
        for m in group:
            rows.append({"municipality_id": m["id"], "external_id": f"demo-{hazard}-{start:%Y%m%d}",
                         "title": title, "description": "Alerta simulada para la demostración. No es oficial.",
                         "level": "YELLOW", "hazard": hazard, "valid_from": start,
                         "valid_to": start + timedelta(hours=24), "issued_at": start,
                         "details": {"areas": ["simulado"]}})
    return rows


def observations(munis: list[dict], now) -> list[dict]:
    ids = {m["id"] for m in munis}
    if "tandil" not in ids:
        return []
    return [{"municipality_id": "tandil", "source": f"{TAG} estación demo", "observed_at": now - timedelta(hours=1),
             "rain_mm_24h": 72.0, "gust_kmh": 55.0, "temp_c": 18.5,
             "notes": "Observación simulada para mostrar la regla: la observación prevalece sobre el modelo."}]
