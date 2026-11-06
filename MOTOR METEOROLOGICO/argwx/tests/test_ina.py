"""Alturas observadas del INA (escalas de Prefectura / Red Hidrológica Nacional), sin red."""
from datetime import timedelta

from app.providers import ina
from app.services.municipalities import load_municipalities
from app.util import utcnow


def test_parse_obs_and_status():
    assert ina.parse_obs({"rows": [{"timestart": "2026-11-03T12:00:00.000Z", "valor": "3.1"},
                                   {"timestart": "2026-11-02T12:00:00.000Z", "valor": 2.9}]}) == [
        ("2026-11-02T12:00:00.000Z", 2.9), ("2026-11-03T12:00:00.000Z", 3.1)]
    assert ina.parse_obs([["2026-11-03T12:00:00Z", "2026-11-03T12:00:00Z", 4.0], ["x", "y", "nan?"]]) == [
        ("2026-11-03T12:00:00Z", 4.0)]
    assert ina.status(3.4, 3.3, 3.9, 0.21) == ("ORANGE", "Alerta")
    assert ina.status(4.0, 3.3, 3.9, 0.21) == ("RED", "Evacuación")
    assert ina.status(0.1, 3.3, 3.9, 0.21) == ("GREEN", "Aguas bajas")
    assert ina.status(1.0, None, None, None) == ("GREEN", "Normal")


def _station(i, name, prov, lat, lon, rio="PARANADELASPALMAS"):
    return {"id": i, "nombre": name, "provincia": prov, "geom": {"type": "Point", "coordinates": [lon, lat]},
            "rio": rio, "has_obs": True, "public": True, "nivel_alerta": 3.0, "nivel_evacuacion": 3.5,
            "nivel_aguas_bajas": 0.3, "red": {"nombre": "escalas Prefectura Nacional"}, "tabla": "alturas_prefe"}


def test_selects_only_province_gauges_with_data():
    stations = [_station(1, "Zárate", "BUENOSAIRES", -34.09, -59.02), _station(2, "Paraná", "ENTRERIOS", -31.72, -60.52),
                _station(3, "Ibicuy", "ENTRERIOS", -33.74, -59.16)]
    stations.append({**_station(4, "Sin datos", "BUENOSAIRES", -34.5, -58.5), "has_obs": False})
    series = [{"id": 10 + s["id"], "estacion": {"id": s["id"]}} for s in stations]
    chosen = ina.pba_series(stations, series)
    assert [c["estacion"] for c in chosen] == ["Zárate"] and chosen[0]["serie"] == 11 and chosen[0]["alerta"] == 3.0


class FakeClient:
    def __init__(self):
        self.now = utcnow()

    def get(self, url, params=None, timeout=None):
        class R:
            def __init__(self, payload):
                self.payload = payload

            def raise_for_status(self):
                pass

            def json(self):
                return self.payload
        if url.endswith("obs/puntual/estaciones"):
            return R([_station(1, "Zárate", "BUENOSAIRES", -34.09, -59.02)])
        if url.endswith("obs/puntual/series"):
            return R({"rows": [{"id": 11, "estacion": {"id": 1}}]})
        t1 = (self.now - timedelta(hours=30)).strftime("%Y-%m-%dT%H:%M:%S")
        t2 = (self.now - timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S")
        return R([{"timestart": t1, "valor": 2.6}, {"timestart": t2, "valor": 3.2}])


def test_export_observed_end_to_end():
    res = ina.export_observed(FakeClient(), load_municipalities())
    st = res["estaciones"][0]
    assert st["estacion"] == "Zárate" and st["altura_m"] == 3.2 and st["estado"] == "Alerta" and st["nivel"] == "ORANGE"
    assert st["cambio_24h"] == 0.6 and len(st["serie_30d"]) == 2
