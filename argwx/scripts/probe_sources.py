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


def second_round(c):
    """Detalles de formato: claves de ensambles, cobertura de radar, estaciones del SMN, tamaños de GOES."""
    try:
        r = get(c, "https://ensemble-api.open-meteo.com/v1/ensemble", params={
            "latitude": LAT, "longitude": LON, "hourly": "precipitation", "models": "ecmwf_ifs025", "forecast_days": 1})
        keys = list(r.json().get("hourly", {}).keys())
        show("Ensemble claves", r.status_code == 200, f"{len(keys)} claves: {keys[:4]} ... {keys[-2:]}")
    except Exception as e:
        show("Ensemble claves", False, repr(e))
    try:
        wm = get(c, "https://api.rainviewer.com/public/weather-maps.json").json()
        frame = wm["radar"]["past"][-1]["path"]
        from PIL import Image  # noqa: F401  (solo si está instalado)
    except ImportError:
        frame = None
    except Exception as e:
        show("RainViewer", False, repr(e))
        frame = None
    try:
        # Cobertura del radar: tile de cobertura (z=4) sobre Buenos Aires (x=5, y=9)
        r = get(c, "https://tilecache.rainviewer.com/v2/coverage/0/256/4/5/9/0/0_0.png")
        show("RainViewer cobertura PBA (z4 5/9)", r.status_code == 200, f"HTTP {r.status_code} {r.headers.get('content-type')} {len(r.content)} bytes")
        open("/tmp/rv_cov.png", "wb").write(r.content)
        if frame:
            r2 = get(c, f"https://tilecache.rainviewer.com{frame}/256/4/5/9/2/1_1.png")
            show("RainViewer radar PBA (z4 5/9)", r2.status_code == 200, f"HTTP {r2.status_code} {len(r2.content)} bytes")
    except Exception as e:
        show("RainViewer cobertura", False, repr(e))
    for dato in ("estaciones", "tiepre"):
        try:
            r = get(c, "https://ssl.smn.gob.ar/dpd/zipopendata.php", params={"dato": dato})
            z = zipfile.ZipFile(io.BytesIO(r.content))
            lines = z.read(z.namelist()[0]).decode("latin-1").splitlines()
            pba = [ln for ln in lines if "BUENOS AIRES" in ln.upper() or "Plata" in ln or "Mar del" in ln][:6]
            show(f"SMN {dato} muestra", True, " || ".join(lines[:3] + ["..."] + pba))
        except Exception as e:
            show(f"SMN {dato} muestra", False, repr(e))
    for size in ("600x600", "1200x1200", "900x540", "1800x1080", "2400x2400"):
        try:
            r = c.head(f"https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/GEOCOLOR/{size}.jpg", timeout=30)
            show(f"GOES ssa {size}", r.status_code == 200, f"HTTP {r.status_code} {r.headers.get('content-length')}")
        except Exception as e:
            show(f"GOES ssa {size}", False, repr(e))


def main():
    c = httpx.Client(headers=UA, follow_redirects=True)
    if "--detalle" in sys.argv:
        return second_round(c)
    # 1) Modelos adicionales en Open-Meteo
    try:
        r = c.get("https://api.open-meteo.com/v1/forecast", timeout=90, params={
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
