"""Umbrales iniciales PROPIOS de ARGWX (no son los umbrales oficiales del SMN).

Son valores de partida, editables y a calibrar con la verificación estadística.
Cada variable se evalúa sobre una ventana de 24 h.
"""
from app.engine.levels import idx, max_level

THRESHOLDS = {
    "rain_mm": {"YELLOW": 30, "ORANGE": 60, "RED": 100, "PURPLE": 150},   # lluvia acumulada (mm/24 h)
    "gust_kmh": {"YELLOW": 60, "ORANGE": 80, "RED": 100, "PURPLE": 120},  # ráfaga máxima (km/h)
    "tmax_c": {"YELLOW": 36, "ORANGE": 39, "RED": 42},                    # temperatura máxima (°C)
}
# Código meteorológico WMO máximo de la ventana: 95 tormenta, 96-98 tormenta fuerte/granizo leve, 99 granizo fuerte.
STORM_CODES = {95: "YELLOW", 96: "ORANGE", 97: "ORANGE", 98: "ORANGE", 99: "RED"}
HAZARDS = {"rain_mm": "lluvia", "weather_code": "tormenta", "gust_kmh": "viento", "tmax_c": "calor"}
_ORDER = list(HAZARDS.values())


def level_for(var: str, value) -> str:
    if value is None:
        return "GREEN"
    if var == "weather_code":
        return STORM_CODES.get(int(value), "GREEN")
    level = "GREEN"
    for name, limit in THRESHOLDS[var].items():
        if limit is not None and value >= limit and idx(name) > idx(level):
            level = name
    return level


def evaluate(values: dict) -> tuple[str, str | None, dict]:
    """Devuelve (nivel, fenómeno principal, nivel por fenómeno) para los valores de un modelo."""
    per = {HAZARDS[v]: level_for(v, values.get(v)) for v in HAZARDS}
    level = max_level(*per.values())
    if level == "GREEN":
        return level, None, per
    hazard = max(per, key=lambda h: (idx(per[h]), -_ORDER.index(h)))
    return level, hazard, per
