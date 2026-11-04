"""Alturas de ríos observadas: API pública del INA (alerta5), que reúne las escalas de Prefectura Naval y la Red
Hidrológica Nacional, con los niveles oficiales de alerta y evacuación de cada escala.

Verificado desde GitHub (4/11/2026): obs/puntual/estaciones (4695 estaciones) y obs/puntual/series?var_id=2 (alturas)
responden en JSON y sin clave. Las mediciones se leen de obs/puntual/series/{id}/observaciones.
"""
import logging
import time
from datetime import datetime, timedelta

import httpx

from app.util import iso, utcnow

log = logging.getLogger("argwx.ina")
BASE = "https://alerta.ina.gob.ar/a5"
ALTURA_VAR = 2
PBA = {"BUENOSAIRES", "BUENOS AIRES"}
MAX_STATIONS = 60


def _get(client, path, params=None, timeout=120):
    for attempt in range(3):
        try:
            r = client.get(f"{BASE}/{path}", params={"format": "json", **(params or {})},
                           timeout=httpx.Timeout(timeout, connect=30))
            r.raise_for_status()
            return r.json()
        except (httpx.TransportError, httpx.HTTPStatusError):
            if attempt == 2:
                raise
            time.sleep(10 * (attempt + 1))


def _rows(data):
    return data if isinstance(data, list) else (data or {}).get("rows") or (data or {}).get("observaciones") or []


def _coords(st):
    c = ((st.get("geom") or {}).get("coordinates")) or [None, None]
    return (c[1], c[0]) if c[0] is not None else (None, None)


def pba_series(stations: list[dict], series: list[dict]) -> list[dict]:
    """Series de altura de las escalas de la provincia. Primero las que tienen niveles de alerta y evacuación."""
    by_id = {s["id"]: s for s in stations}
    out, seen = [], set()
    for se in series:
        st = {**(se.get("estacion") or {}), **by_id.get((se.get("estacion") or {}).get("id"), {})}
        if not st or not st.get("has_obs", True) or st.get("public") is False:
            continue
        prov = (st.get("provincia") or "").upper().replace(" ", "")
        lat, lon = _coords(st)
        if lat is None or prov not in {p.replace(" ", "") for p in PBA}:
            continue
        if st["id"] in seen:
            continue
        seen.add(st["id"])
        out.append({"serie": se["id"], "estacion_id": st["id"], "estacion": st.get("nombre"), "rio": st.get("rio"),
                    "red": (st.get("red") or {}).get("nombre") or st.get("tabla"), "lat": lat, "lon": lon,
                    "alerta": st.get("nivel_alerta"), "evacuacion": st.get("nivel_evacuacion"),
                    "aguas_bajas": st.get("nivel_aguas_bajas"), "propietario": st.get("propietario")})
    out.sort(key=lambda x: (x["alerta"] is None, x["estacion"] or ""))
    return out[:MAX_STATIONS]


def parse_obs(data) -> list[tuple[str, float]]:
    out = []
    for o in _rows(data):
        if isinstance(o, dict):
            t, v = o.get("timestart") or o.get("timeend"), o.get("valor")
        elif isinstance(o, (list, tuple)) and len(o) >= 3:
            t, v = o[0], o[2]
        else:
            continue
        try:
            out.append((str(t), float(v)))
        except (TypeError, ValueError):
            continue
    out.sort()
    return out


def status(value: float | None, alert, evac, low) -> tuple[str, str]:
    if value is None:
        return "GREEN", "Sin dato"
    if evac is not None and value >= evac:
        return "RED", "Evacuación"
    if alert is not None and value >= alert:
        return "ORANGE", "Alerta"
    if low is not None and value <= low:
        return "GREEN", "Aguas bajas"
    return "GREEN", "Normal"


def export_observed(client, munis: list[dict], days: int = 30) -> dict:
    stations = _rows(_get(client, "obs/puntual/estaciones"))
    series = _rows(_get(client, "obs/puntual/series", {"var_id": ALTURA_VAR}))
    chosen = pba_series(stations, series)
    end, start = utcnow(), utcnow() - timedelta(days=days)
    out, errors = [], 0
    for s in chosen:
        try:
            obs = parse_obs(_get(client, f"obs/puntual/series/{s['serie']}/observaciones",
                                 {"timestart": start.strftime("%Y-%m-%d"), "timeend": end.strftime("%Y-%m-%dT%H:%M")},
                                 timeout=60))
        except Exception as exc:
            errors += 1
            log.warning("INA serie %s: %s", s["serie"], exc)
            continue
        if not obs:
            continue
        last_t, last_v = obs[-1]
        try:
            t_last = datetime.fromisoformat(last_t.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            t_last = None
        if t_last and (end - t_last).days > 7:
            continue  # escala sin datos recientes
        prev = [v for t, v in obs if t <= (t_last - timedelta(hours=24)).isoformat()] if t_last else []
        level, label = status(last_v, s["alerta"], s["evacuacion"], s["aguas_bajas"])
        out.append({**s, "altura_m": round(last_v, 2), "fecha": last_t, "cambio_24h": round(last_v - prev[-1], 2) if prev else None,
                    "nivel": level, "estado": label, "serie_30d": [[t[:16], round(v, 2)] for t, v in obs[-120:]]})
    if not out and errors:
        raise RuntimeError(f"INA no devolvió mediciones ({errors} series con error)")
    out.sort(key=lambda x: (-["GREEN", "YELLOW", "ORANGE", "RED"].index(x["nivel"]), x["estacion"] or ""))
    return {"generated_at": iso(utcnow()), "fuente": "INA · Sistema de Alerta Hidrológico (alerta5): escalas de "
            "Prefectura Naval Argentina y Red Hidrológica Nacional", "estaciones": out}
