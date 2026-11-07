"""Inventario real y fallas que antes ocultaban cursos o daban una falsa señal verde."""
import copy
import json
from collections import Counter

import httpx
import pytest

from app.providers import hydro, hydrography as h


@pytest.fixture(scope="module")
def catalog():
    return h.build_catalog()


def test_all_dph_records_and_requested_names_are_present(catalog):
    sources = Counter(s for c in catalog["cursos"] for s in c["fuentes"])
    assert sources["dph"] == 79 + 774 + 418
    assert sources["gcba"] == 18
    assert catalog["cobertura"]["cuencas"] == 84
    assert len({c["id"] for c in catalog["cursos"]}) == len(catalog["cursos"])
    names = "|".join(h.canonical(" ".join([c["nombre"], *c["alias"]])) for c in catalog["cursos"])
    for name in ("de la plata", "salado del sur", "parana de las palmas", "parana guazu", "parana mini",
                 "lujan", "matanza", "reconquista", "colorado", "arrecifes", "areco", "quequen grande",
                 "quequen salado", "sauce grande", "sauce chico", "pergamino", "del medio", "ramallo",
                 "maldonado", "vega", "medrano", "cildanez", "perdriel"):
        assert name in names, name
    assert any(c.get("sin_nombre") for c in catalog["cursos"])
    assert any(0 < (c["km"] or 0) < 1 for c in catalog["cursos"])
    assert sum(len(c["muestras"]) for c in catalog["cursos"]) <= hydro.MAX_SAMPLES
    assert all(not c["muestras"] for c in catalog["cursos"] if c["tipo"] in ("estuario", "arroyo", "canal"))


def test_maldonado_homonyms_and_caba_are_not_assigned_to_la_plata(catalog):
    maldonado = [c for c in catalog["cursos"] if h.canonical(c["nombre"]) == "maldonado"]
    assert any("la-plata" in c["partidos"] for c in maldonado)
    assert any(c.get("solo_caba") and c["partidos"] == [] for c in maldonado)
    assert all(not c["partidos"] for c in catalog["cursos"] if c.get("solo_caba"))
    assert all("Ã" not in c["nombre"] for c in catalog["cursos"])


def test_estuary_urban_and_no_data_are_not_false_green_or_rain_alerts(catalog):
    c = copy.deepcopy(next(c for c in catalog["cursos"] if c["tipo"] == "estuario"))
    c["partidos"] = ["la-plata"]
    urban = copy.deepcopy(next(c for c in catalog["cursos"] if c.get("monitoreo") == "urbano"))
    urban["partidos"] = ["la-plata"]
    res = hydro.compute_floods({"cursos": [c, urban]}, None, None, {"la-plata": 300}, None, {})
    assert all(x["nivel"] is None and x["lluvia_72h"] is None and x["partidos_afectados"] == [] for x in res["cursos"])
    assert res["resumen"]["sin_evaluacion"] == 2
    assert res["resumen"]["en_alerta"] == 0 and res["resumen"]["por_nivel"]["GREEN"] == 0


def test_kml_extended_data_short_unnamed_and_holes():
    data = b'''<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
      <Folder><name>Rios</name><Placemark><ExtendedData><Data name="refname"><value>Rio Prueba</value></Data>
      <Data name="id"><value>42</value></Data></ExtendedData><LineString><coordinates>-60,-35 -60.0001,-35</coordinates></LineString></Placemark></Folder>
      <Folder><name>Arroyos</name><Placemark><LineString><coordinates>-60,-35 -60.0002,-35</coordinates></LineString></Placemark></Folder>
      <Folder><name>CUENCAS</name><Placemark><name>Cuenca prueba</name><Polygon><outerBoundaryIs><LinearRing>
      <coordinates>-61,-36 -59,-36 -59,-34 -61,-34 -61,-36</coordinates></LinearRing></outerBoundaryIs>
      <innerBoundaryIs><LinearRing><coordinates>-60.1,-35.1 -59.9,-35.1 -59.9,-34.9 -60.1,-34.9 -60.1,-35.1</coordinates></LinearRing></innerBoundaryIs>
      </Polygon></Placemark></Folder></Document></kml>'''
    parsed = h.parse_dph(data)
    assert parsed["cursos"][0]["nombre"] == "Rio Prueba"
    assert parsed["cursos"][1]["sin_nombre"]
    g = h.shape(parsed["cuencas"]["features"][0]["geometry"])
    assert not g.covers(h.shape({"type": "Point", "coordinates": [-60, -35]}))


def test_municipality_crossing_without_vertices_is_detected():
    snapshot = {"cursos": [{"id": "test", "nombre": "Arroyo prueba", "tipo": "arroyo", "fuentes": ["dph"],
        "trazo": [[[-35, -61], [-35, -59]]]}], "cuencas": {"features": []}, "capas": {}, "fuentes": [], "fecha_descarga": "2026-11-05"}
    geo = {"features": [{"properties": {"id": "cruzado"}, "geometry": {"type": "Polygon", "coordinates": [
        [[-60.1, -35.1], [-59.9, -35.1], [-59.9, -34.9], [-60.1, -34.9], [-60.1, -35.1]]]}}]}
    result = h.build_catalog(osm={"cursos": []}, geojson=geo, snapshot=snapshot)
    assert result["cursos"][0]["partidos"] == ["cruzado"]


def test_osm_extensions_are_not_lost_at_a_shared_endpoint():
    snapshot = {"cursos": [{"id": "dph", "nombre": "Arroyo prueba", "tipo": "arroyo", "fuentes": ["dph"],
        "registros": ["dph"], "trazo": [[[-35, -61], [-35, -60]]]}], "cuencas": {"features": []},
        "capas": {}, "fuentes": [], "fecha_descarga": "2026-11-05"}
    osm = {"cursos": [{"id": "prueba", "nombre": "Arroyo prueba", "tipo": "arroyo", "trazo": [[[-35, -60], [-35, -59]]]}]}
    result = h.build_catalog(osm=osm, geojson={"features": []}, snapshot=snapshot)
    assert len(result["cursos"]) == 2
    assert any(c["bbox"][3] == -59 for c in result["cursos"])


def test_official_refresh_falls_back_with_original_date():
    def fail(request):
        return httpx.Response(503)
    with httpx.Client(transport=httpx.MockTransport(fail)) as client:
        result = h.export_network(client, json.loads((h.DATA / "municipios_pba.geojson").read_text(encoding="utf-8")), [])
    original = json.loads((h.DATA / "hidrografia_oficial.json").read_text(encoding="utf-8"))
    assert result["advertencias"] and result["cobertura"]["fecha_descarga"] == original["fecha_descarga"]
    assert len(result["cuencas_geojson"]["features"]) == 84
