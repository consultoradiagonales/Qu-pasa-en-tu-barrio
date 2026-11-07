"""Genera app/data/provincias_ar.geojson (límites simplificados de las 24 jurisdicciones).

Fuente: circuitos electorales 2025 de tartagalensis/circuitos_electorales_AR (CC BY 4.0),
https://github.com/tartagalensis/circuitos_electorales_AR/tree/main/2025 .
Cada provincia = unión de sus circuitos. Se descarta lo que está al sur de los 56° S.

Uso: python scripts/build_provincias.py CARPETA_CON_LOS_24_GEOJSON
Requiere: shapely>=2
"""
import json
import sys
from pathlib import Path

from shapely import force_2d
from shapely.geometry import MultiPolygon, Polygon, box, mapping, shape
from shapely.ops import unary_union
from shapely.validation import make_valid

OUT = Path(__file__).resolve().parents[1] / "app" / "data" / "provincias_ar.geojson"
PROVINCIAS = [
    ("CABA", "Ciudad Autónoma de Buenos Aires"), ("PBA", "Buenos Aires"), ("Catamarca", "Catamarca"),
    ("Cordoba", "Córdoba"), ("Corrientes", "Corrientes"), ("Chaco", "Chaco"), ("Chubut", "Chubut"),
    ("EntreRios", "Entre Ríos"), ("Formosa", "Formosa"), ("Jujuy", "Jujuy"), ("LaPampa", "La Pampa"),
    ("LaRioja", "La Rioja"), ("Mendoza", "Mendoza"), ("Misiones", "Misiones"), ("Neuquen", "Neuquén"),
    ("RioNegro", "Río Negro"), ("Salta", "Salta"), ("SanJuan", "San Juan"), ("SanLuis", "San Luis"),
    ("SantaCruz", "Santa Cruz"), ("SantaFe", "Santa Fe"), ("Santiago", "Santiago del Estero"),
    ("Tucuman", "Tucumán"), ("TdF", "Tierra del Fuego"),
]
CLIP = box(-75, -56, -52, -21)


def polys(g):
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, MultiPolygon):
        return list(g.geoms)
    return [p for x in getattr(g, "geoms", []) for p in polys(x)]


def main(folder):
    feats = []
    for code, name in PROVINCIAS:
        src = json.load(open(Path(folder) / f"{code}.geojson"))["features"]
        geom = unary_union([make_valid(shape(f["geometry"])).buffer(0) for f in src]).buffer(0).intersection(CLIP)
        tol = 0.002 if code == "CABA" else 0.04
        # Sin huecos internos: la unión de circuitos deja micro-huecos que no son parte del límite.
        solid = unary_union([Polygon(p.exterior) for p in polys(geom)])
        parts = sorted(polys(solid.simplify(tol, preserve_topology=True)), key=lambda p: -p.area)
        parts = [p for i, p in enumerate(parts) if i == 0 or p.area > 0.01]
        g = force_2d(parts[0] if len(parts) == 1 else MultiPolygon(parts))
        g = json.loads(json.dumps(mapping(g)), parse_float=lambda v: round(float(v), 3))
        feats.append({"type": "Feature", "properties": {"id": code, "name": name}, "geometry": g})
        print(code, len(parts), "partes")
    OUT.write_text(json.dumps({"type": "FeatureCollection", "features": feats}, ensure_ascii=False,
                              separators=(",", ":")))
    print(OUT, OUT.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main(sys.argv[1])
