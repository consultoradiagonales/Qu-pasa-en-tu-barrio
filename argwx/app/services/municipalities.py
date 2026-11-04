"""Los 135 partidos de la Provincia de Buenos Aires (ver app/data/README.md)."""
import json
from functools import lru_cache
from pathlib import Path

from sqlalchemy import select

from app.engine.geo import normalize
from app.models import Municipality

DATA = Path(__file__).resolve().parents[1] / "data"
SECCION_NOMBRE = {1: "Primera Sección", 2: "Segunda Sección", 3: "Tercera Sección", 4: "Cuarta Sección",
                  5: "Quinta Sección", 6: "Sexta Sección", 7: "Séptima Sección", 8: "Sección Capital"}


@lru_cache
def load_municipalities() -> list[dict]:
    return json.loads((DATA / "municipios_pba.json").read_text(encoding="utf-8"))


@lru_cache
def geojson_text() -> str:
    return (DATA / "municipios_pba.geojson").read_text(encoding="utf-8")


@lru_cache
def by_id() -> dict[str, dict]:
    return {m["id"]: m for m in load_municipalities()}


def find(key: str) -> dict | None:
    """Busca por id (la-plata) o por nombre (La Plata, la plata, LA PLATA)."""
    if key in by_id():
        return by_id()[key]
    k = normalize(key)
    return next((m for m in load_municipalities() if normalize(m["name"]) == k), None)


def seed(session) -> int:
    existing = set(session.scalars(select(Municipality.id)))
    new = [Municipality(**m) for m in load_municipalities() if m["id"] not in existing]
    session.add_all(new)
    session.commit()
    return len(new)
