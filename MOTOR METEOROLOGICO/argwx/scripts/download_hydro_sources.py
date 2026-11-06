"""Descarga pública con TLS validado. No sustituye geometrías por coordenadas inventadas."""
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("hydro-sources")
URLS = {
    "hidraulica-cuencas.kml": "https://www.google.com/maps/d/kml?mid=1Jvk6CoOUiGDAdeMl0aM8v6oCvcCzlG8P&forcekml=1",
    "red-osm-anterior.json": "https://raw.githubusercontent.com/consultoradiagonales/Qu-pasa-en-tu-barrio/main/argwx/app/data/hidrografia_osm_respaldo.json",
    "caba-arroyos-resource.html": "https://data.buenosaires.gob.ar/dataset/arroyos/resource/juqdkmgo-111-resource",
    "caba-arroyos.csv": "https://data.buenosaires.gob.ar/dataset/arroyos/resource/juqdkmgo-111-resource/download",
    "caba-arroyos.html": "https://data.buenosaires.gob.ar/dataset/arroyos",
    "ign-plata.json": "https://wms.ign.gob.ar/geoserver/ign/ows?" + urlencode({
        "service": "WFS", "version": "1.0.0", "request": "GetFeature",
        "typeName": "ign:areas_de_aguas_continentales_BH140", "outputFormat": "application/json",
        "srsName": "EPSG:4326", "CQL_FILTER": "nam ILIKE '%Plata%'"}),
}
if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, url in URLS.items():
        if (OUT / name).exists():
            continue
        try:
            with urlopen(Request(url, headers={"User-Agent": "ConDi-ARGWX/1.0"}), timeout=120) as r:
                data = r.read(40_000_000)
            (OUT / name).write_bytes(data)
            print(name, len(data))
        except Exception as e:
            print(name, type(e).__name__, str(e)[:200])
