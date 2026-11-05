"""Climatología y calibración de probabilidades a partir de la base histórica (sin IA, solo conteos).

- climatology(): con qué frecuencia llovió al menos X mm en 24 h y en 72 h, por mes, en la serie histórica.
- verification(): aciertos, falsas alarmas y error de cada modelo frente a lo observado, por anticipación.
- calibration(): cuando k de n modelos pronosticaron al menos X mm, en qué porcentaje de los casos ocurrió.
  Es la "probabilidad calibrada" que acompaña a las alertas.
"""
from collections import defaultdict
from datetime import date
from statistics import mean, quantiles

DAY_THRESHOLDS = (10, 20, 30, 60)          # mm en 24 h (30 y 60 = Amarilla y Naranja del motor)
SUM72_THRESHOLDS = (20, 40, 70, 110)       # mm en 72 h (umbrales de crecidas)
FRACTION_BINS = ((0.0, 0.0), (0.01, 0.25), (0.26, 0.5), (0.51, 0.75), (0.76, 1.0))
MIN_CASES = 10                             # con menos casos la frecuencia observada no es confiable


def climatology(series: dict[str, dict], start_year: int, end_year: int) -> dict:
    """series: punto -> {"time": ["AAAA-MM-DD", ...], "rain": [mm, ...]} (diaria). Solo años completos del rango."""
    out = {}
    for pid, s in series.items():
        days = [(date.fromisoformat(t), v) for t, v in zip(s["time"], s["rain"])
                if v is not None and start_year <= int(t[:4]) <= end_year]
        by_month: dict[int, dict] = defaultdict(lambda: {"d": [], "s3": []})
        for i, (d, v) in enumerate(days):
            by_month[d.month]["d"].append(v)
            if i >= 2 and (d - days[i - 2][0]).days == 2:
                by_month[d.month]["s3"].append(v + days[i - 1][1] + days[i - 2][1])
        months = {}
        for m, vals in sorted(by_month.items()):
            d, s3 = vals["d"], vals["s3"]
            months[str(m)] = {
                "dias": len(d),
                "p24": {str(t): round(100 * sum(x >= t for x in d) / len(d), 2) for t in DAY_THRESHOLDS},
                "p72": {str(t): round(100 * sum(x >= t for x in s3) / len(s3), 2) for t in SUM72_THRESHOLDS} if s3 else {},
                "pct24": _pcts(d), "pct72": _pcts(s3)}
        out[pid] = months
    return {"periodo": f"{start_year}-{end_year}", "umbrales_24h": DAY_THRESHOLDS, "umbrales_72h": SUM72_THRESHOLDS,
            "puntos": out}


def _pcts(xs: list[float]) -> dict:
    if len(xs) < 20:
        return {}
    q = quantiles(xs, n=100)
    return {"p50": round(q[49], 1), "p90": round(q[89], 1), "p95": round(q[94], 1), "p99": round(q[98], 1),
            "max": round(max(xs), 1)}


def rarity(value: float | None, pct: dict) -> str | None:
    """Ubica un valor pronosticado en la distribución histórica del mes."""
    if value is None or not pct:
        return None
    if value >= pct["max"]:
        return "por encima del máximo histórico del mes"
    for key, label in (("p99", "en el 1 % más alto"), ("p95", "en el 5 % más alto"), ("p90", "en el 10 % más alto")):
        if value >= pct[key]:
            return label
    return "dentro de lo habitual"


def contingency(pairs: list[tuple[float, float]], threshold: float) -> dict:
    """pairs: (pronóstico, observado). Tabla 2x2 para 'lluvia >= umbral' y sus índices."""
    a = b = c = d = 0
    for f, o in pairs:
        fe, oe = f >= threshold, o >= threshold
        a += fe and oe
        b += fe and not oe
        c += oe and not fe
        d += not fe and not oe
    return {"aciertos": a, "falsas_alarmas": b, "no_previstos": c, "correctos_sin_evento": d,
            "pod": round(a / (a + c), 2) if a + c else None,          # de los eventos, cuántos se previeron
            "far": round(b / (a + b), 2) if a + b else None,          # de las alarmas, cuántas fueron falsas
            "csi": round(a / (a + b + c), 2) if a + b + c else None,
            "sesgo": round((a + b) / (a + c), 2) if a + c else None}  # >1 sobrepronostica, <1 subpronostica


def verification(rows: list[dict]) -> dict:
    """rows: {"modelo", "plazo", "pronostico", "observado"} -> métricas por modelo y anticipación."""
    groups: dict[tuple, list] = defaultdict(list)
    for r in rows:
        if r["pronostico"] is not None and r["observado"] is not None:
            groups[(r["modelo"], r["plazo"])].append((r["pronostico"], r["observado"]))
    out = {}
    for (model, lead), pairs in sorted(groups.items()):
        err = [f - o for f, o in pairs]
        out.setdefault(model, {})[str(lead)] = {
            "n": len(pairs), "mae": round(mean(abs(e) for e in err), 2), "sesgo_mm": round(mean(err), 2),
            "umbrales": {str(t): contingency(pairs, t) for t in DAY_THRESHOLDS}}
    return out


def _bin(fraction: float) -> int:
    for i, (lo, hi) in enumerate(FRACTION_BINS):
        if lo <= round(fraction, 2) <= hi:
            return i
    return len(FRACTION_BINS) - 1


def calibration(rows: list[dict]) -> dict:
    """Frecuencia observada del evento según qué fracción de los modelos lo pronosticó.

    rows: {"punto", "fecha", "modelo", "plazo", "pronostico", "observado"}. Se agrupan por (punto, fecha, plazo).
    """
    cases: dict[tuple, dict] = {}
    for r in rows:
        if r["pronostico"] is None or r["observado"] is None:
            continue
        key = (r["punto"], r["fecha"], r["plazo"])
        case = cases.setdefault(key, {"obs": r["observado"], "f": []})
        case["f"].append(r["pronostico"])
    out = {}
    for t in DAY_THRESHOLDS:
        for lead in sorted({k[2] for k in cases}):
            bins = [{"desde": lo, "hasta": hi, "casos": 0, "ocurrio": 0} for lo, hi in FRACTION_BINS]
            for (_, _, ld), case in cases.items():
                if ld != lead or len(case["f"]) < 2:
                    continue
                frac = sum(f >= t for f in case["f"]) / len(case["f"])
                b = bins[_bin(frac)]
                b["casos"] += 1
                b["ocurrio"] += case["obs"] >= t
            for b in bins:
                b["frecuencia"] = round(100 * b["ocurrio"] / b["casos"], 1) if b["casos"] else None
                b["confiable"] = b["casos"] >= MIN_CASES
            out.setdefault(str(t), {})[str(lead)] = bins
    return {"bins_fraccion_modelos": FRACTION_BINS, "minimo_casos": MIN_CASES, "tabla": out}


def calibrated_probability(calib: dict | None, threshold: int, lead: int, agreeing: int, total: int) -> dict | None:
    """Probabilidad observada para 'agreeing de total modelos pronostican >= threshold' (None si no hay tabla)."""
    if not calib or total < 2:
        return None
    bins = (calib.get("tabla", {}).get(str(threshold)) or {}).get(str(lead))
    if not bins:
        return None
    b = bins[_bin(agreeing / total)]
    if not b["casos"]:
        return None
    return {"probabilidad": b["frecuencia"], "casos": b["casos"], "confiable": b["confiable"]}
