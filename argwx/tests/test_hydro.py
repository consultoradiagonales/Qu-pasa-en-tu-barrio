"""Crecidas: red hídrica de OpenStreetMap, caudales GloFAS, lluvia en la cuenca y suelo (datos sintéticos)."""
import json
from pathlib import Path

from app.providers import hydro
from app.services.municipalities import load_municipalities

GEO = json.loads((Path(hydro.__file__).parents[1] / "data" / "municipios_pba.geojson").read_text(encoding="utf-8"))


def _way(name, coords, waterway="river"):
    return {"type": "way", "tags": {"name": name, "waterway": waterway},
            "geometry": [{"lat": a, "lon": b} for a, b in coords]}


def _line(lat, lon0, lon1, n=30):
    return [(lat, lon0 + (lon1 - lon0) * i / (n - 1)) for i in range(n)]


def _elements():
    # Río que pasa por Junín y Chacabuco (dos tramos que se tocan) y un arroyo de 2 km (se descarta).
    return [
        _way("Río de Prueba", _line(-34.55, -61.20, -60.70)),
        _way("Río de Prueba", _line(-34.55, -60.70, -60.30)),
        _way("Arroyo Corto", _line(-35.06, -60.62, -60.60), "stream"),
        _way("Arroyo de Prueba", _line(-35.06, -60.90, -60.40), "river"),  # tipo por el nombre, no por la etiqueta
        {"type": "node", "lat": -34.552, "lon": -60.95, "tags": {"name": "Pueblo Ribereño", "place": "village"}},
        {"type": "node", "lat": -34.80, "lon": -60.95, "tags": {"name": "Pueblo Lejano", "place": "town"}},
        {"type": "node", "lat": -34.56, "lon": -60.40, "tags": {"name": "Ciudad Ribereña", "place": "city"}},
    ]


def test_kind_and_reference_names():
    assert hydro.kind_of("Arroyo Pergamino", {"river"}) == "arroyo"
    assert hydro.kind_of("Aº del Medio", {"river"}) == "arroyo"
    assert hydro.kind_of("Canal 15", {"canal"}) == "canal"
    assert hydro.kind_of("Río Salado", {"stream"}) == "río"
    assert hydro.kind_of("Las Flores", {"stream"}) == "arroyo"
    assert hydro.ref_key("Río Salado") == hydro.ref_key("Salado (cuenca alta)") == "salado"
    assert hydro.ref_key("Río Paraná de las Palmas") == "parana de las palmas"


def test_simplify_keeps_shape_and_endpoints():
    pts = _line(-34.5, -61.0, -60.0, 50) + [(-34.0, -60.0)]
    simple = hydro.simplify(pts)
    assert simple[0] == pts[0] and simple[-1] == pts[-1] and (-34.5, -60.0) in simple and len(simple) == 3


def test_build_network_groups_courses_partidos_and_places():
    net = hydro.build_network(_elements(), GEO, load_municipalities())
    assert net["version"] == hydro.VERSION
    by = {c["nombre"]: c for c in net["cursos"]}
    assert "Arroyo Corto" not in by  # menos de 8 km
    rio = by["Río de Prueba"]
    assert rio["tipo"] == "río" and rio["km"] > 80 and len(net["cursos"]) == 2
    assert "junin" in rio["partidos"] and "chacabuco" in rio["partidos"]
    nombres = [loc[0] for loc in rio["localidades"]]
    assert nombres[0] == "Ciudad Ribereña" and "Pueblo Ribereño" in nombres and "Pueblo Lejano" not in nombres
    assert 1 <= len(rio["muestras"]) <= 4 and all(m["partido"] for m in rio["muestras"])
    assert by["Arroyo de Prueba"]["tipo"] == "arroyo"
    assert rio["trazo"] and len(rio["trazo"][0][0]) == 2


def _series(base, future, days_past=hydro.PAST_DAYS):
    t = [f"2026-10-{d:02d}" for d in range(1, days_past + 1)] + [f"2026-11-{d:02d}" for d in range(1, len(future) + 1)]
    return {"time": t, "q": [base] * days_past + future, "med": [None] * days_past + future}


def test_point_status_levels():
    st = hydro.point_status(_series(10.0, [12, 20, 35, 50, 40, 30, 20, 15]), "2026-11-01")
    assert st["nivel"] == "ORANGE" and st["relacion"] == 5.0 and st["pico"] == "2026-11-04"
    assert hydro.point_status(_series(2.0, [3, 5, 6, 6, 5, 4, 3, 3]), "2026-11-01")["nivel"] == "GREEN"  # subida < 5 m³/s
    assert hydro.point_status(_series(0.3, [9, 9, 9, 9, 9, 9, 9, 9]), "2026-11-01") == {"representado": False,
                                                                                         "q_tipico": 0.3}
    assert hydro.point_status(None, "2026-11-01") is None


def test_rain_level_and_wet_soil():
    assert hydro.rain_level(None, None) == "GREEN"
    assert hydro.rain_level(45, 80) == "YELLOW"
    assert hydro.rain_level(45, 200) == "ORANGE"   # suelo cargado: sube un nivel
    assert hydro.rain_level(25, 200) == "YELLOW"
    assert hydro.rain_level(15, 200) == "GREEN"
    assert hydro.rain_level(150, 300) == "RED"     # nunca pasa de Roja
    assert hydro.soil_category(0.42) == "saturado" and hydro.soil_category(0.1) == "seco"
    assert hydro.soil_category(None) is None


def test_rain72_by_partido():
    win = lambda v: {"municipios": [{"id": "junin", "lluvia_mm": v}, {"id": "lobos", "lluvia_mm": None}]}  # noqa: E731
    alertas = {"windows": {"24": win(10), "48": win(25.5), "72": win(4)}}
    assert hydro.rain72_by_partido(alertas) == {"junin": 39.5}
    assert hydro.rain72_by_partido(None) == {}


def test_compute_floods_combines_criteria():
    net = hydro.build_network(_elements(), GEO, load_municipalities())
    rio = next(c for c in net["cursos"] if c["nombre"] == "Río de Prueba")
    s = rio["muestras"][0]
    caudales = {"hoy": "2026-11-01", "puntos": {
        f"{s['lat']},{s['lon']}": hydro.point_status(_series(10.0, [12, 20, 35, 50, 40, 30, 20, 15]), "2026-11-01")}}
    rain = {"junin": 80.0, "chacabuco": 20.0}
    soil = {"municipios": {"junin": {"lluvia_30d": 90}, "chacabuco": {"lluvia_30d": 60}}}
    names = {m["id"]: m["name"] for m in load_municipalities()}
    res = hydro.compute_floods(net, caudales, soil, rain, None, names)
    c = next(x for x in res["cursos"] if x["id"] == rio["id"])
    assert c["nivel_lluvia"] == "YELLOW" and c["nivel_caudal"] == "ORANGE" and c["nivel"] == "ORANGE"
    assert c["lluvia_72h"] == 50.0 and c["pico"] == "2026-11-04"
    assert s["partido"] in c["partidos_afectados"] and "junin" in c["partidos_afectados"]
    assert any("Caudal (GloFAS)" in m for m in c["motivos"]) and any("Máximo en Junín: 80 mm" in m for m in c["motivos"])
    assert res["cursos"][0]["id"] == rio["id"] and res["resumen"]["en_alerta"] == 1

    # Estación de referencia con caudal alto (historia 1984-hoy) aunque no llueva
    refs = {"rios": [{"rio": "de Prueba", "lugar": "Junín", "nivel_7d": "YELLOW", "estado_7d": "Alto",
                      "partidos": ["junin"]}]}
    res = hydro.compute_floods(net, None, None, {}, refs, names)
    c = next(x for x in res["cursos"] if x["id"] == rio["id"])
    assert c["nivel"] == "YELLOW" and c["nivel_referencia"] == "YELLOW" and c["partidos_senal"] == ["junin"]
    assert c["partidos_afectados"][0] == "junin" and set(c["partidos_afectados"]) == set(rio["partidos"])
    assert [loc[0] for loc in c["localidades_afectadas"]] == ["Pueblo Ribereño", "Ciudad Ribereña"]  # señal primero
    otro = next(x for x in res["cursos"] if x["nombre"] == "Arroyo de Prueba")
    assert otro["nivel"] == "GREEN" and otro["partidos_afectados"] == [] and otro["localidades_afectadas"] == []
