"""Orquesta los proveedores y guarda todo en la base (cada corrida queda registrada en sync_run)."""
import logging
import threading
import time
from datetime import timedelta

import httpx
from sqlalchemy import select

from app import __version__
from app.config import get_settings
from app.db import new_session
from app.engine.levels import LABEL
from app.models import Alert, EnsoIndex, Forecast, Observation, SyncRun
from app.providers import demo, enso, openmeteo, optional, smn
from app.services.municipalities import load_municipalities
from app.services.runs import latest_run
from app.util import utcnow

log = logging.getLogger("argwx.sync")
LOCK = threading.Lock()
PARTS = ("models", "enso", "smn", "obs")
_last_attempt = {"t": 0.0}


def http_client(settings) -> httpx.Client:
    return httpx.Client(timeout=settings.http_timeout_s, follow_redirects=True,
                        headers={"User-Agent": f"ARGWX/{__version__} (motor meteorologico)"})


def _run(session, provider, mode, fetch, store, allow_empty=False) -> dict:
    run = SyncRun(provider=provider, data_mode=mode, status="running", started_at=utcnow(), records=0)
    session.add(run)
    session.commit()
    try:
        run.records = store(session, run, fetch())
        run.status = "ok" if (run.records > 0 or allow_empty) else "empty"
        session.commit()
    except Exception as exc:
        session.rollback()
        log.warning("Sincronización %s (%s) con error: %s", provider, mode, exc)
        run.status, run.message = "error", f"{type(exc).__name__}: {exc}"[:1000]
    run.finished_at = utcnow()
    session.commit()
    return {"provider": provider, "data_mode": mode, "status": run.status, "records": run.records,
            "message": run.message, "run_id": run.id}


def _store(model_cls, extra=None):
    def store(session, run, rows):
        now = utcnow()
        objs = []
        for r in rows:
            kw = dict(r, data_mode=run.data_mode)
            if model_cls is not Observation:
                kw["run_id"] = run.id
            if model_cls is Forecast:
                kw["issued_at"] = now
            if model_cls is Observation:
                kw["created_at"] = now
            kw.update(extra or {})
            objs.append(model_cls(**kw))
        session.add_all(objs)
        return len(objs)
    return store


def _live_models(munis, settings, client, now) -> list[dict]:
    rows = openmeteo.fetch(munis, settings, client, now)
    for name, fn, key in (("OpenWeather", optional.fetch_openweather, settings.openweather_api_key),
                          ("Meteoblue", optional.fetch_meteoblue, settings.meteoblue_api_key)):
        if key:
            try:
                rows += fn(munis, settings, client, now)
            except Exception as exc:  # un proveedor opcional no bloquea a los demás
                log.warning("%s con error: %s", name, exc)
    return rows


def snapshot_argwx(session, models_run_id: int) -> int:
    """Guarda las alertas propias vigentes (próximas 24 h) en la tabla alert, para historial."""
    from app.services.state import compute_state

    state = compute_state(session)
    now, n = utcnow(), 0
    for e in state["windows"][24]["municipalities"].values():
        a = e["argwx"]
        if a["level"] == "GREEN":
            continue
        session.add(Alert(run_id=models_run_id, municipality_id=e["id"], origin="ARGWX", level=a["level"],
                          hazard=a["hazard"], title=f"ARGWX {LABEL[a['level']]} por {a['hazard']}",
                          description=" ".join(e["drivers"])[:2000], confidence=a["consensus"],
                          issued_at=now, data_mode=state["data_mode"],
                          details={"agreeing_models": a["agreeing_models"], "values": e["values"]}))
        n += 1
    session.commit()
    return n


def _sync(session, settings, parts: set) -> dict:
    munis, now = load_municipalities(), utcnow()
    mode = settings.data_mode.lower()
    results = {}
    with http_client(settings) as client:
        if "models" in parts:
            effective = "demo" if mode == "demo" else "live"
            if effective == "live":
                results["models"] = _run(session, "models", "live",
                                         lambda: _live_models(munis, settings, client, now), _store(Forecast))
                if results["models"]["status"] != "ok" and mode == "auto":
                    results["models_live_attempt"], effective = results.pop("models"), "demo"
            if effective == "demo":
                results["models"] = _run(session, "models", "demo", lambda: demo.forecasts(munis, now),
                                         _store(Forecast))
        else:
            last = latest_run(session, "models")
            effective = last.data_mode if last else ("demo" if mode == "demo" else "live")

        if "enso" in parts:
            fetch = (lambda: demo.enso(now)) if effective == "demo" else (lambda: enso.fetch(settings, client))
            results["enso"] = _run(session, "enso", effective, fetch, _store(EnsoIndex))
        if "smn" in parts:
            fetch = ((lambda: demo.smn_alerts(munis, now)) if effective == "demo"
                     else (lambda: smn.fetch(settings, client, munis)))
            results["smn"] = _run(session, "smn", effective, fetch, _store(Alert, {"origin": "SMN"}),
                                  allow_empty=True)
        if "obs" in parts:
            if effective == "demo":
                recent = session.scalar(select(Observation.id).where(
                    Observation.data_mode == "demo",
                    Observation.observed_at >= now - timedelta(hours=settings.observation_max_age_h)).limit(1))
                if recent is None:
                    results["obs"] = _run(session, "obs", "demo", lambda: demo.observations(munis, now),
                                          _store(Observation))
            elif settings.wunderground_api_key and settings.list_of("wunderground_stations"):
                results["obs"] = _run(session, "obs", "live",
                                      lambda: optional.fetch_wunderground(munis, settings, client),
                                      _store(Observation))
    if results.get("models", {}).get("status") == "ok":
        results["argwx_alerts"] = snapshot_argwx(session, results["models"]["run_id"])
    return {"data_mode": effective, "results": results}


def sync(parts=PARTS, session=None) -> dict:
    settings = get_settings()
    own = session is None
    session = session or new_session()
    try:
        with LOCK:
            _last_attempt["t"] = time.monotonic()
            return _sync(session, settings, set(parts))
    finally:
        if own:
            session.close()


def safe_sync(parts=PARTS) -> None:
    try:
        sync(parts)
    except Exception:  # nunca tumbar el proceso por una sincronización
        log.exception("Sincronización fallida")


def ensure_data(session) -> None:
    """Si todavía no hay pronósticos, sincroniza una vez (o espera a la sincronización en curso)."""
    if latest_run(session, "models") is not None:
        return
    session.rollback()
    if LOCK.locked():
        if LOCK.acquire(timeout=300):
            LOCK.release()
        session.expire_all()
        return
    if time.monotonic() - _last_attempt["t"] < 300 and _last_attempt["t"]:
        return
    sync(session=session)
