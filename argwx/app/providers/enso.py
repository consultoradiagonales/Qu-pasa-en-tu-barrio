"""ENSO (El Niño / La Niña) desde NOAA CPC: ONI, índices semanales Niño 1+2/3/3.4/4 y SOI."""
import re
from datetime import date

SEASONS = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
MONTHS = {m: i + 1 for i, m in enumerate(
    ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"])}
NUM = re.compile(r"-?\d+\.\d+")
WEEK = re.compile(r"^\s*(\d{2})([A-Z]{3})(\d{4})\s+(.*)$")
REGIONS = ("NINO12", "NINO3", "NINO34", "NINO4")

IMPACTS = {
    "EL_NINO": {"tendencia": "Mayor probabilidad de lluvias superiores a lo normal, en especial en primavera y verano.",
                "riesgos": ["lluvias", "inundaciones", "excesos hídricos"]},
    "LA_NINA": {"tendencia": "Mayor probabilidad de lluvias inferiores a lo normal.",
                "riesgos": ["sequía", "déficit hídrico"]},
    "NEUTRAL": {"tendencia": "Sin señal ENSO dominante: pesan más otros factores regionales.", "riesgos": []},
}
DISCLAIMER = "Señal climática estadística para la región pampeana; no es el pronóstico de un evento puntual."


def phase(value: float) -> str:
    return "EL_NINO" if value >= 0.5 else "LA_NINA" if value <= -0.5 else "NEUTRAL"


def parse_oni(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        p = line.split()
        if len(p) >= 4 and p[0] in SEASONS and p[1].isdigit():
            year = int(p[1])
            rows.append({"index_name": "ONI", "period": f"{p[0]} {year}",
                         "period_date": date(year, SEASONS.index(p[0]) + 1, 1),
                         "sst": float(p[2]), "value": float(p[3])})
    return rows


def parse_weekly(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        m = WEEK.match(line.upper())
        if not m or m.group(2) not in MONTHS:
            continue
        nums = [float(x) for x in NUM.findall(m.group(4))]
        if len(nums) < 8:
            continue
        d = date(int(m.group(3)), MONTHS[m.group(2)], int(m.group(1)))
        for i, name in enumerate(REGIONS):
            rows.append({"index_name": name, "period": d.isoformat(), "period_date": d,
                         "sst": nums[2 * i], "value": nums[2 * i + 1]})
    return rows


def parse_soi(text: str) -> list[dict]:
    """Toma el bloque estandarizado si existe. -999.9 indica dato faltante."""
    parts = re.split(r"STANDARDIZED", text, flags=re.I)
    block = parts[-1] if len(parts) > 1 else text
    rows = []
    for line in block.splitlines():
        m = re.match(r"^\s*(\d{4})\s+(.*)$", line)
        if not m:
            continue
        year = int(m.group(1))
        for month, v in enumerate(NUM.findall(m.group(2))[:12], start=1):
            v = float(v)
            if v > -99:
                rows.append({"index_name": "SOI", "period": f"{year}-{month:02d}",
                             "period_date": date(year, month, 1), "sst": None, "value": v})
    return rows


def status(rows: list[dict]) -> dict:
    """rows: dicts con index_name, period, period_date, value, sst."""
    by = {}
    for r in sorted(rows, key=lambda r: r["period_date"]):
        by.setdefault(r["index_name"], []).append(r)
    oni = by.get("ONI", [])
    if not oni:
        return {"phase": None, "note": "Sin datos ENSO"}
    last = oni[-1]
    ph = phase(last["value"])
    run = 0
    for r in reversed(oni):
        if phase(r["value"]) != ph:
            break
        run += 1
    out = {
        "phase": ph, "oni": last["value"], "season": last["period"], "consecutive_seasons": run,
        "official_episode": ph != "NEUTRAL" and run >= 5,
        "criterion": "ONI >= +0.5 El Niño, <= -0.5 La Niña; episodio oficial con 5 trimestres consecutivos",
        "weekly": {}, "soi": None,
        "impact_buenos_aires": {**IMPACTS[ph], "nota": DISCLAIMER},
    }
    for name in REGIONS:
        if by.get(name):
            w = by[name][-1]
            out["weekly"][name] = {"week": w["period"], "sst": w["sst"], "anomaly": w["value"]}
    if "NINO34" in out["weekly"]:
        out["weekly_phase_nino34"] = phase(out["weekly"]["NINO34"]["anomaly"])
    if by.get("SOI"):
        s = by["SOI"][-1]
        out["soi"] = {"month": s["period"], "value": s["value"]}
    return out


def _get(client, url: str) -> str:
    resp = client.get(url)
    resp.raise_for_status()
    return resp.text


def fetch(settings, client) -> list[dict]:
    oni = parse_oni(_get(client, settings.oni_url))
    if not oni:
        raise ValueError("ONI vacío o con formato inesperado")
    rows = oni[-60:]
    for parser, url, keep in ((parse_weekly, settings.nino_weekly_url, 48), (parse_soi, settings.soi_url, 24)):
        try:
            rows += parser(_get(client, url))[-keep:]
        except Exception:  # índices complementarios: si fallan no bloquean el ONI
            pass
    return rows
