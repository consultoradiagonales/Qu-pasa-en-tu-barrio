"""Healthchecks: /health, /health/live, /health/ready, /health/deep, /health/data-freshness."""
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import func, select, text

from app import __version__
from app.config import get_settings
from app.db import get_session
from app.models import Municipality
from app.services.runs import latest_run, run_info
from app.services.sync import http_client
from app.util import utcnow

router = APIRouter(prefix="/health", tags=["Salud del sistema"])
MAX_AGE_H = {"models": 12, "enso": 24 * 10, "smn": 6}


def _db(session) -> tuple[bool, int, str | None]:
    try:
        session.execute(text("SELECT 1"))
        return True, session.scalar(select(func.count(Municipality.id))) or 0, None
    except Exception as exc:
        return False, 0, f"{type(exc).__name__}: {exc}"[:300]


def freshness(session) -> dict:
    now, out = utcnow(), {}
    current = latest_run(session, "models")
    mode = current.data_mode if current else None
    for provider, max_h in MAX_AGE_H.items():
        ok = latest_run(session, provider, mode if provider != "models" else None)
        last_any = latest_run(session, provider, status=None)
        age = round((now - ok.finished_at).total_seconds() / 3600, 2) if ok and ok.finished_at else None
        out[provider] = {"status": "missing" if age is None else ("fresh" if age <= max_h else "stale"),
                         "age_hours": age, "max_age_hours": max_h, "last_ok": run_info(ok),
                         "last_attempt": run_info(last_any)}
    return out


@router.get("/live", summary="El proceso está vivo")
def live():
    return {"status": "ok"}


@router.get("/ready", summary="Listo para atender (base de datos + 135 municipios)")
def ready(session=Depends(get_session)):
    ok, n, err = _db(session)
    body = {"status": "ok" if ok and n == 135 else "not_ready", "database": ok, "municipalities": n, "error": err}
    return JSONResponse(body, status_code=200 if body["status"] == "ok" else 503)


@router.get("", summary="Estado general")
def health(session=Depends(get_session)):
    s = get_settings()
    ok, n, err = _db(session)
    fr = freshness(session) if ok else {}
    current = latest_run(session, "models") if ok else None
    degraded = not ok or any(v["status"] != "fresh" for v in fr.values())
    return {"status": "degraded" if degraded else "ok", "version": __version__, "env": s.env,
            "data_mode_config": s.data_mode, "data_mode_current": current.data_mode if current else None,
            "database": "ok" if ok else err, "municipalities": n,
            "providers": {k: v["status"] for k, v in fr.items()}}


@router.get("/deep", summary="Chequeo profundo: base + conectividad con las fuentes externas")
def deep(session=Depends(get_session)):
    s = get_settings()
    ok, n, err = _db(session)
    targets = {"open_meteo": f"{s.open_meteo_url}?latitude=-34.9&longitude=-57.95&hourly=temperature_2m&forecast_days=1",
               "noaa_cpc_oni": s.oni_url}
    targets.update({f"smn_{i}": u for i, u in enumerate(s.list_of("smn_cap_urls"))})
    checks = {}
    with http_client(s) as client:
        client.timeout = 8
        for name, url in targets.items():
            try:
                r = client.get(url)
                checks[name] = {"url": url, "http_status": r.status_code, "ok": r.status_code < 400}
            except Exception as exc:
                checks[name] = {"url": url, "ok": False, "error": f"{type(exc).__name__}: {exc}"[:200]}
    return {"status": "ok" if ok and all(c["ok"] for c in checks.values()) else "degraded",
            "database": {"ok": ok, "municipalities": n, "error": err}, "sources": checks}


@router.get("/data-freshness", summary="Antigüedad de los datos por proveedor")
def data_freshness(session=Depends(get_session)):
    return {"checked_at": utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"), "providers": freshness(session)}
