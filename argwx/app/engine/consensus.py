"""Algoritmo de consenso multimodelo.

Consenso = modelos coincidentes / modelos analizados.
Regla: ninguna alerta puede depender de un único modelo. Un nivel se emite solo si lo
alcanzan al menos `min_agreeing` modelos y al menos la mitad de los modelos analizados.
"""
from collections import Counter
from statistics import median

from app.engine.levels import LEVELS, idx
from app.engine.thresholds import evaluate

VARS = ("rain_mm", "gust_kmh", "tmax_c", "tmin_c")


def confidence_label(fraction: float) -> str:
    pct = round(fraction * 100)
    if pct <= 40:
        return "Baja"
    if pct <= 70:
        return "Media"
    if pct <= 85:
        return "Alta"
    return "Muy alta"


def consensus(per_model: dict[str, dict], min_agreeing: int = 2) -> dict:
    votes = {}
    for model, values in per_model.items():
        level, hazard, _ = evaluate(values)
        votes[model] = {"level": level, "hazard": hazard}
    n = len(votes)
    if n == 0:
        return {"level": "GREEN", "consensus": 0.0, "confidence_label": "Baja", "models_analyzed": 0,
                "agreeing_models": [], "hazard": None, "votes": {}, "stats": {}, "unconfirmed_signal": None,
                "note": "Sin datos de modelos"}

    chosen, agreeing = "GREEN", []
    for level in reversed(LEVELS[1:]):
        ag = [m for m, v in votes.items() if idx(v["level"]) >= idx(level)]
        if len(ag) >= min_agreeing and len(ag) / n >= 0.5:
            chosen, agreeing = level, ag
            break
    if chosen == "GREEN":
        agreeing = [m for m, v in votes.items() if v["level"] == "GREEN"]
    fraction = len(agreeing) / n

    hazards = Counter(votes[m]["hazard"] for m in agreeing if votes[m]["hazard"])
    hazard = hazards.most_common(1)[0][0] if hazards else None

    above = [m for m, v in votes.items() if idx(v["level"]) > idx(chosen)]
    unconfirmed = None
    if above:
        top = max((votes[m]["level"] for m in above), key=idx)
        unconfirmed = {"level": top, "models": above,
                       "note": "Señal no confirmada: no alcanza el consenso mínimo"}

    stats = {}
    for var in VARS:
        xs = [v[var] for v in per_model.values() if v.get(var) is not None]
        if xs:
            stats[var] = {"median": round(median(xs), 1), "min": round(min(xs), 1), "max": round(max(xs), 1)}

    note = None
    if n < min_agreeing:
        note = f"Solo {n} modelo disponible: no se emiten alertas propias con un único modelo"
    return {"level": chosen, "consensus": round(fraction, 2), "confidence_label": confidence_label(fraction),
            "models_analyzed": n, "agreeing_models": agreeing, "hazard": hazard, "votes": votes,
            "stats": stats, "unconfirmed_signal": unconfirmed, "note": note}
