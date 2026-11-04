"""Tablas: municipality, sync_run, forecast, alert, enso, observation."""
from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Municipality(Base):
    __tablename__ = "municipality"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    seccion: Mapped[int] = mapped_column(Integer, index=True)
    codigo_electoral: Mapped[str] = mapped_column(String(3))
    conurbano: Mapped[bool] = mapped_column(Boolean, default=False)
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)


class SyncRun(Base):
    """Cada corrida de un proveedor. Sirve para trazabilidad y frescura de datos."""
    __tablename__ = "sync_run"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    provider: Mapped[str] = mapped_column(String(40), index=True)
    data_mode: Mapped[str] = mapped_column(String(10))
    status: Mapped[str] = mapped_column(String(10))
    started_at: Mapped[datetime] = mapped_column(DateTime)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    records: Mapped[int] = mapped_column(Integer, default=0)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)


class Forecast(Base):
    """Todo pronóstico se almacena para verificarlo después contra la observación."""
    __tablename__ = "forecast"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("sync_run.id"), index=True)
    municipality_id: Mapped[str] = mapped_column(ForeignKey("municipality.id"), index=True)
    model: Mapped[str] = mapped_column(String(40))
    window_h: Mapped[int] = mapped_column(Integer)  # 24 = 0-24 h, 48 = 24-48 h, 72 = 48-72 h
    valid_from: Mapped[datetime] = mapped_column(DateTime)
    valid_to: Mapped[datetime] = mapped_column(DateTime)
    rain_mm: Mapped[float | None] = mapped_column(Float, nullable=True)
    gust_kmh: Mapped[float | None] = mapped_column(Float, nullable=True)
    tmax_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    tmin_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    weather_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    data_mode: Mapped[str] = mapped_column(String(10))
    issued_at: Mapped[datetime] = mapped_column(DateTime)


class Alert(Base):
    """Alertas oficiales (origin=SMN) y snapshots de alertas propias (origin=ARGWX)."""
    __tablename__ = "alert"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("sync_run.id"), index=True)
    municipality_id: Mapped[str | None] = mapped_column(ForeignKey("municipality.id"), nullable=True, index=True)
    origin: Mapped[str] = mapped_column(String(20))
    level: Mapped[str] = mapped_column(String(10))
    hazard: Mapped[str | None] = mapped_column(String(40), nullable=True)
    title: Mapped[str] = mapped_column(String(300))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    valid_from: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    valid_to: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    issued_at: Mapped[datetime] = mapped_column(DateTime)
    data_mode: Mapped[str] = mapped_column(String(10))
    external_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    details: Mapped[dict | None] = mapped_column(JSON, nullable=True)


class EnsoIndex(Base):
    __tablename__ = "enso"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("sync_run.id"), index=True)
    index_name: Mapped[str] = mapped_column(String(10), index=True)  # ONI, NINO12, NINO3, NINO34, NINO4, SOI
    period: Mapped[str] = mapped_column(String(20))
    period_date: Mapped[date] = mapped_column(Date)
    value: Mapped[float] = mapped_column(Float)
    sst: Mapped[float | None] = mapped_column(Float, nullable=True)
    data_mode: Mapped[str] = mapped_column(String(10))


class Observation(Base):
    __tablename__ = "observation"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    municipality_id: Mapped[str] = mapped_column(ForeignKey("municipality.id"), index=True)
    source: Mapped[str] = mapped_column(String(60))
    observed_at: Mapped[datetime] = mapped_column(DateTime)
    rain_mm_24h: Mapped[float | None] = mapped_column(Float, nullable=True)
    gust_kmh: Mapped[float | None] = mapped_column(Float, nullable=True)
    temp_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    data_mode: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime)
