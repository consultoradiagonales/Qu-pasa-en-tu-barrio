from datetime import datetime, timedelta

import pytest

from app.engine.consensus import confidence_label, consensus
from app.engine.eta import arrival_times
from app.engine.geo import point_in_polygon
from app.engine.thresholds import evaluate, level_for
from app.engine.verification import metrics


@pytest.mark.parametrize("var,value,expected", [
    ("rain_mm", 29.9, "GREEN"), ("rain_mm", 30, "YELLOW"), ("rain_mm", 60, "ORANGE"), ("rain_mm", 100, "RED"),
    ("rain_mm", 150, "PURPLE"), ("gust_kmh", 85, "ORANGE"), ("tmax_c", 36.5, "YELLOW"), ("tmax_c", None, "GREEN"),
    ("weather_code", 95, "YELLOW"), ("weather_code", 99, "RED"), ("weather_code", 61, "GREEN"),
])
def test_thresholds(var, value, expected):
    assert level_for(var, value) == expected


def test_evaluate_picks_main_hazard():
    level, hazard, _ = evaluate({"rain_mm": 65, "gust_kmh": 62, "tmax_c": 25})
    assert (level, hazard) == ("ORANGE", "lluvia")


def test_consensus_example_from_spec():
    # ECMWF, GFS e ICON: lluvia; GEM: seco -> 3/4 = 75 % -> confianza Alta
    rainy, dry = {"rain_mm": 40}, {"rain_mm": 0}
    r = consensus({"ECMWF": rainy, "GFS": rainy, "ICON": rainy, "GEM": dry})
    assert r["level"] == "YELLOW" and r["consensus"] == 0.75 and r["confidence_label"] == "Alta"
    assert sorted(r["agreeing_models"]) == ["ECMWF", "GFS", "ICON"]


def test_single_model_never_raises_alert():
    r = consensus({"GFS": {"rain_mm": 200}})
    assert r["level"] == "GREEN"
    assert r["unconfirmed_signal"]["level"] == "PURPLE"
    assert "único modelo" in r["note"]


def test_minority_signal_is_not_confirmed():
    red, green = {"rain_mm": 120}, {"rain_mm": 2}
    r = consensus({"A": red, "B": red, "C": green, "D": green, "E": green})
    assert r["level"] == "GREEN" and r["consensus"] == 0.6
    assert r["unconfirmed_signal"]["models"] == ["A", "B"]


@pytest.mark.parametrize("fraction,label", [(0.4, "Baja"), (0.41, "Media"), (0.7, "Media"), (0.71, "Alta"),
                                            (0.85, "Alta"), (0.86, "Muy alta"), (1.0, "Muy alta")])
def test_confidence_classes(fraction, label):
    assert confidence_label(fraction) == label


def test_eta_on_track_and_off_track():
    t0 = datetime(2026, 11, 4, 18)
    p1 = {"lat": -36.0, "lon": -61.0, "time": t0}
    p2 = {"lat": -36.0, "lon": -60.4, "time": t0 + timedelta(hours=1)}  # ~54 km/h hacia el este
    targets = [{"id": "adelante", "name": "Adelante", "lat": -36.0, "lon": -59.8},
               {"id": "atras", "name": "Atrás", "lat": -36.0, "lon": -61.5},
               {"id": "lejos", "name": "Fuera del corredor", "lat": -37.5, "lon": -59.8}]
    res = arrival_times(p1, p2, targets, corridor_km=25, max_hours=6)
    assert 50 < res["motion"]["speed_kmh"] < 56 and 85 < res["motion"]["bearing_deg"] < 95
    assert [t["id"] for t in res["targets"]] == ["adelante"]
    assert res["targets"][0]["eta_hours"] == pytest.approx(1.0, abs=0.05)


def test_eta_rejects_bad_times():
    t0 = datetime(2026, 11, 4, 18)
    with pytest.raises(ValueError):
        arrival_times({"lat": -36, "lon": -61, "time": t0}, {"lat": -36, "lon": -60, "time": t0}, [])


def test_verification_metrics():
    m = metrics([(10, 8), (20, 25), (None, 3)])
    assert m == {"n": 2, "mae": 3.5, "rmse": 3.81, "bias": -1.5}


def test_point_in_polygon():
    square = [(-35, -59), (-35, -58), (-36, -58), (-36, -59)]
    assert point_in_polygon(-35.5, -58.5, square)
    assert not point_in_polygon(-34.5, -58.5, square)
