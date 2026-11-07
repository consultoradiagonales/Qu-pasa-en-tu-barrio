"""Conexión a base de datos (SQLAlchemy 2). PostgreSQL en Docker, SQLite como alternativa local."""
from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings


class Base(DeclarativeBase):
    pass


_engine = None
SessionLocal = sessionmaker(autoflush=False, expire_on_commit=False)


def get_engine():
    global _engine
    if _engine is None:
        url = get_settings().resolved_database_url()
        kw = {"pool_pre_ping": True}
        if url.startswith("sqlite"):
            kw["connect_args"] = {"check_same_thread": False, "timeout": 30}
        _engine = create_engine(url, **kw)
        if url.startswith("sqlite"):
            event.listen(_engine, "connect", _sqlite_pragmas)
        SessionLocal.configure(bind=_engine)
    return _engine


def _sqlite_pragmas(dbapi_conn, _record):
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA foreign_keys=ON")
    cur.close()


def reset_engine():
    global _engine
    if _engine is not None:
        _engine.dispose()
    _engine = None


def init_db():
    from app import models  # noqa: F401  registra las tablas

    Base.metadata.create_all(get_engine())


def new_session() -> Session:
    get_engine()
    return SessionLocal()


def get_session():
    with new_session() as s:
        yield s
