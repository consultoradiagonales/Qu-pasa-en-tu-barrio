"""Línea de comandos.

  python -m app.cli sync [all|models|gfs|enso|smn|alerts|obs]
  python -m app.cli status     frescura de datos por proveedor
  python -m app.cli resumen    resumen de alertas (próximas 24 h)
  python -m app.cli export-site SALIDA [CACHE]   dashboard estático (GitHub Pages)
  python -m app.cli smn-debug  diagnóstico del feed de alertas del SMN
"""
import json
import logging
import sys

from app.db import init_db, new_session
from app.services.municipalities import seed

ALIASES = {"all": ("models", "enso", "smn", "obs"), "models": ("models",), "gfs": ("models",),
           "enso": ("enso",), "smn": ("smn",), "alerts": ("smn",), "obs": ("obs",)}


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    init_db()
    with new_session() as s:
        seed(s)
    cmd = argv[0] if argv else "status"
    if cmd == "sync":
        from app.services.sync import sync

        what = argv[1] if len(argv) > 1 else "all"
        if what not in ALIASES:
            print(f"Opciones: {', '.join(ALIASES)}")
            return 2
        result = sync(ALIASES[what])
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
        return 0 if all(r.get("status") == "ok" for r in result["results"].values() if isinstance(r, dict)) else 1
    if cmd == "status":
        from app.api.health import freshness

        with new_session() as s:
            print(json.dumps(freshness(s), ensure_ascii=False, indent=2, default=str))
        return 0
    if cmd == "export-site":
        from app.export_site import build

        if len(argv) < 2:
            print("Uso: python -m app.cli export-site CARPETA_SALIDA [CARPETA_CACHE]")
            return 2
        meta = build(argv[1], argv[2] if len(argv) > 2 else None)
        print(json.dumps(meta, ensure_ascii=False, indent=2))
        return 0
    if cmd == "smn-debug":
        import re

        from app.config import get_settings
        from app.providers import smn
        from app.services.municipalities import load_municipalities
        from app.services.sync import http_client

        settings, munis = get_settings(), load_municipalities()
        with http_client(settings) as c:
            index = c.get(settings.list_of("smn_cap_urls")[0]).text
            print("INDEX:", re.sub(r"\s+", " ", index[:600]))
            links = re.findall(r"https?://[^\s\"<>]+\.xml", index)
            sample = next((u for u in links if "Tormenta_Llanura" in u), links[-1] if links else None)
            if sample:
                print("CAP:", sample, re.sub(r"\s+", " ", c.get(sample).text[:3000]))
            alerts = smn.parse_feed(index, fetch=lambda u: c.get(u).text)
        for a in alerts:
            ar = a["areas"]
            p0 = next((pl[0] for x in ar for pl in x["polygons"]), None)
            print(f"{a['level']:6} {a['hazard']:9} {a['title'][:45]:45} | areas {len(ar)} | polys "
                  f"{sum(len(x['polygons']) for x in ar)} | p0 {p0} | {ar[0]['desc'][:70] if ar else ''} "
                  f"| PBA {len(smn.affected(a, munis))}")
        return 0
    if cmd == "resumen":
        from app.services.state import compute_state, summary

        with new_session() as s:
            st = compute_state(s)
        order = ("GREEN", "YELLOW", "ORANGE", "RED", "PURPLE")
        entries = sorted(st["windows"][24]["municipalities"].values(),
                         key=lambda e: order.index(e["alert_level"]), reverse=True)
        print(f"Modo de datos: {st['data_mode']} | Modelos: {', '.join(st['models']) or 'sin datos'}")
        print("Municipios por nivel:", summary(entries))
        for e in entries[:15]:
            print(f"  {e['alert_label']:9} {e['name']:28} {e['hazard'] or '':9} confianza {e['confidence_label']}")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
