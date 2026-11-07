"""API REST v1 (base /api/v1)."""
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.config import get_settings
from app.db import get_session
from app.engine import eta
from app.engine.levels import LABEL, LEVELS, idx, info, parse_level
from app.engine.thresholds import STORM_CODES, THRESHOLDS
from app.engine.verification import metrics
from app.models import Alert, EnsoIndex, Forecast, Observation
from app.providers import enso as enso_provider
from app.services import state as st
from app.services.municipalities import SECCION_NOMBRE, find, geojson_text, load_municipalities
from app.services.runs import latest_run, run_info
from app.services.sync import ensure_data, sync
from app.util import iso, to_utc_naive, utcnow

router = APIRouter(prefix="/api/v1")
Window = Query(24, description="Ventana: 24 (próximas 24 h), 48 (24-48 h) o 72 (48-72 h)")


def require_admin(x_argwx_token: str | None = Header(default=None)):
    s = get_settings()
    if s.admin_token:
        if x_argwx_token != s.admin_token:
            raise HTTPException(401, "Token inválido. Enviar el header X-ARGWX-Token.")
    elif s.env == "production":
        raise HTTPException(403, "Configurar ARGWX_ADMIN_TOKEN para habilitar escrituras en producción.")


def current_state(session=Depends(get_session)) -> dict:
    ensure_data(session)
    return st.compute_state(session)


def _window(state: dict, ventana: int) -> dict:
    if ventana not in state["windows"]:
        raise HTTPException(422, "ventana debe ser 24, 48 o 72")
    return state["windows"][ventana]


def _muni_or_404(key: str) -> dict:
    m = find(key)
    if not m:
        raise HTTPException(404, f"Municipio no encontrado: {key}")
    return m


def _compact(e: dict) -> dict:
    keys = ("id", "name", "seccion", "seccion_nombre", "alert_level", "alert_label", "color", "meaning", "hazard",
            "confidence", "confidence_label", "consensus", "basis", "drivers", "values")
    return {k: e[k] for k in keys}


def enso_rows(session, mode: str | None) -> tuple[list[dict], object]:
    run = latest_run(session, "enso", mode)
    if not run:
        return [], None
    rows = session.scalars(select(EnsoIndex).where(EnsoIndex.run_id == run.id)).all()
    return [{"index_name": r.index_name, "period": r.period, "period_date": r.period_date, "value": r.value,
             "sst": r.sst} for r in rows], run


# ---------------------------------------------------------------- municipios
@router.get("/municipios", tags=["Municipios"], summary="Los 135 partidos con su sección electoral")
def municipios(seccion: int | None = Query(None, ge=1, le=8)):
    ms = [m for m in load_municipalities() if seccion is None or m["seccion"] == seccion]
    return {"total": len(ms), "municipios": [{**m, "seccion_nombre": SECCION_NOMBRE[m["seccion"]]} for m in ms]}


@router.get("/municipios/geojson", tags=["Municipios"], summary="Límites simplificados (GeoJSON) para mapas")
def municipios_geojson():
    return Response(geojson_text(), media_type="application/geo+json")


@router.get("/municipios/{municipio}", tags=["Municipios"], summary="Detalle: modelos, consenso, SMN y observación")
def municipio(municipio: str, state=Depends(current_state)):
    m = _muni_or_404(municipio)
    return {"generated_at": state["generated_at"], "data_mode": state["data_mode"],
            "municipio": {**m, "seccion_nombre": SECCION_NOMBRE[m["seccion"]]},
            "ventanas": {str(w): state["windows"][w]["municipalities"][m["id"]] for w in state["windows"]}}


# ---------------------------------------------------------------- alertas
@router.get("/alerts/current", tags=["Alertas"], summary="Alerta vigente en cada uno de los 135 partidos")
def alerts_current(ventana: int = Window, nivel_min: str = Query("GREEN", description="GREEN..PURPLE o verde..púrpura"),
                   seccion: int | None = Query(None, ge=1, le=8), state=Depends(current_state)):
    try:
        minimum = parse_level(nivel_min)
    except ValueError as exc:
        raise HTTPException(422, str(exc))
    win = _window(state, ventana)
    entries = [e for e in win["municipalities"].values()
               if idx(e["alert_level"]) >= idx(minimum) and (seccion is None or e["seccion"] == seccion)]
    entries.sort(key=lambda e: (-idx(e["alert_level"]), -(e["values"].get("rain_mm", {}).get("median") or 0), e["name"]))
    return {"generated_at": state["generated_at"], "data_mode": state["data_mode"], "window": win["label"],
            "valid_from": win["valid_from"], "valid_to": win["valid_to"], "models": state["models"],
            "summary": st.summary(win["municipalities"].values()), "total": len(entries),
            "municipalities": [_compact(e) for e in entries]}


@router.get("/alerts/smn", tags=["Alertas"], summary="Alertas oficiales del SMN asignadas a partidos")
def alerts_smn(session=Depends(get_session), state=Depends(current_state)):
    run = latest_run(session, "smn", state["data_mode"])
    grouped = {}
    if run:
        for a in session.scalars(select(Alert).where(Alert.run_id == run.id)):
            g = grouped.setdefault(a.external_id or a.title, {
                "title": a.title, **info(a.level), "hazard": a.hazard, "description": a.description,
                "valid_from": iso(a.valid_from), "valid_to": iso(a.valid_to), "municipios": []})
            if a.municipality_id:
                g["municipios"].append(a.municipality_id)
    return {"data_mode": state["data_mode"], "run": run_info(run), "total": len(grouped),
            "alerts": list(grouped.values())}


@router.post("/alerts/calculate", tags=["Alertas"], dependencies=[Depends(require_admin)],
             summary="Sincroniza todas las fuentes y recalcula las alertas")
def alerts_calculate(session=Depends(get_session)):
    result = sync(session=session)
    state = st.compute_state(session)
    return {**result, "summary": st.summary(state["windows"][24]["municipalities"].values())}


@router.get("/zonas", tags=["Alertas"], summary="Resumen por zona (sección electoral)")
def zonas(ventana: int = Window, state=Depends(current_state)):
    _window(state, ventana)
    return {"generated_at": state["generated_at"], "data_mode": state["data_mode"],
            "window": state["windows"][ventana]["label"], "zonas": st.zones(state, ventana)}


@router.get("/alerts/thresholds", tags=["Alertas"], summary="Umbrales propios usados por el motor")
def thresholds():
    return {"nota": "Umbrales iniciales propios de ARGWX, a calibrar. No son los umbrales oficiales del SMN.",
            "niveles": [{**info(lv)} for lv in LEVELS], "umbrales": THRESHOLDS,
            "tormenta_codigo_wmo": STORM_CODES, "min_modelos_coincidentes": get_settings().min_agreeing_models}


# ---------------------------------------------------------------- pronóstico y consenso
@router.get("/forecast/rain", tags=["Pronóstico"], summary="Lluvia pronosticada por partido (GFS por defecto)")
def forecast_rain(model: str = Query("GFS", description="GFS, ICON, ECMWF, GEM, UKMO"), state=Depends(current_state)):
    model = model.upper()
    if state["models"] and model not in state["models"]:
        raise HTTPException(404, f"Modelo sin datos. Disponibles: {', '.join(state['models'])}")
    rows = []
    for m in load_municipalities():
        r = {"id": m["id"], "name": m["name"], "seccion": m["seccion"]}
        for w in state["windows"]:
            e = state["windows"][w]["municipalities"][m["id"]]
            r[f"rain_mm_{w}h"] = (e["models"].get(model) or {}).get("rain_mm")
            r[f"rain_mm_{w}h_consenso"] = e["values"].get("rain_mm", {}).get("median")
        rows.append(r)
    rows.sort(key=lambda r: -(r["rain_mm_24h"] or 0))
    return {"generated_at": state["generated_at"], "data_mode": state["data_mode"], "forecast_source": model,
            "unidad": "mm acumulados por ventana (24 h = próximas 24 h)", "municipios": rows}


@router.get("/consensus/current", tags=["Pronóstico"], summary="Consenso multimodelo por partido")
def consensus_current(ventana: int = Window, municipio: str | None = None, state=Depends(current_state)):
    win = _window(state, ventana)
    entries = win["municipalities"].values()
    if municipio:
        entries = [win["municipalities"][_muni_or_404(municipio)["id"]]]
    return {"generated_at": state["generated_at"], "data_mode": state["data_mode"], "window": win["label"],
            "formula": "consenso = modelos coincidentes / modelos analizados",
            "clasificacion": {"Baja": "0-40%", "Media": "41-70%", "Alta": "71-85%", "Muy alta": "86-100%"},
            "municipios": [{"id": e["id"], "name": e["name"], "argwx": e["argwx"], "models": e["models"],
                            "values": e["values"]} for e in entries]}


@router.get("/province/summary", tags=["Provincia"], summary="Resumen provincial (entregable MVP)")
def province_summary(ventana: int = Window, session=Depends(get_session), state=Depends(current_state)):
    win = _window(state, ventana)
    entries = list(win["municipalities"].values())
    worst = sorted(entries, key=lambda e: (-idx(e["alert_level"]), -(e["confidence"] or 0)))
    gfs = [(e["models"]["GFS"]["rain_mm"], e["name"]) for e in entries
           if e["models"].get("GFS", {}).get("rain_mm") is not None]
    rain, rain_where = max(gfs) if gfs else (None, None)
    rows, _ = enso_rows(session, state["data_mode"] if state["data_mode"] != "sin_datos" else None)
    top = worst[0] if worst else None
    return {"province": "Buenos Aires", "enso_phase": enso_provider.status(rows).get("phase") if rows else None,
            "rain_mm": rain, "alert_level": top["alert_level"] if top else "GREEN", "forecast_source": "GFS",
            "confidence": top["confidence"] if top else None,
            "alert_label": LABEL[top["alert_level"]] if top else LABEL["GREEN"],
            "rain_mm_municipio": rain_where, "window": win["label"], "data_mode": state["data_mode"],
            "generated_at": state["generated_at"], "alert_basis": f"consenso de {len(state['models'])} modelos + SMN + observaciones",
            "municipios_por_nivel": st.summary(entries),
            "peores_municipios": [_compact(e) for e in worst[:5] if e["alert_level"] != "GREEN"]}


# ---------------------------------------------------------------- ENSO
@router.get("/enso/current", tags=["ENSO"], summary="Estado ENSO actual (El Niño / Neutral / La Niña)")
@router.get("/enso/status", tags=["ENSO"], include_in_schema=False)
def enso_current(session=Depends(get_session), state=Depends(current_state)):
    mode = state["data_mode"] if state["data_mode"] != "sin_datos" else None
    rows, run = enso_rows(session, mode)
    return {"data_mode": state["data_mode"], "source": "NOAA CPC (ONI, Niño semanales, SOI)", "run": run_info(run),
            **enso_provider.status(rows)}


@router.get("/enso/history", tags=["ENSO"], summary="Serie histórica reciente de un índice")
def enso_history(indice: str = Query("ONI", description="ONI, NINO12, NINO3, NINO34, NINO4, SOI"),
                 limit: int = Query(24, ge=1, le=200), session=Depends(get_session), state=Depends(current_state)):
    mode = state["data_mode"] if state["data_mode"] != "sin_datos" else None
    rows, run = enso_rows(session, mode)
    serie = sorted((r for r in rows if r["index_name"] == indice.upper()), key=lambda r: r["period_date"])[-limit:]
    return {"indice": indice.upper(), "data_mode": state["data_mode"],
            "serie": [{"period": r["period"], "value": r["value"], "sst": r["sst"],
                       "phase": enso_provider.phase(r["value"]) if indice.upper() != "SOI" else None} for r in serie]}


# ---------------------------------------------------------------- observaciones
class ObservationIn(BaseModel):
    municipio: str = Field(..., description="id (la-plata) o nombre (La Plata)")
    rain_mm_24h: float | None = Field(None, ge=0, le=1000)
    gust_kmh: float | None = Field(None, ge=0, le=400)
    temp_c: float | None = Field(None, ge=-30, le=55)
    observed_at: datetime | None = None
    source: str = "manual"
    notes: str | None = None
    model_config = {"json_schema_extra": {"examples": [
        {"municipio": "La Plata", "rain_mm_24h": 85, "gust_kmh": 70, "source": "Estación municipal"}]}}


@router.post("/observations", tags=["Observaciones"], dependencies=[Depends(require_admin)],
             summary="Cargar una observación real (la observación prevalece sobre el modelo)")
def add_observation(body: ObservationIn, session=Depends(get_session), state=Depends(current_state)):
    m = _muni_or_404(body.municipio)
    observed = to_utc_naive(body.observed_at) or utcnow()
    mode = state["data_mode"] if state["data_mode"] != "sin_datos" else "live"
    o = Observation(municipality_id=m["id"], source=body.source[:60], observed_at=observed,
                    rain_mm_24h=body.rain_mm_24h, gust_kmh=body.gust_kmh, temp_c=body.temp_c, notes=body.notes,
                    data_mode=mode, created_at=utcnow())
    session.add(o)
    session.commit()
    entry = st.compute_state(session)["windows"][24]["municipalities"][m["id"]]
    return {"saved_id": o.id, "municipio": m["name"], "alerta_resultante": _compact(entry)}


@router.get("/observations/current", tags=["Observaciones"], summary="Observaciones recientes")
def observations_current(session=Depends(get_session)):
    since = utcnow() - timedelta(hours=get_settings().observation_max_age_h)
    obs = session.scalars(select(Observation).where(Observation.observed_at >= since)
                          .order_by(Observation.observed_at.desc())).all()
    return {"desde": iso(since), "total": len(obs), "observaciones": [
        {"municipio": o.municipality_id, "source": o.source, "observed_at": iso(o.observed_at),
         "rain_mm_24h": o.rain_mm_24h, "gust_kmh": o.gust_kmh, "temp_c": o.temp_c, "data_mode": o.data_mode,
         "notes": o.notes} for o in obs]}


# ---------------------------------------------------------------- radar / ETA
class Position(BaseModel):
    lat: float = Field(..., ge=-60, le=-15)
    lon: float = Field(..., ge=-80, le=-50)
    time: datetime


class ArrivalIn(BaseModel):
    p1: Position
    p2: Position
    corridor_km: float = Field(25, gt=0, le=200, description="Ancho a cada lado de la trayectoria")
    max_hours: float = Field(12, gt=0, le=48)
    model_config = {"json_schema_extra": {"examples": [{
        "p1": {"lat": -36.9, "lon": -60.3, "time": "2026-11-04T18:00:00Z"},
        "p2": {"lat": -36.6, "lon": -59.9, "time": "2026-11-04T19:00:00Z"}, "corridor_km": 30, "max_hours": 6}]}}


@router.post("/radar/arrival-time", tags=["Radar"], summary="Hora estimada de llegada de una tormenta a cada partido")
def arrival_time(body: ArrivalIn):
    p1 = {"lat": body.p1.lat, "lon": body.p1.lon, "time": to_utc_naive(body.p1.time)}
    p2 = {"lat": body.p2.lat, "lon": body.p2.lon, "time": to_utc_naive(body.p2.time)}
    try:
        res = eta.arrival_times(p1, p2, load_municipalities(), body.corridor_km, body.max_hours)
    except ValueError as exc:
        raise HTTPException(422, str(exc))
    for t in res["targets"]:
        t["arrival_time"] = iso(t["arrival_time"])
    return {"formulas": {"velocidad": "distancia recorrida / tiempo transcurrido",
                         "eta": "distancia restante / velocidad"}, **res}


# ---------------------------------------------------------------- verificación
@router.get("/verification/metrics", tags=["Verificación"], summary="MAE, RMSE y BIAS de lluvia por modelo")
def verification_metrics(session=Depends(get_session)):
    obs = session.scalars(select(Observation).where(Observation.rain_mm_24h.is_not(None))).all()
    pairs: dict[str, list] = {}
    for o in obs:
        fc = session.scalars(select(Forecast).where(
            Forecast.municipality_id == o.municipality_id, Forecast.window_h == 24,
            Forecast.valid_to >= o.observed_at - timedelta(hours=3),
            Forecast.valid_to <= o.observed_at + timedelta(hours=3),
            Forecast.issued_at <= o.observed_at, Forecast.data_mode == o.data_mode)
            .order_by(Forecast.issued_at.desc())).all()
        seen = set()
        for f in fc:
            if f.model not in seen:
                seen.add(f.model)
                pairs.setdefault(f.model, []).append((f.rain_mm, o.rain_mm_24h))
    return {"variable": "lluvia 24 h (mm)", "nota": "Se comparan pronósticos de 24 h cuyo fin coincide (±3 h) "
            "con la hora de la observación. BIAS > 0: el modelo sobreestima.",
            "modelos": {m: metrics(p) for m, p in sorted(pairs.items())}}


# ---------------------------------------------------------------- fuentes
@router.get("/satellite/latest", tags=["Fuentes"], summary="Imagen satelital GOES-Este más reciente (enlace)")
def satellite_latest():
    s = get_settings()
    return {"satellite": "GOES-Este (NOAA)", "sector": "Sur de Sudamérica", "image_url": s.goes_image_url,
            "viewer_url": s.goes_viewer_url, "nota": "Enlace de referencia; ARGWX todavía no procesa la imagen."}


@router.get("/sources", tags=["Fuentes"], summary="Fuentes integradas y su estado")
def sources(session=Depends(get_session)):
    s = get_settings()
    last = {p: run_info(latest_run(session, p, status=None)) for p in ("models", "enso", "smn", "obs")}
    return {"data_mode_config": s.data_mode, "fuentes": [
        {"nombre": "Modelos GFS, ICON, ECMWF, GEM, UKMO (vía Open-Meteo)", "tipo": "pronóstico",
         "activo": True, "modelos": s.list_of("open_meteo_models"), "ultima_corrida": last["models"]},
        {"nombre": "NOAA CPC - ENSO (ONI, Niño 1+2/3/3.4/4, SOI)", "tipo": "clima", "activo": True,
         "ultima_corrida": last["enso"]},
        {"nombre": "SMN - alertas oficiales (CAP/GeoRSS)", "tipo": "alertas", "activo": bool(s.list_of("smn_cap_urls")),
         "urls": s.list_of("smn_cap_urls"), "ultima_corrida": last["smn"]},
        {"nombre": "OpenWeather", "tipo": "pronóstico", "activo": bool(s.openweather_api_key),
         "requiere": "ARGWX_OPENWEATHER_API_KEY"},
        {"nombre": "Meteoblue", "tipo": "pronóstico", "activo": bool(s.meteoblue_api_key),
         "requiere": "ARGWX_METEOBLUE_API_KEY"},
        {"nombre": "Weather Underground (estaciones PWS)", "tipo": "observación",
         "activo": bool(s.wunderground_api_key and s.wunderground_stations),
         "requiere": "ARGWX_WUNDERGROUND_API_KEY y ARGWX_WUNDERGROUND_STATIONS", "ultima_corrida": last["obs"]},
        {"nombre": "GOES-Este (NOAA)", "tipo": "satélite", "activo": True, "modo": "enlace de imagen"},
        {"nombre": "Observaciones manuales", "tipo": "observación", "activo": True,
         "endpoint": "POST /api/v1/observations"},
    ]}
