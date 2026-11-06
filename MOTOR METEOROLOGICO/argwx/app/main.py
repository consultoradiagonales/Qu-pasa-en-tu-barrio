"""ARGWX - motor meteorológico. Arranque de la API FastAPI."""
import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app import __version__
from app.api import health, v1
from app.config import get_settings
from app.db import init_db, new_session
from app.services.municipalities import seed
from app.services.sync import safe_sync

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
STATIC = Path(__file__).parent / "static"

DESCRIPTION = """
**ConDi** (motor ARGWX) genera alertas meteorológicas para los **135 partidos de la Provincia de Buenos Aires**.

Cómo decide (sin IA generativa):
1. Toma el pronóstico de **5 modelos** (GFS, ICON, ECMWF, GEM, UKMO) para cada partido.
2. Cada modelo "vota" un nivel según umbrales de lluvia, ráfagas, calor y tormentas.
3. **Consenso** = modelos coincidentes / modelos analizados. Ninguna alerta depende de un solo modelo.
4. Se suma la alerta **oficial del SMN** y las **observaciones reales** (la observación prevalece).
5. Resultado: Verde, Amarilla, Naranja, Roja o Púrpura, con su nivel de confianza.

Empezá por `GET /api/v1/alerts/current` o abrí el panel en `/`.
"""


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    init_db()
    with new_session() as s:
        seed(s)
    tasks = []
    if settings.sync_on_startup:
        tasks.append(asyncio.create_task(asyncio.to_thread(safe_sync)))
    if settings.scheduler_enabled:
        tasks.append(asyncio.create_task(_scheduler(settings.sync_interval_min)))
    yield
    for t in tasks:
        t.cancel()


async def _scheduler(minutes: int):
    while True:
        await asyncio.sleep(max(minutes, 5) * 60)
        await asyncio.to_thread(safe_sync)


app = FastAPI(title="ConDi - Motor meteorológico (ARGWX)", version=__version__, description=DESCRIPTION, lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=get_settings().list_of("cors_origins") or ["*"],
                   allow_methods=["*"], allow_headers=["*"])
app.include_router(health.router)
app.include_router(health.router, prefix="/api/v1", include_in_schema=False)
app.include_router(v1.router)
app.mount("/static", StaticFiles(directory=STATIC), name="static")


@app.get("/", include_in_schema=False)
def dashboard():
    return FileResponse(STATIC / "index.html")
