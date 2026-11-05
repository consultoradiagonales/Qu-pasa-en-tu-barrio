from datetime import datetime, timezone


def utcnow() -> datetime:
    """UTC sin tzinfo: así se guarda en la base (compatible PostgreSQL/SQLite)."""
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def to_utc_naive(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).replace(tzinfo=None) if dt.tzinfo else dt


def iso(dt: datetime | None) -> str | None:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None
