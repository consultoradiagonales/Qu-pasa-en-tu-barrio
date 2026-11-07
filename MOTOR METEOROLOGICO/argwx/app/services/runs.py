from sqlalchemy import select

from app.models import SyncRun


def latest_run(session, provider: str, mode: str | None = None, status: str | None = "ok") -> SyncRun | None:
    q = select(SyncRun).where(SyncRun.provider == provider)
    if status:
        q = q.where(SyncRun.status == status)
    if mode:
        q = q.where(SyncRun.data_mode == mode)
    return session.scalars(q.order_by(SyncRun.id.desc()).limit(1)).first()


def run_info(run: SyncRun | None) -> dict | None:
    from app.util import iso

    if run is None:
        return None
    return {"id": run.id, "provider": run.provider, "data_mode": run.data_mode, "status": run.status,
            "started_at": iso(run.started_at), "finished_at": iso(run.finished_at), "records": run.records,
            "message": run.message}
