"""Prueba de fuentes gratuitas: qué responde y con qué formato (python scripts/probe_sources.py).

Se usa en el CI para decidir qué conectar. No guarda nada.
"""
import io
import json
import sys
import zipfile

import httpx

UA = {"User-Agent": "ConDi-ARGWX/0.1 (+https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio)"}
LAT, LON = -34.92, -57.95  # La Plata
EXTRA_MODELS = ["ecmwf_aifs025_single", "gfs_graphcast025", "jma_seamless", "meteofrance_seamless",
                "bom_access_global", "cma_grapes_global", "kma_seamless", "ukmo_global_deterministic_10km",
                "icon_global", "gem_global", "gfs_global", "ecmwf_ifs025", "ecmwf_ifs"]


def show(name, ok, detail):
    print(f"[{'OK ' if ok else 'NO '}] {name}: {detail}"[:600])


def get(client, url, **kw):
    r = client.get(url, timeout=40, **kw)
    return r


def main():
    c = httpx.Client(headers=UA, follow_redirects=True)
    # 1) Modelos adicionales en Open-Meteo
    try:
        r = get(c, "https://api.open-meteo.com/v1/forecast", params={
            "latitude": LAT, "longitude": LON, "hourly": "precipitation,weather_code,wind_gusts_10m",
            "forecast_hours": 6, "models": ",".join(EXTRA_MODELS)})
        h = r.json().get("hourly", {}) if r.status_code == 200 else {}
        res = {m: any(v is not None for v in (h.get(f"precipitation_{m}") or [])) for m in EXTRA_MODELS}
        show("Open-Meteo modelos extra", r.status_code == 200, f"HTTP {r.status_code} " + json.dumps(res) +
             ("" if r.status_code == 200 else r.text[:200]))
    except Exception as e:
        show("Open-Meteo modelos extra", False, repr(e))
    probes = [
        ("Open-Meteo Ensemble (ECMWF/GFS)", "https://ensemble-api.open-meteo.com/v1/ensemble",
         {"latitude": LAT, "longitude": LON, "hourly": "precipitation", "models": "ecmwf_ifs025,gfs025", "forecast_days": 2}),
        ("Open-Meteo Flood (GloFAS) Paraná/Zárate", "https://flood-api.open-meteo.com/v1/flood",
         {"latitude": -34.10, "longitude": -59.02, "daily": "river_discharge,river_discharge_mean,river_discharge_max",
          "forecast_days": 30, "past_days": 7}),
        ("Open-Meteo Flood histórico 1984", "https://flood-api.open-meteo.com/v1/flood",
         {"latitude": -35.77, "longitude": -58.50, "daily": "river_discharge", "start_date": "1984-01-01", "end_date": "1984-01-10"}),
        ("Open-Meteo Marine (Mar del Plata)", "https://marine-api.open-meteo.com/v1/marine",
         {"latitude": -38.05, "longitude": -57.45, "hourly": "wave_height,wave_direction,wave_period,sea_level_height_msl", "forecast_days": 2}),
        ("Open-Meteo Air Quality (CABA)", "https://air-quality-api.open-meteo.com/v1/air-quality",
         {"latitude": -34.6, "longitude": -58.45, "hourly": "pm2_5,pm10,ozone,dust,uv_index,european_aqi", "forecast_days": 2}),
        ("MET Norway", "https://api.met.no/weatherapi/locationforecast/2.0/compact", {"lat": LAT, "lon": LON}),
        ("RainViewer", "https://api.rainviewer.com/public/weather-maps.json", None),
    ]
    for name, url, params in probes:
        try:
            r = get(c, url, params=params)
            body = r.text
            if "json" in r.headers.get("content-type", ""):
                d = r.json()
                keys = {k: (str(v)[:160]) for k, v in (d.items() if isinstance(d, dict) else [])
                        if k in ("hourly", "daily", "radar", "satellite", "host", "properties", "error", "reason")}
                show(name, r.status_code == 200, f"HTTP {r.status_code} {json.dumps(keys)[:450]}")
            else:
                show(name, r.status_code == 200, f"HTTP {r.status_code} {r.headers.get('content-type')} {body[:200]!r}")
        except Exception as e:
            show(name, False, repr(e))
    # 2) SMN datos abiertos (zip con txt)
    for dato in ("tiepre", "estaciones", "pron5d"):
        try:
            r = get(c, "https://ssl.smn.gob.ar/dpd/zipopendata.php", params={"dato": dato})
            ok = r.status_code == 200 and r.content[:2] == b"PK"
            detail = f"HTTP {r.status_code} {r.headers.get('content-type')} {len(r.content)} bytes"
            if ok:
                z = zipfile.ZipFile(io.BytesIO(r.content))
                n = z.namelist()
                txt = z.read(n[0]).decode("latin-1")
                detail += f" archivos={n} lineas={len(txt.splitlines())} | " + " || ".join(txt.splitlines()[:4])
            else:
                detail += " " + repr(r.content[:150])
            show(f"SMN {dato}", ok, detail)
        except Exception as e:
            show(f"SMN {dato}", False, repr(e))
    # 3) Imágenes satelitales
    for name, url in (("NOAA STAR GOES-19 ssa GEOCOLOR", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/GEOCOLOR/latest.jpg"),
                      ("NOAA STAR GOES-19 ssa banda 13", "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/13/latest.jpg")):
        try:
            r = get(c, url)
            show(name, r.status_code == 200 and r.headers.get("content-type", "").startswith("image"),
                 f"HTTP {r.status_code} {r.headers.get('content-type')} {len(r.content)} bytes")
        except Exception as e:
            show(name, False, repr(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
