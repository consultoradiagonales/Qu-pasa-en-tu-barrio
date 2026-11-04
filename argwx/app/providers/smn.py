"""Alertas oficiales del SMN (Servicio Meteorológico Nacional): feeds CAP 1.2, Atom/RSS con CAP o GeoRSS.

Cada alerta se asigna a los partidos cuyo punto de pronóstico cae dentro del polígono oficial.
Si el área no trae polígono, se busca el nombre del partido en la descripción del área.
"""
import email.utils
import logging
import re
import xml.etree.ElementTree as ET
from datetime import datetime

from app.engine.geo import normalize, point_in_polygon
from app.engine.levels import max_level
from app.util import to_utc_naive

log = logging.getLogger("argwx.smn")

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


def affected(alert: dict, munis: list[dict]) -> list[str]:
    ids = set()
    by_length = sorted(munis, key=lambda m: -len(m["name"]))
    for area in alert.get("areas", []):
        if area["polygons"]:
            for poly in area["polygons"]:
                ids.update(m["id"] for m in munis if point_in_polygon(m["lat"], m["lon"], poly))
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
