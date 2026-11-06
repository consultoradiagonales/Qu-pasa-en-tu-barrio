"""Verificación estadística: MAE, RMSE y BIAS (pronóstico - observación)."""
import math


def metrics(pairs: list[tuple[float, float]]) -> dict:
    pairs = [(f, o) for f, o in pairs if f is not None and o is not None]
    n = len(pairs)
    if n == 0:
        return {"n": 0, "mae": None, "rmse": None, "bias": None}
    err = [f - o for f, o in pairs]
    return {"n": n, "mae": round(sum(abs(e) for e in err) / n, 2),
            "rmse": round(math.sqrt(sum(e * e for e in err) / n), 2), "bias": round(sum(err) / n, 2)}
