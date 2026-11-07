"""Genera app/data/municipios_pba.json y app/data/municipios_pba.geojson.

Fuentes (descargar antes de correr):
  1. Circuitos electorales 2025 de PBA (CC BY 4.0), tartagalensis/circuitos_electorales_AR:
     https://raw.githubusercontent.com/tartagalensis/circuitos_electorales_AR/main/2025/PBA.geojson
     -> geometría de los 135 partidos (se disuelven los circuitos por `coddepto`).
  2. Departamentos IGN (SIG 250) de mgaitan/departamentos_argentina:
     https://raw.githubusercontent.com/mgaitan/departamentos_argentina/master/departamentos-buenos_aires.json
     -> nombres de los partidos (se asignan por superposición espacial).
     Este archivo es anterior a la creación de Lezama (2009): el código 135, segundo
     polígono dentro del Chascomús histórico y ubicado al sur, se asigna a Lezama.

Uso: python scripts/build_municipios.py PBA.geojson departamentos-buenos_aires.json
Requiere: shapely>=2
"""
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

from shapely import force_2d
from shapely.geometry import MultiPolygon, Polygon, mapping, shape
from shapely.ops import unary_union
from shapely.validation import make_valid

OUT = Path(__file__).resolve().parents[1] / "app" / "data"

NOMBRES = {
    "25 DE MAYO": "25 de Mayo", "9 DE JULIO": "9 de Julio", "ADOLFO ALSINA": "Adolfo Alsina",
    "ADOLFO GONZALES CHAVES": "Adolfo Gonzales Chaves", "ALBERTI": "Alberti",
    "ALMIRANTE BROWN": "Almirante Brown", "ARRECIFES": "Arrecifes", "AVELLANEDA": "Avellaneda",
    "AYACUCHO": "Ayacucho", "AZUL": "Azul", "BAHIA BLANCA": "Bahía Blanca", "BALCARCE": "Balcarce",
    "BARADERO": "Baradero", "BENITO JUAREZ": "Benito Juárez", "BERAZATEGUI": "Berazategui",
    "BERISSO": "Berisso", "BOLIVAR": "Bolívar", "BRAGADO": "Bragado", "BRANDSEN": "Brandsen",
    "CAMPANA": "Campana", "CAPITAN SARMIENTO": "Capitán Sarmiento", "CARLOS CASARES": "Carlos Casares",
    "CARLOS TEJEDOR": "Carlos Tejedor", "CARMEN DE ARECO": "Carmen de Areco", "CASTELLI": "Castelli",
    "CAÑUELAS": "Cañuelas", "CHACABUCO": "Chacabuco", "CHASCOMUS": "Chascomús", "CHIVILCOY": "Chivilcoy",
    "COLON": "Colón", "CORONEL DE MARINA LEONARDO ROSALES": "Coronel Rosales",
    "CORONEL DORREGO": "Coronel Dorrego", "CORONEL PRINGLES": "Coronel Pringles",
    "CORONEL SUAREZ": "Coronel Suárez", "DAIREAUX": "Daireaux", "DOLORES": "Dolores",
    "ENSENADA": "Ensenada", "ESCOBAR": "Escobar", "ESTEBAN ECHEVERRIA": "Esteban Echeverría",
    "EXALTACION DE LA CRUZ": "Exaltación de la Cruz", "EZEIZA": "Ezeiza",
    "FLORENCIO VARELA": "Florencio Varela", "FLORENTINO AMEGHINO": "Florentino Ameghino",
    "GENERAL ALVARADO": "General Alvarado", "GENERAL ALVEAR": "General Alvear",
    "GENERAL ARENALES": "General Arenales", "GENERAL BELGRANO": "General Belgrano",
    "GENERAL GUIDO": "General Guido", "GENERAL JUAN MADARIAGA": "General Juan Madariaga",
    "GENERAL LA MADRID": "General La Madrid", "GENERAL LAS HERAS": "General Las Heras",
    "GENERAL LAVALLE": "General Lavalle", "GENERAL PAZ": "General Paz", "GENERAL PINTO": "General Pinto",
    "GENERAL PUEYRREDON": "General Pueyrredón", "GENERAL RODRIGUEZ": "General Rodríguez",
    "GENERAL SAN MARTIN": "General San Martín", "GENERAL VIAMONTE": "General Viamonte",
    "GENERAL VILLEGAS": "General Villegas", "GUAMINI": "Guaminí", "HIPOLITO YRIGOYEN": "Hipólito Yrigoyen",
    "HURLINGHAM": "Hurlingham", "ITUZAINGO": "Ituzaingó", "JOSE C PAZ": "José C. Paz", "JUNIN": "Junín",
    "LA COSTA": "La Costa", "LA MATANZA": "La Matanza", "LA PLATA": "La Plata", "LANUS": "Lanús",
    "LAPRIDA": "Laprida", "LAS FLORES": "Las Flores", "LEANDRO N ALEM": "Leandro N. Alem",
    "LINCOLN": "Lincoln", "LOBERIA": "Lobería", "LOBOS": "Lobos", "LOMAS DE ZAMORA": "Lomas de Zamora",
    "LUJAN": "Luján", "MAGDALENA": "Magdalena", "MAIPU": "Maipú", "MALVINAS ARGENTINAS": "Malvinas Argentinas",
    "MAR CHIQUITA": "Mar Chiquita", "MARCOS PAZ": "Marcos Paz", "MERCEDES": "Mercedes", "MERLO": "Merlo",
    "MONTE": "Monte", "MONTE HERMOSO": "Monte Hermoso", "MORENO": "Moreno", "MORON": "Morón",
    "NAVARRO": "Navarro", "NECOCHEA": "Necochea", "OLAVARRIA": "Olavarría", "PATAGONES": "Patagones",
    "PEHUAJO": "Pehuajó", "PELLEGRINI": "Pellegrini", "PERGAMINO": "Pergamino", "PILA": "Pila",
    "PILAR": "Pilar", "PINAMAR": "Pinamar", "PRESIDENTE PERON": "Presidente Perón", "PUAN": "Puan",
    "PUNTA INDIO": "Punta Indio", "QUILMES": "Quilmes", "RAMALLO": "Ramallo", "RAUCH": "Rauch",
    "RIVADAVIA": "Rivadavia", "ROJAS": "Rojas", "ROQUE PEREZ": "Roque Pérez", "SAAVEDRA": "Saavedra",
    "SALADILLO": "Saladillo", "SALLIQUELO": "Salliqueló", "SALTO": "Salto",
    "SAN ANDRES DE GILES": "San Andrés de Giles", "SAN ANTONIO DE ARECO": "San Antonio de Areco",
    "SAN CAYETANO": "San Cayetano", "SAN FERNANDO": "San Fernando", "SAN ISIDRO": "San Isidro",
    "SAN MIGUEL": "San Miguel", "SAN NICOLAS": "San Nicolás", "SAN PEDRO": "San Pedro",
    "SAN VICENTE": "San Vicente", "SUIPACHA": "Suipacha", "TANDIL": "Tandil", "TAPALQUE": "Tapalqué",
    "TIGRE": "Tigre", "TORDILLO": "Tordillo", "TORNQUIST": "Tornquist", "TRENQUE LAUQUEN": "Trenque Lauquen",
    "TRES ARROYOS": "Tres Arroyos", "TRES DE FEBRERO": "Tres de Febrero", "TRES LOMAS": "Tres Lomas",
    "VICENTE LOPEZ": "Vicente López", "VILLA GESELL": "Villa Gesell", "VILLARINO": "Villarino",
    "ZARATE": "Zárate",
}

# Secciones electorales de la Provincia de Buenos Aires (8va = Sección Capital).
SECCIONES = {
    1: ["Campana", "Escobar", "General Las Heras", "General Rodríguez", "General San Martín", "Hurlingham",
        "Ituzaingó", "José C. Paz", "Luján", "Malvinas Argentinas", "Marcos Paz", "Mercedes", "Merlo",
        "Moreno", "Morón", "Navarro", "Pilar", "San Fernando", "San Isidro", "San Miguel", "Suipacha",
        "Tigre", "Tres de Febrero", "Vicente López"],
    2: ["Arrecifes", "Baradero", "Capitán Sarmiento", "Carmen de Areco", "Colón", "Exaltación de la Cruz",
        "Pergamino", "Ramallo", "Rojas", "Salto", "San Andrés de Giles", "San Antonio de Areco",
        "San Nicolás", "San Pedro", "Zárate"],
    3: ["Almirante Brown", "Avellaneda", "Berazategui", "Berisso", "Brandsen", "Cañuelas", "Ensenada",
        "Esteban Echeverría", "Ezeiza", "Florencio Varela", "La Matanza", "Lanús", "Lobos",
        "Lomas de Zamora", "Magdalena", "Presidente Perón", "Punta Indio", "Quilmes", "San Vicente"],
    4: ["Alberti", "Bragado", "Carlos Casares", "Carlos Tejedor", "Chacabuco", "Chivilcoy",
        "Florentino Ameghino", "General Arenales", "General Pinto", "General Viamonte", "General Villegas",
        "Hipólito Yrigoyen", "Junín", "Leandro N. Alem", "Lincoln", "9 de Julio", "Pehuajó", "Rivadavia",
        "Trenque Lauquen"],
    5: ["Ayacucho", "Balcarce", "Castelli", "Chascomús", "Dolores", "General Alvarado", "General Belgrano",
        "General Guido", "General Juan Madariaga", "General Lavalle", "General Paz", "General Pueyrredón",
        "La Costa", "Las Flores", "Lezama", "Lobería", "Maipú", "Mar Chiquita", "Monte", "Necochea", "Pila",
        "Pinamar", "Rauch", "San Cayetano", "Tandil", "Tordillo", "Villa Gesell"],
    6: ["Adolfo Alsina", "Adolfo Gonzales Chaves", "Bahía Blanca", "Benito Juárez", "Coronel Dorrego",
        "Coronel Pringles", "Coronel Rosales", "Coronel Suárez", "Daireaux", "General La Madrid", "Guaminí",
        "Laprida", "Monte Hermoso", "Patagones", "Pellegrini", "Puan", "Saavedra", "Salliqueló", "Tornquist",
        "Tres Arroyos", "Tres Lomas", "Villarino"],
    7: ["25 de Mayo", "Azul", "Bolívar", "General Alvear", "Olavarría", "Roque Pérez", "Saladillo", "Tapalqué"],
    8: ["La Plata"],
}
# 24 partidos del Gran Buenos Aires (definición INDEC).
CONURBANO = {"Almirante Brown", "Avellaneda", "Berazategui", "Esteban Echeverría", "Ezeiza", "Florencio Varela",
             "General San Martín", "Hurlingham", "Ituzaingó", "José C. Paz", "La Matanza", "Lanús",
             "Lomas de Zamora", "Malvinas Argentinas", "Merlo", "Moreno", "Morón", "Quilmes", "San Fernando",
             "San Isidro", "San Miguel", "Tigre", "Tres de Febrero", "Vicente López"}


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def polys(g):
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, MultiPolygon):
        return list(g.geoms)
    return [p for x in getattr(g, "geoms", []) for p in polys(x)]


def main(circ_path, old_path):
    circ = json.load(open(circ_path))["features"]
    old = [(NOMBRES[f["properties"]["departamento"]], make_valid(shape(f["geometry"])).buffer(0))
           for f in json.load(open(old_path))["features"]]
    groups, sueltos = defaultdict(list), []
    for f in circ:
        g = make_valid(shape(f["geometry"])).buffer(0)
        c = f["properties"]["coddepto"]
        (sueltos if c == "nan" else groups[c]).append(g)
    diss = {c: unary_union(gs).buffer(0) for c, gs in groups.items()}

    def best_name(g):
        return max(old, key=lambda o: g.intersection(o[1]).area)[0]

    nombre = {c: best_name(g) for c, g in diss.items()}
    dup = [c for c in diss if list(nombre.values()).count(nombre[c]) > 1]
    assert sorted(nombre[c] for c in dup) == ["Chascomús", "Chascomús"], dup
    sur = min(dup, key=lambda c: diss[c].centroid.y)
    nombre[sur] = "Lezama"
    # Fragmentos sin código de circuito: se suman al partido que los contiene.
    por_nombre = {v: k for k, v in nombre.items()}
    for g in sueltos:
        n = best_name(g)
        if n == "Chascomús":
            n = max(("Chascomús", "Lezama"), key=lambda x: g.distance(diss[por_nombre[x]]) * -1)
        c = por_nombre[n]
        diss[c] = unary_union([diss[c], g]).buffer(0)

    seccion = {n: s for s, ns in SECCIONES.items() for n in ns}
    assert len(seccion) == 135 and set(seccion) == set(nombre.values()), set(seccion) ^ set(nombre.values())

    munis, feats = [], []
    for c in sorted(diss):
        g, n = diss[c], nombre[c]
        p = g.centroid if g.contains(g.centroid) else g.representative_point()
        m = {"id": slug(n), "name": n, "seccion": seccion[n], "codigo_electoral": c,
             "conurbano": n in CONURBANO, "lat": round(p.y, 4), "lon": round(p.x, 4)}
        munis.append(m)
        parts = sorted(polys(g.simplify(0.003, preserve_topology=True)), key=lambda x: -x.area)
        parts = [x for i, x in enumerate(parts) if i == 0 or x.area > 0.0003]
        geom = mapping(force_2d(parts[0] if len(parts) == 1 else MultiPolygon(parts)))
        geom = json.loads(json.dumps(geom), parse_float=lambda v: round(float(v), 4))
        feats.append({"type": "Feature", "properties": {"id": m["id"], "name": n, "seccion": m["seccion"]},
                      "geometry": geom})
    munis.sort(key=lambda m: m["name"])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "municipios_pba.json").write_text(json.dumps(munis, ensure_ascii=False, indent=1))
    (OUT / "municipios_pba.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": feats}, ensure_ascii=False, separators=(",", ":")))
    print(len(munis), "partidos;", {s: sum(1 for m in munis if m["seccion"] == s) for s in range(1, 9)})


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
