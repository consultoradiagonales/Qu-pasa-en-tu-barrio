"""Modelo ponderado ARGWX: combina los modelos según cuánto acertó cada uno.

Se entrena con la base histórica de verificación (lluvia diaria pronosticada por
cada modelo con 1, 2 y 3 días de anticipación frente a la lluvia observada por
ERA5, en los puntos de referencia de cada sección electoral):

1. Peso por modelo: inverso del error cuadrático medio en los días con lluvia
   (observada o pronosticada >= 1 mm). Los días secos, que son la mayoría, no
   deciden quién es mejor pronosticando lluvia.
2. Contracción hacia pesos iguales cuando hay pocos casos (n / (n + 30)).
3. Pesos por punto de referencia (sección) si hay casos suficientes; si no, los
   pesos generales de esa anticipación.
4. Combinación: MEDIANA PONDERADA de los pronósticos. Se probó también la media
   ponderada con corrección de sesgo, pero en la validación quedó peor que la
   mediana simple (los modelos que exageran tormentas arrastran la media, y la
   corrección contra ERA5 achica la lluvia porque ERA5 suaviza las tormentas).
   El sesgo de cada modelo se informa, pero no se aplica.

Validación: se ajusta con el 70 % más antiguo de los días y se mide en el 30 %
más reciente, contra la mediana de modelos (lo que usa el consenso actual) y
contra cada modelo por separado.

Sólo pondera la lluvia: es la única variable con verificación histórica. Ráfagas
y temperaturas siguen con la mediana.
"""
from collections import defaultdict
from math import sqrt
from statistics import median

WET_MM = 1.0           # un día cuenta como "con lluvia" desde 1 mm
SHRINK_N = 30          # casos para confiar a medias en el peso por desempeño
MIN_POINT_CASES = 60   # casos con lluvia mínimos para pesos propios de un punto
RATIO_BOUNDS = (0.5, 2.0)
TRAIN_SHARE = 0.7


def _cases(rows: list[dict]) -> dict[tuple, dict]:
    """Filas largas -> {(punto, fecha, plazo): {"obs": mm, "f": {modelo: mm}}}."""
    cases: dict[tuple, dict] = {}
    for r in rows:
        if r.get("pronostico") is None or r.get("observado") is None:
            continue
        key = (r["punto"], r["fecha"], int(r["plazo"]))
        case = cases.setdefault(key, {"obs": float(r["observado"]), "f": {}})
        case["f"][r["modelo"]] = float(r["pronostico"])
    return cases


def _wet(case: dict) -> bool:
    return case["obs"] >= WET_MM or max(case["f"].values(), default=0) >= WET_MM


def _fit_group(cases: list[dict]) -> dict:
    """Factor de sesgo, error y peso de cada modelo dentro de un grupo de casos."""
    wet = [c for c in cases if _wet(c)]
    sums: dict[str, dict] = defaultdict(lambda: {"f": 0.0, "o": 0.0, "n": 0})
    for c in wet:
        for m, f in c["f"].items():
            sums[m]["f"] += f
            sums[m]["o"] += c["obs"]
            sums[m]["n"] += 1
    if not sums:
        return {}
    factor = {}
    for m, s in sums.items():
        ratio = s["o"] / s["f"] if s["f"] > 0 else 1.0
        factor[m] = min(RATIO_BOUNDS[1], max(RATIO_BOUNDS[0], ratio))  # observado / pronosticado (sólo informativo)
    sq = defaultdict(float)
    for c in wet:
        for m, f in c["f"].items():
            sq[m] += (f - c["obs"]) ** 2
    models = sorted(sums)
    rmse = {m: sqrt(sq[m] / sums[m]["n"]) for m in models}
    raw = {m: 1 / max(rmse[m], 0.1) ** 2 for m in models}
    total = sum(raw.values())
    uniform = 1 / len(models)
    out = {}
    for m in models:
        n = sums[m]["n"]
        trust = n / (n + SHRINK_N)
        out[m] = {"peso": trust * raw[m] / total + (1 - trust) * uniform,
                  "sesgo_relativo": round(factor[m], 3), "rmse_mm": round(rmse[m], 2), "n": n}
    norm = sum(v["peso"] for v in out.values())
    for v in out.values():
        v["peso"] = round(v["peso"] / norm, 4)
    return out


def fit(rows: list[dict]) -> dict:
    """Ajusta pesos y factores por anticipación (general) y por punto y anticipación."""
    cases = _cases(rows)
    by_lead: dict[int, list] = defaultdict(list)
    by_point: dict[tuple, list] = defaultdict(list)
    for (punto, _, lead), c in cases.items():
        by_lead[lead].append(c)
        by_point[(punto, lead)].append(c)
    general = {str(lead): _fit_group(cs) for lead, cs in sorted(by_lead.items())}
    puntos: dict[str, dict] = {}
    for (punto, lead), cs in sorted(by_point.items()):
        if sum(1 for c in cs if _wet(c)) >= MIN_POINT_CASES:
            puntos.setdefault(punto, {})[str(lead)] = _fit_group(cs)
    return {"general": general, "puntos": puntos}


def weights_for(model_fit: dict, lead: int, point: str | None = None) -> dict:
    lead_key = str(lead)
    by_point = (model_fit.get("puntos") or {}).get(point) or {}
    if point and lead_key in by_point:
        return by_point[lead_key]
    return (model_fit.get("general") or {}).get(lead_key) or {}


def weighted_median(vals: dict, w: dict) -> float:
    total = sum(w[m] for m in vals)
    acc = 0.0
    for m, v in sorted(vals.items(), key=lambda kv: kv[1]):
        acc += w[m]
        if acc >= total / 2:
            return v
    return max(vals.values())


def combine(forecasts: dict, weights: dict) -> dict | None:
    """Lluvia de la mediana ponderada para {modelo: mm}. Modelos sin peso aprendido entran con el peso promedio."""
    vals = {m: float(v) for m, v in forecasts.items() if v is not None}
    if not vals:
        return None
    known = [weights[m]["peso"] for m in vals if m in weights]
    default = sum(known) / len(known) if known else 1.0
    w = {m: (weights[m]["peso"] if m in weights else default) for m in vals}
    den = sum(w.values())
    value = weighted_median(vals, w)
    share = {str(t): round(100 * sum(w[m] for m in vals if vals[m] >= t) / den, 1) for t in (10, 30, 60)}
    top = sorted(vals, key=lambda m: -w[m])[:3]
    return {"lluvia_mm": round(value, 1), "peso_modelos_mm": share,
            "modelos_principales": [{"modelo": m, "peso": round(w[m] / den, 2)} for m in top], "modelos": len(vals)}


def validate(rows: list[dict]) -> dict:
    """Ajusta con el 70 % más antiguo y mide el error en el 30 % más reciente."""
    cases = _cases(rows)
    days = sorted({k[1] for k in cases})
    if len(days) < 20:
        return {"evaluable": False, "motivo": f"Sólo {len(days)} días con observación: no alcanza para validar"}
    cut = days[int(len(days) * TRAIN_SHARE)]
    model_fit = fit([r for r in rows if r["fecha"] < cut])
    err: dict[str, list] = defaultdict(list)
    for (punto, fecha, lead), c in cases.items():
        if fecha < cut or len(c["f"]) < 2 or not _wet(c):
            continue
        res = combine(c["f"], weights_for(model_fit, lead, punto))
        err["ARGWX ponderado"].append(res["lluvia_mm"] - c["obs"])
        err["Mediana de modelos"].append(median(c["f"].values()) - c["obs"])
        for m, f in c["f"].items():
            err[m].append(f - c["obs"])
    table = {name: {"n": len(es), "mae_mm": round(sum(abs(e) for e in es) / len(es), 2),
                    "rmse_mm": round(sqrt(sum(e * e for e in es) / len(es)), 2),
                    "sesgo_mm": round(sum(es) / len(es), 2)}
             for name, es in err.items() if es}
    ranking = sorted(table, key=lambda k: table[k]["rmse_mm"])
    w, med = table.get("ARGWX ponderado"), table.get("Mediana de modelos")
    mejora = round(100 * (med["rmse_mm"] - w["rmse_mm"]) / med["rmse_mm"], 1) if w and med and med["rmse_mm"] else None
    return {"evaluable": True, "entrenamiento": [days[0], cut], "prueba": [cut, days[-1]],
            "dias_prueba": sum(1 for d in days if d >= cut), "errores": table, "ranking": ranking,
            "mejora_vs_mediana_pct": mejora,
            "nota": "Días con lluvia observada o pronosticada (>= 1 mm). Verdad: ERA5, que suaviza tormentas locales."}


def build_model_file(rows: list[dict], points_info: dict | None = None) -> dict:
    days = sorted({r["fecha"] for r in rows})
    return {"version": 1, "periodo": [days[0], days[-1]] if days else None, "dias": len(days),
            "metodo": "Mediana ponderada: pesos por error cuadrático de cada modelo en días con lluvia, "
                      "contraídos hacia pesos iguales con pocos casos; por punto de referencia cuando hay datos.",
            "estado": "En evaluación: se muestra en paralelo y no define el nivel de alerta.",
            "ajuste": fit(rows), "validacion": validate(rows), "puntos_info": points_info or {}}
