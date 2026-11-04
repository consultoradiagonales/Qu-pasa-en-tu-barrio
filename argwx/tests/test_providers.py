from datetime import datetime, timedelta
from pathlib import Path

from app.providers import enso, openmeteo, smn
from app.services.municipalities import load_municipalities

FIX = Path(__file__).parent / "fixtures"


def test_parse_oni_and_status():
    rows = enso.parse_oni((FIX / "oni_sample.txt").read_text())
    assert rows[0]["period"] == "DJF 2026" and rows[0]["value"] == -0.6
    st = enso.status(rows)
    assert st["phase"] == "EL_NINO" and st["oni"] == 0.9 and st["season"] == "ASO 2026"
    assert st["consecutive_seasons"] == 5 and st["official_episode"] is True
    assert "inundaciones" in st["impact_buenos_aires"]["riesgos"]


def test_parse_weekly_with_glued_negative_numbers():
    rows = enso.parse_weekly((FIX / "wksst_sample.txt").read_text())
    last = [r for r in rows if r["index_name"] == "NINO34"][-1]
    assert last["period"] == "2026-10-28" and last["value"] == 0.9
    first12 = [r for r in rows if r["index_name"] == "NINO12"][0]
    assert first12["sst"] == 23.4 and first12["value"] == -0.4


def test_parse_soi_uses_standardized_block():
    rows = enso.parse_soi((FIX / "soi_sample.txt").read_text())
    assert rows[-1]["period"] == "2026-09" and rows[-1]["value"] == -1.1  # -999.9 se descarta


def test_openmeteo_aggregation_multi_model():
    now = datetime(2026, 11, 4, 5, 30)
    start = datetime(2026, 11, 4, 0)
    times = [(start + timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M") for h in range(96)]
    loc = {"hourly": {"time": times,
                      "precipitation_gfs_seamless": [1.0] * 96, "wind_gusts_10m_gfs_seamless": [50.0] * 95 + [90.0],
                      "temperature_2m_gfs_seamless": [20.0] * 96, "weather_code_gfs_seamless": [3] * 96,
                      "precipitation_icon_seamless": [None] * 96, "temperature_2m_icon_seamless": [None] * 96}}
    res = openmeteo.parse_location(loc, ["gfs_seamless", "icon_seamless"], now)
    assert list(res) == ["GFS"]  # ICON sin datos se descarta
    w24 = res["GFS"][0]
    assert w24["window_h"] == 24 and w24["rain_mm"] == 24.0 and w24["valid_from"] == datetime(2026, 11, 4, 5)
    assert [w["window_h"] for w in res["GFS"]] == [24, 48, 72]


def test_cap_alert_polygon_and_color():
    munis = load_municipalities()
    alerts = smn.parse_feed((FIX / "cap_sample.xml").read_text())
    assert len(alerts) == 2
    a, b = alerts
    assert a["level"] == "ORANGE" and a["hazard"] == "tormenta"
    assert "la-plata" in smn.affected(a, munis)
    ids = smn.affected(b, munis)
    assert {"pila", "pilar", "rojas"} <= set(ids) and "monte" not in ids and "monte-hermoso" in ids
    assert b["level"] == "YELLOW"  # "Rojas" no debe leerse como alerta roja


def test_georss_feed():
    xml = """<rss xmlns:georss="http://www.georss.org/georss"><channel><item>
      <title>Aviso a corto plazo por tormentas fuertes</title><description>Nivel naranja</description>
      <pubDate>Wed, 04 Nov 2026 18:00:00 -0300</pubDate>
      <georss:polygon>-34.9 -58.1 -34.9 -57.9 -35.1 -57.9 -35.1 -58.1</georss:polygon></item></channel></rss>"""
    alerts = smn.parse_feed(xml)
    assert alerts[0]["level"] == "ORANGE" and alerts[0]["issued_at"] == datetime(2026, 11, 4, 21)
    assert "la-plata" in smn.affected(alerts[0], load_municipalities())


def test_alert_covering_part_of_a_partido():
    munis = load_municipalities()
    # Rectángulo que cubre casi todo Tandil (incluye su centro) -> Tandil en alerta
    tandil = {"areas": [{"desc": "", "polygons": [[(-37.0, -59.6), (-37.0, -58.7), (-37.7, -58.7), (-37.7, -59.6)]]}]}
    assert "tandil" in smn.affected(tandil, munis)
    # Franja angosta sobre el límite con La Pampa: roza Pellegrini y Rivadavia pero no los cubre
    borde = {"areas": [{"desc": "", "polygons": [[(-35.2, -63.45), (-35.2, -63.37), (-36.6, -63.37), (-36.6, -63.45)]]}]}
    assert smn.affected(borde, munis) == []


def test_export_helpers():
    from datetime import date as d, timedelta as td

    from app.export_site import _season_months, enso_rain_composites, storm_grid

    assert _season_months(0, 2000) == [(1999, 12), (2000, 1), (2000, 2)]
    assert _season_months(11, 2000) == [(2000, 11), (2000, 12), (2001, 1)]
    ids = {p["id"] for p in storm_grid()}
    assert len(ids) > 50 and "-36.0_-60.0" in ids and "-34.5_-80.0" not in ids
    # Años con El Niño (año % 3 == 0) llueve el doble: +50 % vs climatología; el resto -25 %
    oni = [{"period": f"{s} {y}", "value": 1.0 if y % 3 == 0 else (-1.0 if y % 3 == 1 else 0.0)}
           for y in range(1981, 2026) for s in ("DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO",
                                                "SON", "OND", "NDJ")]
    times, vals, day = [], [], d(1980, 12, 1)
    while day <= d(2025, 12, 31):
        times.append(day.isoformat())
        vals.append(2.0 if day.year % 3 == 0 else 1.0)
        day += td(days=1)
    res = enso_rain_composites({"a": {"time": times, "precipitation_sum": vals},
                                "b": {"time": times, "precipitation_sum": vals}}, oni)
    mjj = res["provincia"]
    assert abs(mjj["EL_NINO"]["media"][5] - 50) < 1 and abs(mjj["LA_NINA"]["media"][5] + 25) < 1
    assert res["resumen"]["nino_max"]["valor"] > 40 and res["estaciones"][0]["es"] == "DEF"
