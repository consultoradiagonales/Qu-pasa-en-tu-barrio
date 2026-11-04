"""Configuración por variables de entorno (prefijo ARGWX_). Nunca se hardcodean secretos."""
from functools import lru_cache
from urllib.parse import quote

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ARGWX_", env_file=".env", extra="ignore")

    env: str = "development"                      # development | production
    database_url: str = "sqlite:///./argwx.db"    # PostgreSQL en Docker; SQLite para correr sin infraestructura
    db_password_file: str | None = None           # Docker secret: reemplaza __PASSWORD__ en database_url
    data_mode: str = "auto"                       # live | demo | auto (live y, si falla, demo)
    sync_on_startup: bool = True
    scheduler_enabled: bool = True
    sync_interval_min: int = 180
    http_timeout_s: float = 30.0
    admin_token: str | None = None                # protege los endpoints de escritura
    cors_origins: str = "*"
    min_agreeing_models: int = 2                  # ninguna alerta depende de un único modelo
    observation_max_age_h: int = 6

    # Modelos numéricos vía Open-Meteo (GFS, ICON, ECMWF, GEM, UKMO)
    open_meteo_url: str = "https://api.open-meteo.com/v1/forecast"
    open_meteo_api_key: str | None = None         # uso comercial: plan pago de Open-Meteo
    open_meteo_models: str = "gfs_seamless,icon_seamless,ecmwf_ifs025,gem_seamless,ukmo_seamless"
    # ENSO (NOAA CPC)
    oni_url: str = "https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt"
    nino_weekly_url: str = "https://www.cpc.ncep.noaa.gov/data/indices/wksst9120.for"
    soi_url: str = "https://www.cpc.ncep.noaa.gov/data/indices/soi"
    # SMN: feed CAP oficial (índice RSS con un CAP 1.2 por alerta). Admite varios separados por coma.
    smn_cap_urls: str = "https://ssl.smn.gob.ar/CAP/AR.php"
    # Proveedores opcionales: se activan solo si hay API key
    openweather_api_key: str | None = None
    meteoblue_api_key: str | None = None
    wunderground_api_key: str | None = None
    wunderground_stations: str = ""               # IDs de estaciones PWS separados por coma
    # Satélite GOES-Este (enlaces de referencia, sin procesamiento)
    goes_image_url: str = "https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/GEOCOLOR/latest.jpg"
    goes_viewer_url: str = "https://www.star.nesdis.noaa.gov/GOES/sector.php?sat=G19&sector=ssa"

    def resolved_database_url(self) -> str:
        url = self.database_url
        if self.db_password_file and "__PASSWORD__" in url:
            with open(self.db_password_file, encoding="utf-8") as fh:
                url = url.replace("__PASSWORD__", quote(fh.read().strip(), safe=""))
        return url

    def list_of(self, field: str) -> list[str]:
        return [x.strip() for x in (getattr(self, field) or "").split(",") if x.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
