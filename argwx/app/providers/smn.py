"""Alertas oficiales del SMN (Servicio Meteorológico Nacional): feeds CAP 1.2, Atom/RSS con CAP o GeoRSS.

Un partido queda bajo una alerta si el polígono oficial cubre su punto central o al menos el 20 % de
su superficie (estimada con una grilla de puntos). Así se evitan falsos positivos por roces en los
bordes entre provincias. Si el área no trae polígono, se busca el nombre del partido en la descripción.
"""
import email.utils
import json
import logging
import re
import xml.etree.ElementTree as ET
from datetime import datetime
from functools import lru_cache
from pathlib import Path

from app.engine.geo import normalize, point_in_polygon
from app.engine.levels import max_level
from app.util import to_utc_naive

log = logging.getLogger("argwx.smn")
GEOJSON = Path(__file__).resolve().parents[1] / "data" / "municipios_pba.geojson"
COVERAGE_MIN = 0.2

COLORS = [(r"\b(purpura|violeta)\b", "PURPLE"), (r"\b(roja|rojo)\b", "RED"), (r"\bnaranja\b", "ORANGE"),
          (r"\b(amarilla|amarillo)\b", "YELLOW")]
SEVERITY = {"extreme": "RED", "severe": "ORANGE", "moderate": "YELLOW", "minor": "YELLOW"}
HAZARDS = [("granizo", "granizo"), ("tormenta", "tormenta"), ("lluvia", "lluvia"), ("viento", "viento"),
           ("zonda", "viento"), ("calor", "calor"), ("nieve", "nieve"), ("niebla", "niebla"), ("frio", "frío"),
           ("humo", "humo"), ("polvo", "polvo")]
OTHER_PROVINCES = ["entre rios", "santa fe", "cordoba", "la pampa", "rio negro", "caba", "ciudad autonoma",
                   "uruguay", "corrientes", "san luis", "mendoza", "chubut", "neuquen"]


def _local(tag) -> str:
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def _children(el, name):
    return [c for c in el if _local(c.tag) == name]


def _text(el, name):
    c = next((c for c in el if _local(c.tag) == name), None)
    return c.text.strip() if c is not None and c.text and c.text.strip() else None


def _dt(value):
    if not value:
        return None
    try:
        d = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            d = email.utils.parsedate_to_datetime(value)
        except (TypeError, ValueError):
            return None
    return to_utc_naive(d)


def level_from_text(primary: str, secondary: str | None = None, severity: str | None = None) -> str:
    for text in (primary, secondary):
        t = normalize(text or "")
        found = [lvl for rx, lvl in COLORS if re.search(rx, t)]
        if found:
            return max_level(*found)
    return SEVERITY.get((severity or "").lower(), "YELLOW")


def hazard_from_text(*texts) -> str:
    t = normalize(" ".join(x for x in texts if x))
    return next((h for w, h in HAZARDS if w in t), "otro")


def parse_polygon(text: str) -> list[tuple[float, float]]:
    tokens = text.replace(";", " ").split()
    try:
        if tokens and all("," in tok for tok in tokens):  # CAP: "lat,lon lat,lon ..."
            pts = [tuple(float(x) for x in tok.split(",")[:2]) for tok in tokens]
        else:  # GeoRSS: "lat lon lat lon ..."
            nums = [float(x) for x in tokens]
            pts = list(zip(nums[0::2], nums[1::2]))
    except ValueError:
        return []
    return pts if len(pts) >= 3 else []


def parse_cap_alert(root) -> list[dict]:
    if (_text(root, "msgType") or "").lower() == "cancel":
        return []
    ident, sent = _text(root, "identifier"), _dt(_text(root, "sent"))
    infos = _children(root, "info")
    spanish = [i for i in infos if (_text(i, "language") or "es").lower().startswith("es")] or infos
    out = []
    for info in spanish:
        event = _text(info, "event") or ""
        headline = _text(info, "headline") or event
        desc = _text(info, "description")
        params = " ".join(f"{_text(p, 'valueName') or ''} {_text(p, 'value') or ''}"
                          for p in _children(info, "parameter"))
        areas = [{"desc": _text(a, "areaDesc") or "",
                  "polygons": [pl for pl in (parse_polygon(p.text or "") for p in _children(a, "polygon")) if pl]}
                 for a in _children(info, "area")]
        out.append({
            "external_id": ident, "issued_at": sent, "title": headline[:300], "description": desc,
            "level": level_from_text(f"{event} {headline} {params}", desc, _text(info, "severity")),
            "hazard": hazard_from_text(event, headline),
            "valid_from": _dt(_text(info, "onset") or _text(info, "effective")) or sent,
            "valid_to": _dt(_text(info, "expires")), "areas": areas,
        })
    return out


def parse_feed(xml_text: str, fetch=None) -> list[dict]:
    root = ET.fromstring(xml_text)
    if _local(root.tag) == "alert":
        return parse_cap_alert(root)
    alerts = []
    entries = [e for e in root.iter() if _local(e.tag) in ("entry", "item")]
    for e in entries[:100]:
        embedded = next((c for c in e.iter() if _local(c.tag) == "alert"), None)
        if embedded is not None:
            alerts += parse_cap_alert(embedded)
            continue
        title = _text(e, "title") or ""
        desc = _text(e, "description") or _text(e, "summary")
        polys = [parse_polygon(c.text) for c in e.iter() if _local(c.tag) == "polygon" and c.text]
        if any(polys):
            when = _dt(_text(e, "pubDate") or _text(e, "updated"))
            alerts.append({"external_id": _text(e, "guid") or _text(e, "id") or title[:200], "issued_at": when,
                           "title": title[:300], "description": desc, "level": level_from_text(title, desc),
                           "hazard": hazard_from_text(title, desc), "valid_from": when, "valid_to": None,
                           "areas": [{"desc": title, "polygons": [p for p in polys if p]}]})
            continue
        link = next((c.get("href") or (c.text or "").strip() for c in e if _local(c.tag) == "link"), None)
        if fetch and link:
            try:
                alerts += parse_feed(fetch(link))
            except Exception:  # un CAP individual roto no invalida el feed
                continue
    return alerts


def _bbox(pts) -> tuple[float, float, float, float]:
    lats, lons = [p[0] for p in pts], [p[1] for p in pts]
    return min(lats), max(lats), min(lons), max(lons)


def _bbox_overlap(a, b) -> bool:
    return a[0] <= b[1] and b[0] <= a[1] and a[2] <= b[3] and b[2] <= a[3]


@lru_cache
def _samples() -> dict[str, tuple[list, tuple]]:
    """Grilla de puntos interiores de cada partido, para estimar qué parte cubre una alerta."""
    out = {}
    for f in json.loads(GEOJSON.read_text(encoding="utf-8"))["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        rings = [[(c[1], c[0]) for c in p[0]] for p in polys]
        box = _bbox([pt for r in rings for pt in r])
        n = 8
        grid = [(box[0] + (i + 0.5) * (box[1] - box[0]) / n, box[2] + (j + 0.5) * (box[3] - box[2]) / n)
                for i in range(n) for j in range(n)]
        out[f["properties"]["id"]] = ([p for p in grid if any(point_in_polygon(p[0], p[1], r) for r in rings)], box)
    return out


def _covered(poly: list, box: tuple, m: dict) -> bool:
    if point_in_polygon(m["lat"], m["lon"], poly):
        return True
    samples, mbox = _samples().get(m["id"], ([], None))
    if not samples or not _bbox_overlap(box, mbox):
        return False
    inside = sum(point_in_polygon(lat, lon, poly) for lat, lon in samples)
    return inside / len(samples) >= COVERAGE_MIN


def affected(alert: dict, munis: list[dict]) -> list[str]:
    ids = set()
    by_length = sorted(munis, key=lambda m: -len(m["name"]))
    for area in alert.get("areas", []):
        if area["polygons"]:
            for poly in area["polygons"]:
                box = _bbox(poly)
                ids.update(m["id"] for m in munis if m["id"] not in ids and _covered(poly, box, m))
            continue
        text = f" {normalize(area['desc'])} "
        if any(p in text for p in OTHER_PROVINCES) and "buenos aires" not in text:
            continue
        for m in by_length:
            key = f" {normalize(m['name'])} "
            if key in text:
                ids.add(m["id"])
                text = text.replace(key, " ")
    return sorted(ids)


def to_rows(alerts: list[dict], munis: list[dict]) -> list[dict]:
    rows = []
    for a in alerts:
        base = {k: a[k] for k in ("external_id", "title", "description", "level", "hazard", "valid_from", "valid_to")}
        base["issued_at"] = a["issued_at"] or a["valid_from"]
        base["details"] = {"areas": [ar["desc"] for ar in a["areas"]][:20]}
        rows += [{**base, "municipality_id": mid} for mid in affected(a, munis)]
    return [r for r in rows if r["issued_at"] is not None]


def fetch(settings, client, munis: list[dict]) -> list[dict]:
    def get(url):
        resp = client.get(url)
        resp.raise_for_status()
        return resp.text

    errors = []
    for url in settings.list_of("smn_cap_urls"):
        try:
            alerts = parse_feed(get(url), fetch=get)
        except Exception as exc:
            errors.append(f"{url}: {type(exc).__name__}: {exc}"[:200])
            continue
        rows = to_rows(alerts, munis)
        log.info("Feed SMN %s: %d alertas en el feed, %d asignaciones a partidos de PBA", url, len(alerts), len(rows))
        return rows
    raise RuntimeError("Ningún feed del SMN respondió con un formato válido. " + " | ".join(errors))
