"""Importación reproducible de los archivos oficiales descargados (sin red).

Uso: python scripts/import_hydrography.py DIRECTORIO_DE_FUENTES
"""
import hashlib
import json
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from shapely import from_wkt, union_all
from shapely.geometry import mapping, shape
from app.providers.hydrography import DATA, DPH_URL, KML_URL, parse_dph, _rounded


class Rows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        if tag == "td":
            self.cell = ""

    def handle_data(self, data):
        if self.cell is not None:
            self.cell += data

    def handle_endtag(self, tag):
        if tag == "td" and self.row is not None and self.cell is not None:
            self.row.append(self.cell.strip())
            self.cell = None
        if tag == "tr" and self.row:
            self.rows.append(self.row)
            self.row = None


def main(source_dir):
    root = Path(source_dir)
    raw = (root / "hidraulica-cuencas.kml").read_bytes()
    result = parse_dph(raw)
    today = datetime.now(timezone.utc).date().isoformat()
    result["fecha_descarga"] = today
    result["fuentes"] = [
        {"id": "dph", "nombre": "Dirección Provincial de Hidráulica · Provincia de Buenos Aires",
         "url": DPH_URL, "recurso": KML_URL, "sha256": hashlib.sha256(raw).hexdigest(),
         "fecha_descarga": today, "fecha_original": "No informada en el KML",
         "licencia": "No declarada en el recurso; se conserva atribución y procedencia."},
        {"id": "ign", "nombre": "FUENTE: Instituto Geográfico Nacional de la República Argentina",
         "url": "https://www.ign.gob.ar/NuestrasActividades/InformacionGeoespacial/CapasSIG",
         "recurso": "ign:areas_de_aguas_continentales_BH140 · nam ILIKE '%Plata%'",
         "fecha_original": "Esri-World_Imagery 2010 (campo fdc)", "fecha_descarga": today,
         "licencia": "https://www.ign.gob.ar/descargas/tyc1.html",
         "sha256": hashlib.sha256((root / "ign-plata.json").read_bytes()).hexdigest()},
        {"id": "gcba", "nombre": "GCBA · Dirección General de Hidráulica · Arroyos",
         "url": "https://data.buenosaires.gob.ar/dataset/arroyos",
         "recurso": "https://data.buenosaires.gob.ar/dataset/arroyos/resource/juqdkmgo-111-resource",
         "formato": "Tabla pública del recurso (geometrías WKT); descarga CSV no disponible al importar",
         "fecha_actualizacion_catalogo": "2026-07-06", "fecha_descarga": today,
         "sha256": hashlib.sha256((root / "caba-arroyos-resource.html").read_bytes()).hexdigest()},
        {"id": "osm", "nombre": "© colaboradores de OpenStreetMap", "url": "https://www.openstreetmap.org/copyright",
         "licencia": "ODbL", "fecha_descarga": today,
         "fecha_generacion_respaldo": json.loads((root / "red-osm-anterior.json").read_text(encoding="utf-8")).get("generated_at"),
         "sha256": hashlib.sha256((root / "red-osm-anterior.json").read_bytes()).hexdigest()},
    ]
    ign = json.loads((root / "ign-plata.json").read_text(encoding="utf-8"))
    selected = [f for f in ign["features"] if f["properties"]["nam"] == "de la Plata"]
    if not selected:
        raise ValueError("IGN no devolvió el estuario")
    g = union_all([shape(f["geometry"]) for f in selected]).simplify(0.0002, preserve_topology=True)
    lines = [list(p.exterior.coords) for p in (g.geoms if g.geom_type == "MultiPolygon" else [g])]
    result["cursos"].append({"id": "ign-rio-de-la-plata", "nombre": "Río de la Plata", "tipo": "estuario",
        "monitoreo": "costero", "fuentes": ["ign"], "registros": [f["id"] for f in selected],
        "jurisdicciones": ["Provincia de Buenos Aires", "CABA", "Estuario compartido con Uruguay"],
        "area": _rounded(mapping(g)), "trazo": [[[round(y, 5), round(x, 5)] for x, y in ln] for ln in lines]})
    parser = Rows()
    parser.feed((root / "caba-arroyos-resource.html").read_text(encoding="utf-8"))
    count = 0
    for row in parser.rows:
        wkt = next((v for v in row if v.startswith(("LINESTRING", "MULTILINESTRING"))), None)
        if not wkt:
            continue
        geom = from_wkt(wkt)
        name = row[1]
        if "Ã" in name:  # el preview del catálogo publica mojibake en algunos nombres
            name = name.encode("latin-1").decode("utf-8")
        ident = "gcba-arroyo-" + row[0]
        result["cursos"].append({"id": ident, "nombre": name, "tipo": "arroyo", "fuentes": ["gcba"],
            "registros": [ident], "solo_caba": True, "jurisdicciones": ["CABA (tramo cartografiado por GCBA)"],
            "monitoreo": "urbano", "nota": "Trazado oficial urbano; puede incluir tramos entubados. Sin modelo de capacidad pluvial.",
            "trazo": [[[round(y, 5), round(x, 5)] for x, y in ln.coords] for ln in (geom.geoms if geom.geom_type == "MultiLineString" else [geom])]})
        count += 1
    if count < 6:
        raise ValueError("GCBA: tabla incompleta")
    result["capas"]["GCBA"] = count
    result["capas"]["IGN_estuario"] = len(selected)
    (DATA / "hidrografia_oficial.json").write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (DATA / "cuencas_hidricas.geojson").write_text(json.dumps(result["cuencas"], ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    osm = json.loads((root / "red-osm-anterior.json").read_text(encoding="utf-8"))
    (DATA / "hidrografia_osm_respaldo.json").write_text(json.dumps(osm, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(result["capas"], "cursos", len(result["cursos"]))


if __name__ == "__main__":
    main(sys.argv[1])
