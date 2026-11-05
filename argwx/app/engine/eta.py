"""Estimación de llegada de una celda o frente (radar / satélite / reportes).

Velocidad = Distancia recorrida / Tiempo transcurrido
ETA (tiempo de arribo) = Distancia restante / Velocidad
"""
import math
from datetime import datetime, timedelta

from app.engine.geo import EARTH_KM, bearing_deg, haversine_km


def storm_motion(p1: dict, p2: dict) -> dict:
    hours = (p2["time"] - p1["time"]).total_seconds() / 3600
    if hours <= 0:
        raise ValueError("La segunda posición debe ser posterior a la primera")
    dist = haversine_km(p1["lat"], p1["lon"], p2["lat"], p2["lon"])
    if dist < 0.5:
        raise ValueError("La celda no se desplazó lo suficiente para estimar velocidad")
    return {"distance_km": round(dist, 1), "hours": round(hours, 2), "speed_kmh": round(dist / hours, 1),
            "bearing_deg": round(bearing_deg(p1["lat"], p1["lon"], p2["lat"], p2["lon"]), 1)}


def arrival_times(p1: dict, p2: dict, targets: list[dict], corridor_km: float = 25, max_hours: float = 12) -> dict:
    motion = storm_motion(p1, p2)
    speed, course = motion["speed_kmh"], math.radians(motion["bearing_deg"])
    out = []
    for t in targets:
        d = haversine_km(p2["lat"], p2["lon"], t["lat"], t["lon"])
        if d < 1e-6:
            out.append({**_target(t), "distance_km": 0.0, "cross_track_km": 0.0, "eta_hours": 0.0,
                        "arrival_time": p2["time"]})
            continue
        ang = d / EARTH_KM
        b = math.radians(bearing_deg(p2["lat"], p2["lon"], t["lat"], t["lon"]))
        xt = math.asin(max(-1.0, min(1.0, math.sin(ang) * math.sin(b - course))))
        cos_ratio = math.cos(ang) / max(math.cos(xt), 1e-12)
        at = math.acos(max(-1.0, min(1.0, cos_ratio))) * EARTH_KM
        if math.cos(b - course) <= 0 or abs(xt * EARTH_KM) > corridor_km:
            continue
        eta = at / speed
        if eta <= max_hours:
            out.append({**_target(t), "distance_km": round(at, 1), "cross_track_km": round(abs(xt * EARTH_KM), 1),
                        "eta_hours": round(eta, 2), "arrival_time": p2["time"] + timedelta(hours=eta)})
    out.sort(key=lambda r: r["eta_hours"])
    return {"motion": motion, "corridor_km": corridor_km, "max_hours": max_hours, "targets": out}


def _target(t: dict) -> dict:
    return {k: t[k] for k in ("id", "name") if k in t}


def parse_time(value) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
