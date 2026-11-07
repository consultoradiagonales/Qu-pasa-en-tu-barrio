from app.engine import blindspots

MODELS = ["GFS", "ICON", "ECMWF", "GEM", "UKMO"]
STEPS = ("observados", "ausentes", "filtro", "distorsion", "falta", "riesgo", "riesgo_motivo", "conclusion")


def entry(models=MODELS, level="GREEN", rain=(2.0, 0.5, 6.0), obs=None, signal=None, agreeing=None):
    return {
        "id": "la-plata", "alert_level": level, "hazard": None if level == "GREEN" else "lluvia",
        "models": {m: {"rain_mm": rain[0]} for m in models},
        "values": {"rain_mm": {"median": rain[0], "min": rain[1], "max": rain[2]}},
        "argwx": {"agreeing_models": agreeing if agreeing is not None else list(models), "unconfirmed_signal": signal},
        "observation": obs, "smn": [],
    }


def test_all_seven_steps_present():
    res = blindspots.analyze(entry(), MODELS)
    for k in STEPS:
        assert res[k]
    assert res["riesgo"] in ("Bajo", "Medio", "Alto")


def test_station_and_agreement_give_low_risk():
    res = blindspots.analyze(entry(obs={"source": "SMN La Plata"}), MODELS)
    assert res["riesgo"] == "Bajo"
    assert res["supuesto"] is None


def test_no_station_is_declared_as_assumption():
    res = blindspots.analyze(entry(), MODELS)
    assert res["riesgo"] == "Medio"
    assert res["supuesto"].startswith("Supuesto:")
    assert "estación" in res["ausentes"]


def test_median_hiding_heavy_rain_raises_risk_and_conclusion():
    signal = {"level": "YELLOW", "models": ["GFS"]}
    res = blindspots.analyze(entry(rain=(8.0, 1.0, 45.0), signal=signal, agreeing=MODELS[1:]), MODELS)
    assert res["riesgo"] == "Alto"
    assert "esconde" in res["distorsion"]
    assert "no se puede descartar amarilla" in res["conclusion"]


def test_few_models_named_as_absent():
    res = blindspots.analyze(entry(models=["GFS", "ICON"]), MODELS)
    assert "ECMWF" in res["ausentes"]
    assert res["riesgo"] == "Alto"


def test_weighted_disagreement_is_flagged():
    res = blindspots.analyze(entry(obs={"source": "SMN"}), MODELS, {"difiere": True, "nivel": "YELLOW"})
    assert res["banderas"]["ponderado_difiere"]
    assert res["riesgo"] == "Medio"
    assert "ponderado" in res["distorsion"]


def test_no_models_is_high_risk_without_numbers():
    res = blindspots.analyze(entry(models=[]), MODELS)
    assert res["riesgo"] == "Alto"
    assert "No hay base" in res["conclusion"]
