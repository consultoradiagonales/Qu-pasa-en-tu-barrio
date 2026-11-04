"""Línea de comandos.

  python -m app.cli sync [all|models|gfs|enso|smn|alerts|obs]
  python -m app.cli status     frescura de datos por proveedor
  python -m app.cli resumen    resumen de alertas (próximas 24 h)
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
