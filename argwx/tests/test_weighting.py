"""Modelo ponderado ARGWX: pesos por desempeño, mediana ponderada y validación."""
from datetime import date, timedelta

from app.engine import weighting
from app.export_site import weighted_view


def _rows(days=60, points=("la-plata",)):
    """Historia sintética: BUENO acierta, MALO exagera 3x, MEDIO erra por poco."""
    rows = []
    start = date(2026, 1, 1)
    for d in range(days):
        fecha = (start + timedelta(days=d)).isoformat()
        obs = float((d * 7) % 25) if d % 3 else 0.0
        for punto in points:
            for lead in (1, 2):
                for modelo, f in (("BUENO", obs + 0.5), ("MEDIO", obs * 1.3 + 1), ("MALO", obs * 3 + 2)):
                    rows.append({"punto": punto, "fecha": fecha, "plazo": lead, "modelo": modelo,
                                 "pronostico": f, "observado": obs})
    return rows


def test_el_modelo_que_mas_acierta_pesa_mas():
    fit = weighting.fit(_rows())
    w = fit["general"]["1"]
    assert w["BUENO"]["peso"] > w["MEDIO"]["peso"] > w["MALO"]["peso"]
    assert abs(sum(v["peso"] for v in w.values()) - 1) < 0.01
    assert w["MALO"]["sesgo_relativo"] == 0.5  # exagera: observado/pronosticado acotado en 0,5
    assert "la-plata" in fit["puntos"]


def test_pocos_casos_contraen_hacia_pesos_iguales():
    few = weighting.fit(_rows(days=6))["general"]["1"]
    many = weighting.fit(_rows(days=90))["general"]["1"]
    assert few["BUENO"]["peso"] - few["MALO"]["peso"] < many["BUENO"]["peso"] - many["MALO"]["peso"]


def test_mediana_ponderada_y_modelo_desconocido():
    weights = {"A": {"peso": 0.7}, "B": {"peso": 0.2}, "C": {"peso": 0.1}}
    res = weighting.combine({"A": 10, "B": 40, "C": 80}, weights)
    assert res["lluvia_mm"] == 10
    assert res["modelos_principales"][0]["modelo"] == "A"
    assert res["peso_modelos_mm"]["30"] == 30.0
    # Un modelo sin historia entra con el peso promedio de los conocidos.
    res = weighting.combine({"A": 10, "NUEVO": 50}, weights)
    assert res["modelos"] == 2
    assert weighting.combine({"A": None}, weights) is None


def test_validacion_supera_a_la_mediana_cuando_hay_un_modelo_malo():
    val = weighting.validate(_rows(days=90))
    assert val["evaluable"]
    assert val["errores"]["ARGWX ponderado"]["rmse_mm"] <= val["errores"]["Mediana de modelos"]["rmse_mm"]
    assert val["ranking"][0] in ("ARGWX ponderado", "BUENO")
    assert weighting.validate(_rows(days=10))["evaluable"] is False


def test_vista_por_partido_no_cambia_el_nivel_publicado():
    model_file = weighting.build_model_file(_rows(days=90), {"la-plata": {"name": "La Plata", "seccion": 8}})
    entry = {"seccion": 8, "alert_level": "GREEN",
             "values": {"gust_kmh": {"median": 20}, "tmax_c": {"median": 25}, "tmin_c": {"median": 12}},
             "models": {"BUENO": {"rain_mm": 70}, "MEDIO": {"rain_mm": 75}, "MALO": {"rain_mm": 5}}}
    view = weighted_view(entry, 24, model_file, {8: "la-plata"})
    assert view["lluvia_mm"] >= 70
    assert view["nivel"] != "GREEN"
    assert view["difiere"] is True
    assert view["punto_referencia"] == "la-plata"
    assert entry["alert_level"] == "GREEN"
    assert weighted_view(entry, 24, None, {}) is None
