"""Vista local con los datos publicados: no modifica fuentes ni pide pronósticos.

python scripts/preview_hydrography.py DIRECTORIO_ARGWX_PUBLICADO SALIDA
"""
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.providers import hydro, hydrography
from app.services.municipalities import load_municipalities
from app.util import iso, utcnow


def main(source, target):
    source, target = Path(source).resolve(), Path(target).resolve()
    if source == target or source in target.parents or target in source.parents:
        raise ValueError("La vista requiere una salida separada del sitio publicado")
    shutil.copytree(source, target, dirs_exist_ok=True)
    shutil.copytree(Path(__file__).parents[1] / "app" / "site", target, dirs_exist_ok=True)
    data = target / "data"

    def read(name):
        p = data / name
        return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None

    def write(name, obj):
        (data / name).write_text(json.dumps({"generated_at": iso(utcnow()), **obj}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    net = hydrography.build_catalog()
    basins = json.loads((hydrography.DATA / "cuencas_hidricas.geojson").read_text(encoding="utf-8"))
    net["cuencas_geojson"] = basins
    result = hydro.compute_floods(net, read("caudales_red.json"), read("suelo.json"),
        hydro.rain72_by_partido(read("alertas_pba.json")), read("rios.json"),
        {m["id"]: m["name"] for m in load_municipalities()}, observed=read("rios_observados.json"))
    result["insumos"] = {name: (read(name) or {}).get("generated_at") for name in
        ("caudales_red.json", "suelo.json", "alertas_pba.json", "rios.json", "rios_observados.json")}
    write("red_hidrica.json", net)
    write("cuencas_hidricas.json", basins)
    write("crecidas.json", result)
    print(json.dumps(result["resumen"], ensure_ascii=False))


if __name__ == "__main__":
    main(*sys.argv[1:])
