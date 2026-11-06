"""Climatología y calibración de probabilidades (datos sintéticos)."""
from datetime import date, timedelta

from app.engine import calibration as cal


def _series(values_by_day):
    start = date(2001, 1, 1)
    return {"time": [(start + timedelta(days=i)).isoformat() for i in range(len(values_by_day))], "rain": values_by_day}


def test_climatology_counts_daily_and_3day_totals():
    # Enero de 2001: 31 días; 3 días seguidos de 15 mm (45 mm en 72 h) y el resto seco
    vals = [0.0] * 31
    vals[10:13] = [15.0, 15.0, 15.0]
    res = cal.climatology({"lujan": _series(vals)}, 2001, 2001)
    jan = res["puntos"]["lujan"]["1"]
    assert jan["dias"] == 31
    assert jan["p24"]["10"] == round(100 * 3 / 31, 2) and jan["p24"]["20"] == 0
    assert jan["p72"]["40"] == round(100 * 1 / 29, 2)   # 29 ventanas de 3 días dentro de enero
    assert res["periodo"] == "2001-2001"


def test_rarity_labels():
    pct = {"p50": 0.0, "p90": 10.0, "p95": 20.0, "p99": 50.0, "max": 120.0}
    assert cal.rarity(5, pct) == "dentro de lo habitual"
    assert cal.rarity(25, pct) == "en el 5 % más alto"
    assert cal.rarity(60, pct) == "en el 1 % más alto"
    assert cal.rarity(130, pct) == "por encima del máximo histórico del mes"
    assert cal.rarity(None, pct) is None and cal.rarity(5, {}) is None


def test_contingency_scores():
    pairs = [(35, 40), (32, 5), (0, 31), (0, 0), (40, 45)]
    c = cal.contingency(pairs, 30)
    assert (c["aciertos"], c["falsas_alarmas"], c["no_previstos"], c["correctos_sin_evento"]) == (2, 1, 1, 1)
    assert c["pod"] == 0.67 and c["far"] == 0.33 and c["sesgo"] == 1.0


def _rows(n_cases, models_hit, observed):
    rows = []
    for i in range(n_cases):
        for m in range(4):
            rows.append({"punto": "p", "fecha": f"2025-01-{i + 1:02d}", "modelo": f"m{m}", "plazo": 1,
                         "pronostico": 35.0 if m < models_hit else 0.0, "observado": observed(i)})
    return rows


def test_calibration_and_lookup():
    # 12 casos con 3 de 4 modelos >= 30 mm: ocurrió en 9 (75 %)
    rows = _rows(12, 3, lambda i: 40.0 if i < 9 else 0.0)
    # 12 casos con ningún modelo >= 30 mm: ocurrió en 1
    rows += [dict(r, fecha="2025-02" + r["fecha"][7:]) for r in _rows(12, 0, lambda i: 40.0 if i == 0 else 0.0)]
    calib = cal.calibration(rows)
    bins = calib["tabla"]["30"]["1"]
    high = bins[3]  # 0,51-0,75 (3 de 4)
    assert high["casos"] == 12 and high["ocurrio"] == 9 and high["frecuencia"] == 75.0 and high["confiable"]
    assert bins[0]["casos"] == 12 and bins[0]["frecuencia"] == round(100 / 12, 1)
    p = cal.calibrated_probability(calib, 30, 1, 3, 4)
    assert p == {"probabilidad": 75.0, "casos": 12, "confiable": True}
    assert cal.calibrated_probability(calib, 30, 2, 3, 4) is None   # sin datos para ese plazo
    assert cal.calibrated_probability(None, 30, 1, 3, 4) is None


def test_verification_by_model_and_lead():
    rows = [{"modelo": "gfs", "plazo": 1, "pronostico": 10.0, "observado": 12.0},
            {"modelo": "gfs", "plazo": 1, "pronostico": 0.0, "observado": 0.0},
            {"modelo": "gfs", "plazo": 2, "pronostico": 30.0, "observado": None}]
    v = cal.verification(rows)
    assert v["gfs"]["1"]["n"] == 2 and v["gfs"]["1"]["mae"] == 1.0 and v["gfs"]["1"]["sesgo_mm"] == -1.0
    assert "2" not in v["gfs"]
