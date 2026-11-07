"""Puntos ciegos del pronóstico por partido (skill "sesgo del superviviente", v4).

Para cada partido y ventana arma el análisis en 7 pasos: casos observados,
casos ausentes probables, filtro que explica la ausencia, cómo distorsiona la
conclusión, qué dato falta, riesgo analítico (Bajo / Medio / Alto) y la
conclusión reformulada, con el supuesto en una línea aparte.

Reglas: sólo usa cifras que salen del propio pronóstico; si algo no se puede
estimar lo dice ("No hay datos para estimarlo") en vez de suponerlo.
"""
from app.engine.levels import LABEL, idx
from app.engine.thresholds import THRESHOLDS

NO_DATA = "No hay datos para estimarlo."
# Diferencia entre el modelo más lluvioso y el más seco a partir de la cual la
# mediana deja de describir bien lo que dicen los modelos.
RAIN_SPREAD_MM = 20


def _plural(n: int, one: str, many: str) -> str:
    return f"{n} {one if n == 1 else many}"


def analyze(entry: dict, all_models: list[str], weighted: dict | None = None) -> dict:
    """Análisis de evidencia ausente para un partido en una ventana del motor."""
    models = entry.get("models") or {}
    n, total = len(models), len(all_models)
    missing_models = [m for m in all_models if m not in models]
    argwx = entry.get("argwx") or {}
    agreeing = len(argwx.get("agreeing_models") or [])
    rain = (entry.get("values") or {}).get("rain_mm") or {}
    obs = entry.get("observation")
    smn = entry.get("smn") or []
    signal = argwx.get("unconfirmed_signal")
    level = entry.get("alert_level", "GREEN")

    if n == 0:
        return {
            "observados": "Ningún modelo devolvió datos para este partido en esta ventana.",
            "ausentes": "Todos los modelos." + (" Hay alerta oficial del SMN." if smn else ""),
            "filtro": "No lo sé: puede ser un corte del proveedor o un límite de consultas.",
            "distorsion": "Un partido sin datos puede verse en verde cuando en realidad no se analizó.",
            "falta": "Volver a consultar los modelos y revisar las alertas oficiales del SMN.",
            "riesgo": "Alto",
            "riesgo_motivo": "Sin pronóstico, cualquier nivel es un supuesto.",
            "supuesto": None,
            "conclusion": "No hay base para afirmar el nivel de riesgo de este partido: sólo cuentan las alertas del SMN.",
            "banderas": {"modelos": 0, "modelos_total": total, "sin_estacion": obs is None},
        }

    spread = None
    if rain.get("max") is not None and rain.get("min") is not None:
        spread = round(rain["max"] - rain["min"], 1)
    hides_rain = (rain.get("max") is not None and rain.get("median") is not None
                  and rain["max"] >= THRESHOLDS["rain_mm"]["YELLOW"] > rain["median"])
    differs = bool(weighted and weighted.get("difiere"))

    # 1. Qué observamos
    observed = [f"{_plural(n, 'modelo', 'modelos')} de {total} con dato; coinciden {agreeing} en {LABEL[level].lower()}."]
    if rain.get("median") is not None:
        observed.append(f"Lluvia: mediana {rain['median']} mm (entre {rain['min']} y {rain['max']} mm).")
    if obs is not None:
        observed.append(f"Hay observación de {obs.get('source') or 'estación'}.")
    if smn:
        observed.append(f"{_plural(len(smn), 'alerta oficial', 'alertas oficiales')} del SMN.")

    # 2. Qué no observamos
    absent = []
    if missing_models:
        absent.append(f"Sin dato de {', '.join(missing_models)}.")
    if obs is None:
        absent.append("Ninguna estación con dato reciente en el partido: el pronóstico no se contrasta con lo medido.")
    absent.append("Fenómenos más chicos que la grilla de los modelos (tormentas puntuales, granizo, anegamientos de barrio).")

    # 3. Por qué no lo observamos
    filt = ["Los modelos globales promedian celdas de decenas de kilómetros."]
    if weighted:
        filt.append("El modelo ponderado se verifica en un punto de referencia por sección electoral, "
                    "contra un reanálisis (ERA5) y sólo para la lluvia.")
    if missing_models:
        filt.append("Algún proveedor no respondió en esta corrida.")

    # 4. Cómo distorsiona
    dist = ["Que los modelos coincidan no es una probabilidad: comparten datos de partida y pueden fallar juntos."]
    if hides_rain:
        dist.append(f"La mediana queda debajo de {THRESHOLDS['rain_mm']['YELLOW']} mm pero un modelo la supera: "
                    "el promedio esconde el escenario más lluvioso.")
    elif spread is not None and spread >= RAIN_SPREAD_MM:
        dist.append(f"Los modelos difieren {spread} mm entre sí: la mediana describe mal la incertidumbre.")
    if signal:
        dist.append(f"Hay señal {LABEL[signal['level']].lower()} de {', '.join(signal['models'])} que no alcanza el consenso.")
    if differs:
        dist.append(f"El modelo ponderado da {LABEL[weighted['nivel']].lower()}: no coincide con el consenso.")

    # 5. Qué falta
    falta = []
    if obs is None:
        falta.append("Un pluviómetro o estación dentro del partido.")
    falta.append("Reportes de vecinos (anegamientos, árboles caídos) para contrastar con lo pronosticado.")
    if weighted:
        falta.append("Verificación del viento y la temperatura, no sólo de la lluvia.")

    # 6. Riesgo analítico
    points = 0
    reasons = []
    if n < 3 or (total and n / total < 0.5):
        points += 2
        reasons.append(f"sólo {_plural(n, 'modelo', 'modelos')} con dato")
    if obs is None:
        points += 1
    if hides_rain or (spread is not None and spread >= RAIN_SPREAD_MM):
        points += 1
        reasons.append("los modelos difieren mucho en la lluvia")
    if signal:
        points += 1
        reasons.append("hay una señal no confirmada")
    if differs:
        points += 1
        reasons.append("el modelo ponderado no coincide")
    risk = "Alto" if points >= 3 else "Medio" if points >= 1 else "Bajo"
    if reasons:
        reason = "Pesa que " + ", ".join(reasons) + "."
    elif obs is None:
        reason = "Los modelos coinciden, pero no hay medición en el partido para confirmarlo."
    else:
        reason = "Los modelos coinciden y hay medición en el partido."

    # 7. Conclusión reformulada (el supuesto va aparte)
    supuesto = None if obs is not None else "Supuesto: no hay medición en el partido; se confía sólo en modelos."
    worst = max([level] + ([signal["level"]] if signal else []) + ([weighted["nivel"]] if differs else []), key=idx)
    if worst != level:
        conclusion = (f"El motor indica {LABEL[level].lower()}, pero no se puede descartar {LABEL[worst].lower()}: "
                      "conviene vigilar el partido antes de dar el riesgo por bajo.")
    elif level == "GREEN":
        conclusion = ("Los modelos no muestran fenómenos significativos; eso no excluye tormentas locales "
                      "que la grilla no resuelve.")
    else:
        conclusion = (f"Los modelos sostienen {LABEL[level].lower()}"
                      f"{' por ' + entry['hazard'] if entry.get('hazard') else ''}; "
                      "la intensidad local puede ser mayor o menor que la mediana.")

    return {
        "observados": " ".join(observed),
        "ausentes": " ".join(absent),
        "filtro": " ".join(filt),
        "distorsion": " ".join(dist),
        "falta": " ".join(falta) if falta else NO_DATA,
        "riesgo": risk,
        "riesgo_motivo": reason,
        "supuesto": supuesto,
        "conclusion": conclusion,
        "banderas": {"modelos": n, "modelos_total": total, "sin_estacion": obs is None,
                     "dispersion_lluvia_mm": spread, "senal_no_confirmada": bool(signal),
                     "ponderado_difiere": differs},
    }
