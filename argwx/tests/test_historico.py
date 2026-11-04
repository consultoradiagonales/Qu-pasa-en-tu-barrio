"""Base histórica: ERA5 incremental, verificación con corridas anteriores, registro del SMN y catálogo (sin red)."""
import io
import json
import zipfile
from datetime import date, timedelta

from app.export_site import rain_probabilities
from app.providers import historico as h


class Resp:
    def __init__(self, payload=None, content=b"", status=200):
        self._payload, self.content, self.status_code = payload, content, status

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(self.status_code)


class FakeClient:
    def __init__(self, handler):
        self.handler, self.calls = handler, []

    def get(self, url, params=None, timeout=None):
        self.calls.append((url, dict(params or {})))
        return self.handler(url, params or {})


class Settings:
    open_meteo_api_key = None


POINTS = [{"id": "lujan", "name": "Luján", "seccion": 1, "lat": -34.57, "lon": -59.11},
          {"id": "pergamino", "name": "Pergamino", "seccion": 2, "lat": -33.89, "lon": -60.57}]


def _days(start, end):
    d, out = start, []
    while d <= end:
        out.append(d.isoformat())
        d += timedelta(days=1)
    return out


def era5_handler(url, params):
    times = _days(date.fromisoformat(params["start_date"]), date.fromisoformat(params["end_date"]))
    locs = [{"daily": {"time": times, "precipitation_sum": [float(i % 7 == 0) * 12 for i in range(len(times))]}}
            for _ in params["latitude"].split(",")]
    return Resp(locs)


def test_era5_full_then_incremental(tmp_path, monkeypatch):
    monkeypatch.setattr(h, "_today", lambda: date(2026, 11, 4))
    c = FakeClient(era5_handler)
    info = h.update_era5(c, Settings(), tmp_path, POINTS)
    assert c.calls[0][1]["start_date"] == "1980-12-01" and info["hasta"] == "2026-10-28"
    rows = h.read_csv(tmp_path / h.ERA5_FILE)
    assert rows[0].keys() == {"fecha", "lujan", "pergamino"} and len(rows) == info["dias"]
    monkeypatch.setattr(h, "_today", lambda: date(2026, 11, 10))
    c2 = FakeClient(era5_handler)
    h.update_era5(c2, Settings(), tmp_path, POINTS)
    assert c2.calls[0][1]["start_date"] == "2026-10-18"     # solo los días nuevos (con 10 de solapamiento)
    assert h.read_csv(tmp_path / h.ERA5_FILE)[-1]["fecha"] == "2026-11-03"
    clima = h.climatology_file(tmp_path, POINTS)
    assert clima["periodo"] == "1981-2025"
    data = json.loads((tmp_path / h.CLIMA_FILE).read_text())
    assert data["por_seccion"] == {"1": "lujan", "2": "pergamino"} and "11" in data["puntos"]["lujan"]


def previous_handler(url, params):
    start = date(2026, 11, 1)
    times = [f"{d}T{hh:02d}:00" for d in _days(start, date(2026, 11, 4)) for hh in range(24)]
    hourly = {"time": times}
    for m in params["models"].split(","):
        for lead in (1, 2, 3):
            vals = [2.0 if t.startswith("2026-11-02") else 0.0 for t in times]
            hourly[f"precipitation_previous_day{lead}_{m}"] = vals
    return Resp({"hourly": hourly})


def test_verification_and_calibration(tmp_path, monkeypatch):
    monkeypatch.setattr(h, "_today", lambda: date(2026, 11, 4))
    monkeypatch.setattr(h.time, "sleep", lambda s: None)
    # observado: 50 mm el 2/11 en Luján
    h.write_csv(tmp_path / h.ERA5_FILE, ["fecha", "lujan", "pergamino"],
                [{"fecha": d, "lujan": 50.0 if d == "2026-11-02" else 0.0, "pergamino": 0.0}
                 for d in _days(date(2026, 11, 1), date(2026, 11, 3))])
    models = ["gfs_seamless", "icon_seamless"]
    info = h.update_verification(FakeClient(previous_handler), tmp_path, POINTS, models)
    rows = h.read_csv(tmp_path / h.VERIF_FILE)
    # 3 días completos (1, 2 y 3/11; el 4/11 es hoy) x 2 puntos x 3 plazos
    assert info["filas"] == 18 and {r["fecha"] for r in rows} == {"2026-11-01", "2026-11-02", "2026-11-03"}
    r = next(x for x in rows if x["fecha"] == "2026-11-02" and x["punto"] == "lujan" and x["plazo"] == "1")
    assert float(r["GFS"]) == 48.0 and float(r["ICON"]) == 48.0 and float(r["observado"]) == 50.0
    h.calibration_file(tmp_path, models)
    calib = json.loads((tmp_path / h.CALIB_FILE).read_text())
    assert calib["verificacion"]["GFS"]["1"]["umbrales"]["30"]["aciertos"] == 1
    bins = calib["calibracion"]["tabla"]["30"]["1"]
    # el 2/11 los dos modelos dieron 48 mm en los dos puntos: llovió en Luján (50 mm) y no en Pergamino
    assert bins[-1]["casos"] == 2 and bins[-1]["ocurrio"] == 1 and bins[-1]["frecuencia"] == 50.0
    assert bins[0]["casos"] == 4 and bins[0]["ocurrio"] == 0


def test_parse_hourly_and_station_filter():
    txt = ("FECHA     HORA  TEMP   HUM   PNM    DD    FF     NOMBRE\n"
           "          [HOA]  [ºC]   [%]  [hPa]  [gr] [km/hr]\n"
           " 03112026     0  20.4   85  1014.4   90   15     AEROPARQUE AERO\n"
           " 03112026     1  19.0   90  1013.0  110   13     JUJUY AERO\n")
    rows = h.parse_hourly(txt)
    assert rows[0] == {"fecha": "2026-11-03", "hora": 0, "temp_c": 20.4, "humedad": 85.0, "presion_hpa": 1014.4,
                       "viento_dir": 90.0, "viento_kmh": 15.0, "estacion": "AEROPARQUE AERO"}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("datohorario20261103.txt", txt.encode("latin-1"))
    c = FakeClient(lambda url, params: Resp(content=buf.getvalue()))
    import tempfile
    from pathlib import Path

    with tempfile.TemporaryDirectory() as d:
        info = h.update_smn_hourly(c, Path(d), {"AEROPARQUE AERO"})
        assert info == {"archivo": "smn_horarios_2026-11.csv", "nuevas": 1, "estaciones": 1}
        assert h.update_smn_hourly(c, Path(d), {"AEROPARQUE AERO"})["nuevas"] == 0   # no duplica


def test_alert_registry_and_forecasts_and_catalog(tmp_path):
    smn = {"alerts": [{"title": "Tormentas", "level": "YELLOW", "hazard": "tormenta", "valid_from": "2026-11-04T12:00:00Z",
                       "valid_to": "2026-11-05T00:00:00Z", "provincias": ["Córdoba"], "partidos_pba": []}]}
    assert h.update_alert_registry(tmp_path, smn) == {"alertas": 1, "nuevas": 1}
    assert h.update_alert_registry(tmp_path, smn)["nuevas"] == 0
    alertas = {"generated_at": "2026-11-04T18:00:00Z", "data_mode": "live", "windows": {"24": {
        "valid_from": "2026-11-04T18:00:00Z", "municipios": [{
            "id": "lujan", "alert_level": "GREEN", "hazard": None, "consensus": "9/9", "lluvia_mm": 3.2,
            "prob_lluvia": {"10": {"k": 1, "n": 9}, "30": {"k": 0, "n": 9}, "60": {"k": 0, "n": 9}}}]}}}
    assert h.append_forecasts(tmp_path, alertas)["nuevas"] == 1
    assert h.append_forecasts(tmp_path, alertas)["nuevas"] == 0   # una vez por día
    row = h.read_csv(tmp_path / "pronosticos_condi_2026-11.csv")[0]
    assert row["modelos"] == "9" and row["modelos_10mm"] == "1" and row["lluvia_mediana_mm"] == "3.2"
    cat = h.write_catalog(tmp_path)
    data = json.loads((tmp_path / h.CATALOG_FILE).read_text())
    assert cat["tablas"] == len(h.TABLES)
    reg = next(t for t in data["tablas"] if t["tabla"] == h.ALERTS_FILE)
    assert reg["registros"] == 1 and reg["desde"] == "2026-11-04"


def test_rain_probabilities_uses_calibration():
    calib = {"calibracion": {"tabla": {"30": {"1": [
        {"casos": 50, "ocurrio": 1, "frecuencia": 2.0, "confiable": True},
        {"casos": 20, "ocurrio": 3, "frecuencia": 15.0, "confiable": True},
        {"casos": 12, "ocurrio": 5, "frecuencia": 41.7, "confiable": True},
        {"casos": 8, "ocurrio": 5, "frecuencia": 62.5, "confiable": False},
        {"casos": 11, "ocurrio": 9, "frecuencia": 81.8, "confiable": True}]}}}}
    entry = {"models": {m: {"rain_mm": v} for m, v in zip("abcdefghi", [40, 35, 31, 30, 10, 5, 0, 0, 0])}}
    p = rain_probabilities(entry, 24, calib)
    assert p["30"]["k"] == 4 and p["30"]["n"] == 9 and p["30"]["probabilidad"] == 41.7 and p["30"]["casos"] == 12
    assert "probabilidad" not in p["60"]   # sin tabla para 60 mm
