"""Proveedores opcionales: se activan solo si hay API key en las variables de entorno.

BETA: implementados según la documentación pública de cada servicio; no se pudieron probar
contra las APIs reales desde el entorno de desarrollo (sin salida a esos dominios).
"""
import time
from datetime import datetime, timedelta, timezone

from app.engine.geo import haversine_km
from app.util import to_utc_naive


def _windows(points: list[tuple], now: datetime) -> list[dict]:
    """points: (hora UTC, lluvia mm, ráfaga km/h, temperatura °C, tormenta bool)."""
    start = now.replace(minute=0, second=0, microsecond=0)
    out = []
    for w in (24, 48, 72):
        a, b = start + timedelta(hours=w - 24), start + timedelta(hours=w)
        seg = [p for p in points if a <= p[0] < b]
        if not seg:
            continue
        rain = [p[1] for p in seg if p[1] is not None]
        gust = [p[2] for p in seg if p[2] is not None]
        temp = [p[3] for p in seg if p[3] is not None]
        out.append({"window_h": w, "valid_from": a, "valid_to": b,
                    "rain_mm": round(sum(rain), 1) if rain else None,
                    "gust_kmh": round(max(gust), 1) if gust else None,
                    "tmax_c": round(max(temp), 1) if temp else None,
                    "tmin_c": round(min(temp), 1) if temp else None,
                    "weather_code": 95 if any(p[4] for p in seg) else None})
    return out


def fetch_openweather(munis, settings, client, now) -> list[dict]:
    """OpenWeather 5 días / 3 horas (plan gratuito: 60 llamadas por minuto)."""
    rows = []
    for m in munis:
        resp = client.get("https://api.openweathermap.org/data/2.5/forecast",
                          params={"lat": m["lat"], "lon": m["lon"], "appid": settings.openweather_api_key,
                                  "units": "metric"})
        resp.raise_for_status()
        pts = []
        for it in resp.json().get("list", []):
            t = datetime.fromtimestamp(it["dt"], tz=timezone.utc).replace(tzinfo=None)
            wind, main = it.get("wind") or {}, it.get("main") or {}
            gust = wind.get("gust", wind.get("speed"))
            pts.append((t, (it.get("rain") or {}).get("3h", 0.0), gust * 3.6 if gust is not None else None,
                        main.get("temp_max", main.get("temp")),
                        any(200 <= w.get("id", 0) < 300 for w in it.get("weather", []))))
        rows += [{"municipality_id": m["id"], "model": "OPENWEATHER", **w} for w in _windows(pts, now)]
        time.sleep(1.05)
    return rows


def fetch_meteoblue(munis, settings, client, now) -> list[dict]:
    """Meteoblue basic-day. Ventanas = días calendario locales (aproximación). Sin ráfagas en este paquete."""
    rows = []
    for m in munis:
        resp = client.get("https://my.meteoblue.com/packages/basic-day",
                          params={"lat": m["lat"], "lon": m["lon"], "apikey": settings.meteoblue_api_key,
                                  "format": "json", "windspeed": "kmh"})
        resp.raise_for_status()
        d = resp.json().get("data_day") or {}

        def at(key, i):
            v = d.get(key) or []
            return v[i] if i < len(v) else None

        for i, w in enumerate((24, 48, 72)):
            if i >= len(d.get("time") or []):
                break
            day = datetime.fromisoformat(str(d["time"][i])[:10]) + timedelta(hours=3)  # 00 h Argentina = 03 UTC
            rows.append({"municipality_id": m["id"], "model": "METEOBLUE", "window_h": w, "valid_from": day,
                         "valid_to": day + timedelta(hours=24), "rain_mm": at("precipitation", i), "gust_kmh": None,
                         "tmax_c": at("temperature_max", i), "tmin_c": at("temperature_min", i),
                         "weather_code": None})
    return rows


def fetch_wunderground(munis, settings, client) -> list[dict]:
    """Observaciones de estaciones personales (PWS) de Weather Underground."""
    rows = []
    for station in settings.list_of("wunderground_stations"):
        resp = client.get("https://api.weather.com/v2/pws/observations/current",
                          params={"stationId": station, "format": "json", "units": "m",
                                  "apiKey": settings.wunderground_api_key})
        resp.raise_for_status()
        for ob in resp.json().get("observations", []):
            lat, lon, met = ob.get("lat"), ob.get("lon"), ob.get("metric") or {}
            if lat is None or lon is None or not ob.get("obsTimeUtc"):
                continue
            near = min(munis, key=lambda m: haversine_km(lat, lon, m["lat"], m["lon"]))
            if haversine_km(lat, lon, near["lat"], near["lon"]) > 60:
                continue
            rows.append({"municipality_id": near["id"], "source": f"Weather Underground PWS {station}",
                         "observed_at": to_utc_naive(datetime.fromisoformat(ob["obsTimeUtc"].replace("Z", "+00:00"))),
                         "rain_mm_24h": met.get("precipTotal"), "gust_kmh": met.get("windGust"),
                         "temp_c": met.get("temp"), "notes": "precipTotal = acumulado desde la medianoche local"})
    return rows
