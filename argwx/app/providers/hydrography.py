"""Inventario cartográfico trazable: DPH, IGN, GCBA y complemento OSM.

La pertenencia administrativa se obtiene por intersección de geometrías, nunca por
el centroide más próximo. El inventario no implica cobertura hidrométrica.
"""
import hashlib
import copy
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from shapely import make_valid
from shapely.geometry import LineString, MultiLineString, mapping, shape
from shapely.strtree import STRtree

from app.engine.geo import haversine_km, normalize
from app.providers import hydro

DATA = Path(__file__).parents[1] / "data"
NS = {"k": "http://www.opengis.net/kml/2.2"}
DPH_URL = "https://www.gba.gob.ar/hidraulica/cuencas_hidricas/mapa"
KML_URL = "https://www.google.com/maps/d/kml?mid=1Jvk6CoOUiGDAdeMl0aM8v6oCvcCzlG8P&forcekml=1"


def canonical(name):
    n = normalize(name)
    n = re.sub(r"^(rio|arroyo|canal|ao|aº|a°)\s+", "", n)
    n = re.sub(r"[^a-z0-9 ]", " ", n)
    return " ".join(n.split()).replace("matanza riachuelo", "matanza")


def _coords(text):
    return [(float(v.split(",")[0]), float(v.split(",")[1])) for v in (text or "").split()]


def parse_dph(kml):
    """Conserva cada Placemark, incluso sin nombre; refname no está en <name>."""
    root = ET.fromstring(kml)
    courses, basins = [], []
    counts = {}
    for folder in root.findall(".//k:Folder", NS):
        layer = folder.findtext("k:name", "", NS)
        if layer not in ("Rios", "Arroyos", "Canales", "CUENCAS"):
            continue
        marks = folder.findall("k:Placemark", NS)
        counts[layer] = len(marks)
        for p in marks:
            attrs = {d.get("name"): d.findtext("k:value", "", NS)
                     for d in p.findall("k:ExtendedData/k:Data", NS)}
            name = (p.findtext("k:name", "", NS) or attrs.get("refname") or attrs.get("n_completo") or "").strip()
            if layer == "CUENCAS":
                polys = []
                for poly in p.findall(".//k:Polygon", NS):
                    outer = poly.findtext("k:outerBoundaryIs/k:LinearRing/k:coordinates", "", NS)
                    rings = [_coords(outer)] + [_coords(r.text) for r in poly.findall("k:innerBoundaryIs/k:LinearRing/k:coordinates", NS)]
                    if len(rings[0]) >= 4:
                        polys.append(rings)
                if not polys:
                    raise ValueError(f"Cuenca sin polígono: {name}")
                geom = make_valid(shape({"type": "MultiPolygon", "coordinates": polys})).simplify(0.0002, preserve_topology=True)
                ident = "dph-cuenca-" + hashlib.sha256((name + geom.wkt).encode()).hexdigest()[:12]
                basins.append({"type": "Feature", "id": ident, "properties": {
                    "id": ident, "nombre": name or "Cuenca sin nombre", "fuente": "dph", "atributos_originales": attrs},
                    "geometry": _rounded(mapping(geom))})
                continue
            lines = [_coords(c.text) for c in p.findall(".//k:LineString/k:coordinates", NS)]
            lines = [ln for ln in lines if len(ln) >= 2]
            if not lines:
                raise ValueError(f"Cauce sin geometría: {layer} {name}")
            tipo = {"Rios": "río", "Arroyos": "arroyo", "Canales": "canal"}[layer]
            digest = hashlib.sha256(json.dumps(lines).encode()).hexdigest()[:12]
            ident = "dph-" + layer.lower() + "-" + (attrs.get("id") or digest)
            courses.append({"id": ident, "nombre": name or f"{tipo.capitalize()} sin nombre ({ident})",
                "sin_nombre": not bool(name), "tipo": tipo, "fuentes": ["dph"], "registros": [ident],
                "nombre_original": name, "atributos_originales": attrs,
                "trazo": [[[round(y, 5), round(x, 5)] for x, y in LineString(ln).simplify(0.0001).coords] for ln in lines]})
    if not courses or not basins:
        raise ValueError("El KML no contiene las capas esperadas")
    return {"cursos": courses, "cuencas": {"type": "FeatureCollection", "features": basins}, "capas": counts}


def _rounded(value):
    if isinstance(value, dict):
        return {k: _rounded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_rounded(v) for v in value]
    return round(value, 5) if isinstance(value, float) else value


def geometry(c):
    return MultiLineString([[(lon, lat) for lat, lon in ln] for ln in c["trazo"] if len(ln) >= 2])


def _aliases(c):
    key = canonical(c["nombre"])
    aliases = list(c.get("alias", []))
    if key == "salado":
        aliases += ["Río Salado del Sur"]
    if key == "matanza":
        aliases += ["Río Matanza-Riachuelo", "Riachuelo"]
    if key.startswith("parana"):
        aliases += ["Río Paraná", c["nombre"].replace("Mini", "Miní").replace("Guazu", "Guazú")]
    return list(dict.fromkeys(aliases))


def build_catalog(osm=None, geojson=None, munis=None, snapshot=None):
    snapshot = copy.deepcopy(snapshot) if snapshot is not None else json.loads((DATA / "hidrografia_oficial.json").read_text(encoding="utf-8"))
    if geojson is None:
        geojson = json.loads((DATA / "municipios_pba.geojson").read_text(encoding="utf-8"))
    if osm is None:
        osm = json.loads((DATA / "hidrografia_osm_respaldo.json").read_text(encoding="utf-8"))
    # Los tramos DPH se conservan individualmente: el total expresa registros
    # cartográficos, no un conteo de ríos únicos. No se fusionan homónimos.
    courses = snapshot["cursos"]
    geoms = [geometry(c) for c in courses]
    tree = STRtree(geoms)
    for c in osm["cursos"]:
        g = geometry(c)
        if g.is_empty:
            continue
        matches = [int(i) for i in tree.query(g.buffer(0.001)) if
                   canonical(courses[int(i)]["nombre"]) == canonical(c["nombre"]) and
                   not courses[int(i)].get("solo_caba") and
                   g.difference(geoms[int(i)].buffer(0.001)).length <= g.length * 0.15]
        if matches:
            # Conserva el complemento OSM en un solo registro, sin borrar DPH.
            i = min(matches, key=lambda i: geoms[i].distance(g))
            courses[i]["fuentes"] = list(dict.fromkeys(courses[i]["fuentes"] + ["osm"]))
            courses[i]["registros"] += ["osm-" + c["id"]]
            courses[i]["localidades"] = c.get("localidades", [])
        else:
            courses.append({**c, "id": "osm-" + c["id"], "fuentes": ["osm"], "registros": ["osm-" + c["id"]]})
    pids = [f["properties"]["id"] for f in geojson["features"]]
    pgeoms = [make_valid(shape(f["geometry"])) for f in geojson["features"]]
    ptree = STRtree(pgeoms)
    basins = snapshot["cuencas"]["features"]
    bgeoms = [make_valid(shape(f["geometry"])) for f in basins]
    btree = STRtree(bgeoms)
    seen, total = set(), 0
    for c in sorted(courses, key=lambda c: (c["tipo"] != "río", c["id"])):
        g = geometry(c)
        c["partidos"] = sorted(pids[int(i)] for i in ptree.query(g, predicate="intersects"))
        c["cuencas"] = [basins[int(i)]["properties"]["nombre"] for i in btree.query(g, predicate="intersects")]
        c["cuenca_ids"] = [basins[int(i)]["id"] for i in btree.query(g, predicate="intersects")]
        c["jurisdicciones"] = c.get("jurisdicciones") or (["Provincia de Buenos Aires"] if c["partidos"] else ["Contexto limítrofe / jurisdicción a verificar"])
        if c.get("solo_caba"):
            c["partidos"] = []  # los datos GCBA describen únicamente sus tramos en CABA
        c["alias"] = _aliases(c)
        minx, miny, maxx, maxy = g.bounds
        c["bbox"] = [miny, minx, maxy, maxx]
        c["km"] = round(sum(haversine_km(*a, *b) for ln in c["trazo"] for a, b in zip(ln, ln[1:])), 2)
        if c.get("monitoreo") == "costero":
            c["km"] = None  # su contorno no es la longitud de un cauce
        c["localidades"] = [loc for loc in c.get("localidades", []) if loc[1] in c["partidos"]]
        c["muestras"] = []
        # Un inventario urbano o un estuario no habilita un modelo fluvial grueso.
        if c["tipo"] != "río" or c.get("monitoreo") == "costero" or c["km"] < hydro.GLOFAS_KM:
            continue
        verts = [(lat, lon, pid) for ln in c["trazo"] for lat, lon in ln for pid in c["partidos"]
                 if pgeoms[pids.index(pid)].covers(shape({"type": "Point", "coordinates": [lon, lat]}))]
        for lat, lon, pid in hydro._farthest(verts, min(4, 1 + int(c["km"] // 60))):
            cell = (round(lat * 20), round(lon * 20))
            if cell in seen or total >= hydro.MAX_SAMPLES:
                continue
            seen.add(cell)
            total += 1
            c["muestras"].append({"lat": round(lat, 3), "lon": round(lon, 3), "partido": pid})
    return {"version": hydro.VERSION, "fuente": "DPH Buenos Aires · IGN · GCBA · © colaboradores de OpenStreetMap (ODbL)",
            "fuentes": snapshot["fuentes"], "cobertura": {"registros_dph": snapshot["capas"],
            "cuencas": len(basins), "fecha_descarga": snapshot["fecha_descarga"],
            "unidad": "tramos cartográficos; un curso puede tener varios registros",
            "nota": "Cobertura según las fuentes publicadas; no garantiza exhaustividad física ni monitoreo de cada cauce."},
            "cursos": courses}


def export_network(client, geojson, munis):
    """Actualización mensual DPH; respaldo versionado si el recurso no responde."""
    snapshot = json.loads((DATA / "hidrografia_oficial.json").read_text(encoding="utf-8"))
    warning = None
    try:
        from datetime import datetime, timezone
        response = client.get(KML_URL, timeout=60, follow_redirects=True)
        response.raise_for_status()
        fresh = parse_dph(response.content)
        if len(fresh["cursos"]) < 100 or len(fresh["cuencas"]["features"]) < 20:
            raise ValueError("Recurso DPH posiblemente incompleto")
        snapshot["cursos"] = fresh["cursos"] + [c for c in snapshot["cursos"] if "dph" not in c["fuentes"]]
        snapshot["cuencas"] = fresh["cuencas"]
        snapshot["capas"].update(fresh["capas"])
        snapshot["fecha_descarga"] = datetime.now(timezone.utc).date().isoformat()
        snapshot["fuentes"][0].update(sha256=hashlib.sha256(response.content).hexdigest(), fecha_descarga=snapshot["fecha_descarga"])
    except Exception as exc:
        warning = f"DPH: se usa respaldo cartográfico de {snapshot['fecha_descarga']} ({type(exc).__name__})"
    result = build_catalog(geojson=geojson, munis=munis, snapshot=snapshot)
    result["cuencas_geojson"] = snapshot["cuencas"]
    if warning:
        result["advertencias"] = [warning]
    return result
