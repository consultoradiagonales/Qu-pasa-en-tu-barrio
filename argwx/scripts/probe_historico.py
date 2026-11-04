"""Prueba de fuentes públicas para la base histórica y la API del SMN (python scripts/probe_historico.py).

Se usa en el CI para decidir qué conectar. No guarda nada.
"""
import html
import io
import json
import re
import sys
import zipfile
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
UA = {"User-Agent": "ConDi-ARGWX/0.1 (+https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio)"}
LAT, LON = -34.92, -57.95  # La Plata
PBA_PORTS = ("SAN NICOLAS", "RAMALLO", "SAN PEDRO", "BARADERO", "ZARATE", "CAMPANA", "ESCOBAR", "TIGRE",
             "SAN FERNANDO", "BUENOS AIRES", "LA PLATA", "ATALAYA", "SAN CLEMENTE", "MAR DEL PLATA", "BAHIA BLANCA")
MODELS = ["gfs_seamless", "icon_seamless", "ecmwf_ifs025", "ecmwf_aifs025_single", "gem_seamless", "ukmo_seamless",
          "jma_seamless", "meteofrance_seamless", "cma_grapes_global"]


def show(name, ok, detail):
    print(f"[{'OK ' if ok else 'NO '}] {name}: {detail}"[:1500], flush=True)


def heads(r):
    return {k: r.headers.get(k) for k in ("content-type", "content-length", "access-control-allow-origin")}


def text_of(body: bytes) -> str:
    for enc in ("utf-8", "latin-1"):
        try:
            return body.decode(enc)
        except UnicodeDecodeError:
            continue
    return body.decode("utf-8", "replace")


def plain(page: str) -> str:
    page = re.sub(r"(?is)<(script|style).*?</\1>", " ", page)
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"(?s)<[^>]+>", " | ", page)))


def get(c, name, url, **kw):
    try:
        r = c.get(url, timeout=60, **kw)
        show(name, r.status_code == 200, f"HTTP {r.status_code} {heads(r)} {len(r.content)} bytes")
        return r
    except Exception as exc:
        show(name, False, f"{type(exc).__name__}: {exc}")
        return None


def smn(c):
    print("\n==== SMN ====")
    r = get(c, "SMN CAP (feed oficial)", "https://ssl.smn.gob.ar/CAP/AR.php")
    if r is not None and r.status_code == 200:
        t = text_of(r.content)
        titles = re.findall(r"<title>(.*?)</title>", t, re.S)
        print("   títulos:", [html.unescape(x)[:90] for x in titles[:12]], f"(total {len(titles)})")
        try:
            from app.providers import smn as smn_mod

            alerts = smn_mod.parse_feed(t, fetch=lambda u: c.get(u, timeout=40).text)
            kinds = {}
            for a in alerts:
                kinds.setdefault((a["hazard"], a["level"]), 0)
                kinds[(a["hazard"], a["level"])] += 1
            print("   alertas por fenómeno y nivel:", kinds)
            print("   títulos de alertas:", sorted({a["title"] for a in alerts})[:20])
        except Exception as exc:
            print("   parse:", type(exc).__name__, exc)
    for path in ("map_items/weather", "map_items/forecast/1", "alerts/type/AL", "alerts/type/AC", "alerts/type/IN",
                 "alerts/type/SA", "alerts/type/AV"):
        r = get(c, f"ws.smn.gob.ar/{path}", f"https://ws.smn.gob.ar/{path}")
        if r is not None and r.status_code == 200:
            print("   muestra:", text_of(r.content)[:500].replace("\n", " "))
    for url in ("https://ws1.smn.gob.ar/v1/", "https://ws1.smn.gob.ar/v1/warning/alert/area/1"):
        r = get(c, url, url)
        if r is not None:
            print("   muestra:", text_of(r.content)[:200].replace("\n", " "))
    r = get(c, "smn.gob.ar/descarga-de-datos", "https://www.smn.gob.ar/descarga-de-datos")
    if r is not None and r.status_code == 200:
        links = sorted(set(re.findall(r'href="([^"]+)"', text_of(r.content))))
        keep = [x for x in links if re.search(r"dpd|opendata|descarga|\.zip|\.txt|\.csv", x, re.I)]
        print("   enlaces de descarga:", keep[:60])
    print("\n---- datos.gob.ar (catálogo del SMN) ----")
    try:
        r = c.get("https://datos.gob.ar/api/3/action/package_search", params={"q": "smn", "rows": 60}, timeout=60)
        res = r.json()["result"]["results"]
        for p in res:
            if "smn" not in p["name"]:
                continue
            urls = [(x.get("format"), x.get("url")) for x in p.get("resources", [])]
            print(f"   {p['name']}: {urls[:4]}")
    except Exception as exc:
        show("datos.gob.ar package_search", False, f"{type(exc).__name__}: {exc}")
    for dato in ("alertas", "alertas365", "regdiario", "datohorario", "normales", "estadisticas", "radiacion"):
        try:
            r = c.get("https://ssl.smn.gob.ar/dpd/zipopendata.php", params={"dato": dato}, timeout=60)
            ok = r.status_code == 200 and r.content[:2] == b"PK"
            detail = f"HTTP {r.status_code} {len(r.content)} bytes"
            if ok:
                z = zipfile.ZipFile(io.BytesIO(r.content))
                first = z.namelist()[0]
                lines = text_of(z.read(first)).splitlines()
                detail += f" archivos={z.namelist()[:5]} lineas={len(lines)} | " + " || ".join(lines[:5])
            show(f"SMN zipopendata dato={dato}", ok, detail)
        except Exception as exc:
            show(f"SMN zipopendata dato={dato}", False, f"{type(exc).__name__}: {exc}")


def rivers(c):
    print("\n==== Ríos (observados) ====")
    r = get(c, "Prefectura Naval · alturas", "https://contenidosweb.prefecturanaval.gob.ar/alturas/")
    if r is not None and r.status_code == 200:
        t = plain(text_of(r.content))
        i = t.upper().find("PUERTO")
        print("   encabezado:", t[max(0, i - 50):i + 400])
        up = t.upper()
        for port in PBA_PORTS:
            j = up.find(port)
            if j >= 0:
                print(f"   {port}:", t[j:j + 260])
    for url in ("https://alerta.ina.gob.ar/a5/", "https://alerta.ina.gob.ar/pub/", "https://www.ina.gob.ar/alerta/",
                "https://snih.hidricosargentina.gob.ar/"):
        r = get(c, url, url)
        if r is not None and r.status_code == 200:
            print("   muestra:", plain(text_of(r.content))[:300])


def previous_runs(c):
    print("\n==== Open-Meteo: pronósticos de corridas anteriores (verificación) ====")
    hourly = "precipitation,precipitation_previous_day1,precipitation_previous_day2,precipitation_previous_day3"
    for days in (92, 400):
        try:
            r = c.get("https://previous-runs-api.open-meteo.com/v1/forecast", timeout=120, params={
                "latitude": LAT, "longitude": LON, "hourly": hourly, "models": ",".join(MODELS), "past_days": days,
                "forecast_days": 1, "timezone": "UTC"})
            if r.status_code != 200:
                show(f"Previous runs past_days={days}", False, f"HTTP {r.status_code} {r.text[:300]}")
                continue
            h = r.json().get("hourly", {})
            times = h.get("time", [])
            out = {}
            for key, vals in h.items():
                if key == "time":
                    continue
                idx = [i for i, v in enumerate(vals) if v is not None]
                out[key] = f"{len(idx)} valores desde {times[idx[0]][:10] if idx else '-'}"
            show(f"Previous runs past_days={days}", True, f"{len(times)} horas; " + json.dumps(out, ensure_ascii=False))
        except Exception as exc:
            show(f"Previous runs past_days={days}", False, f"{type(exc).__name__}: {exc}")
    try:
        r = c.get("https://historical-forecast-api.open-meteo.com/v1/forecast", timeout=120, params={
            "latitude": LAT, "longitude": LON, "start_date": "2024-01-01", "end_date": "2024-01-07",
            "hourly": "precipitation", "models": ",".join(MODELS)})
        h = r.json().get("hourly", {}) if r.status_code == 200 else {}
        res = {k: sum(v is not None for v in vals) for k, vals in h.items() if k != "time"}
        show("Historical forecast 2024-01", r.status_code == 200, f"HTTP {r.status_code} {json.dumps(res)}")
    except Exception as exc:
        show("Historical forecast", False, f"{type(exc).__name__}: {exc}")


def main():
    with httpx.Client(headers=UA, follow_redirects=True) as c:
        for part in (smn, rivers, previous_runs):
            try:
                part(c)
            except Exception as exc:
                show(part.__name__, False, f"{type(exc).__name__}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
