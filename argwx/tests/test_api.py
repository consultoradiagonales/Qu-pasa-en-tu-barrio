from app.services.municipalities import load_municipalities


def test_health(client):
    assert client.get("/health/live").json() == {"status": "ok"}
    assert client.get("/health/ready").json()["municipalities"] == 135
    assert client.get("/health").status_code == 200
    fr = client.get("/health/data-freshness").json()["providers"]
    assert fr["models"]["status"] == "fresh"


def test_135_municipalities_and_sections(client):
    data = client.get("/api/v1/municipios").json()
    assert data["total"] == 135
    counts = {}
    for m in data["municipios"]:
        counts[m["seccion"]] = counts.get(m["seccion"], 0) + 1
    assert counts == {1: 24, 2: 15, 3: 19, 4: 19, 5: 27, 6: 22, 7: 8, 8: 1}
    assert len({m["id"] for m in load_municipalities()}) == 135
    assert len(client.get("/api/v1/municipios/geojson").json()["features"]) == 135


def test_alerts_current(client):
    data = client.get("/api/v1/alerts/current").json()
    assert data["data_mode"] == "demo" and data["total"] == 135
    assert sum(data["summary"].values()) == 135
    assert set(data["models"]) == {"GFS", "ICON", "ECMWF", "GEM", "UKMO"}
    only = client.get("/api/v1/alerts/current?nivel_min=naranja&seccion=6").json()
    assert all(m["seccion"] == 6 and m["alert_level"] in ("ORANGE", "RED", "PURPLE") for m in only["municipalities"])
    assert client.get("/api/v1/alerts/current?ventana=12").status_code == 422


def test_province_summary_matches_mvp_contract(client):
    data = client.get("/api/v1/province/summary").json()
    for key in ("province", "enso_phase", "rain_mm", "alert_level", "forecast_source", "confidence"):
        assert key in data
    assert data["province"] == "Buenos Aires" and data["forecast_source"] == "GFS"


def test_observation_prevails_over_models(client):
    r = client.post("/api/v1/observations", json={"municipio": "Bahía Blanca", "rain_mm_24h": 160})
    assert r.status_code == 200
    alert = r.json()["alerta_resultante"]
    assert alert["alert_level"] == "PURPLE" and "observación" in alert["basis"]


def test_other_endpoints(client):
    assert len(client.get("/api/v1/zonas").json()["zonas"]) == 8
    assert client.get("/api/v1/enso/current").json()["phase"] in ("EL_NINO", "NEUTRAL", "LA_NINA")
    assert client.get("/api/v1/municipios/la-plata").json()["municipio"]["name"] == "La Plata"
    assert client.get("/api/v1/municipios/inexistente").status_code == 404
    assert client.get("/api/v1/forecast/rain?model=GFS").json()["forecast_source"] == "GFS"
    assert client.get("/api/v1/consensus/current?municipio=tandil").json()["municipios"][0]["id"] == "tandil"
    assert client.get("/api/v1/alerts/smn").json()["total"] >= 1
    assert client.get("/api/v1/sources").status_code == 200
    assert client.get("/").status_code == 200
    body = {"p1": {"lat": -36.9, "lon": -60.3, "time": "2026-11-04T18:00:00Z"},
            "p2": {"lat": -36.6, "lon": -59.9, "time": "2026-11-04T19:00:00Z"}, "corridor_km": 30}
    eta = client.post("/api/v1/radar/arrival-time", json=body).json()
    assert eta["motion"]["speed_kmh"] > 0 and isinstance(eta["targets"], list)
