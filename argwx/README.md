# ARGWX · Motor meteorológico (MVP)

Alertas meteorológicas para los **135 municipios de la Provincia de Buenos Aires**, calculadas por
**consenso de varios modelos**, sumando las alertas oficiales del SMN y las observaciones reales.
Es la primera pieza de la plataforma ARGWX (Argentina Weather Exchange), pensada para integrarse después a ConDi.

Los pronósticos **no** se calculan con IA generativa: solo reglas físicas/estadísticas, umbrales y consenso.

---

## Probarlo

### Opción A · GitHub Codespaces (sin instalar nada)
1. En GitHub: **Code → Codespaces → Create codespace** sobre la rama `claude/weather-engine-mvp-jafv4d`.
2. Se instalan las dependencias y arranca la API sola. Se abre el puerto **8000**:
   - Panel con mapa: `/`
   - API interactiva (Swagger): `/docs`

### Opción B · Docker (API + PostgreSQL)
```bash
cd argwx
make dev-up          # crea .env con clave aleatoria y levanta todo
make api-health      # estado
make resumen         # resumen de alertas en consola
```
Abrir http://localhost:8000

### Opción C · Python local (SQLite, sin Docker)
```bash
cd argwx
pip install -r requirements.txt
make demo   # escenario SIMULADO, funciona sin internet
make run    # datos reales (si una fuente falla, cae a simulado y lo avisa en pantalla)
```

---

## Qué se ve

- **Panel web** (`/`): mapa de los 135 partidos coloreado por nivel, ventanas *próximas 24 h / 24-48 h / 48-72 h*,
  zoom al AMBA, resumen por **sección electoral**, estado ENSO y el detalle de cada municipio con el “voto” de cada modelo.
- **API REST** (`/api/v1`): todo lo anterior en JSON, para integrar con ConDi u otros sistemas.
- Si los datos son simulados, el panel muestra un cartel **DEMO · SIMULADO** y cada respuesta trae `"data_mode": "demo"`.

---

## Cómo decide la alerta

1. Para cada municipio se toma el pronóstico de **5 modelos**: GFS (EE. UU.), ICON (Alemania), ECMWF (Europa),
   GEM (Canadá) y UKMO (Reino Unido).
2. Cada modelo “vota” un nivel según **umbrales** de lluvia, ráfagas, calor y tormentas.
3. **Consenso = modelos que coinciden / modelos analizados.** Un nivel se emite solo si lo alcanzan
   **al menos 2 modelos y al menos la mitad**. Ninguna alerta depende de un único modelo.
   Si un modelo solo marca algo más grave, se informa como *señal no confirmada*.
4. Se suma la **alerta oficial del SMN** y las **observaciones reales**. **La observación prevalece sobre el modelo.**
5. Nivel final = el más alto entre consenso, SMN y observación, con su **confianza**:

| Consenso | Confianza |
|---|---|
| 0-40 % | Baja |
| 41-70 % | Media |
| 71-85 % | Alta |
| 86-100 % | Muy alta |

### Niveles

| Nivel | Significado |
|---|---|
| Verde | Sin fenómenos significativos |
| Amarilla | Posibles inconvenientes puntuales |
| Naranja | Fenómenos potencialmente peligrosos |
| Roja | Fenómenos severos |
| Púrpura | Evento extremo (granizo severo, inundaciones excepcionales, fenómenos destructivos) |

### Umbrales iniciales (propios de ARGWX, a calibrar)

| Variable (ventana de 24 h) | Amarilla | Naranja | Roja | Púrpura |
|---|---|---|---|---|
| Lluvia acumulada (mm) | 30 | 60 | 100 | 150 |
| Ráfaga máxima (km/h) | 60 | 80 | 100 | 120 |
| Temperatura máxima (°C) | 36 | 39 | 42 | – |
| Tormenta (código WMO) | 95 | 96-98 | 99 | – |

Son valores de partida definidos para este MVP, **no son los umbrales oficiales del SMN**.
Se editan en `app/engine/thresholds.py` y se consultan en `GET /api/v1/alerts/thresholds`.

---

## Endpoints principales

| Método y ruta | Qué devuelve |
|---|---|
| `GET /api/v1/alerts/current?ventana=24&nivel_min=amarilla&seccion=5` | Alerta de cada municipio (filtros opcionales) |
| `GET /api/v1/zonas` | Resumen por sección electoral (8 zonas) |
| `GET /api/v1/municipios/{id o nombre}` | Detalle: votos por modelo, SMN, observación, explicación |
| `GET /api/v1/province/summary` | Resumen provincial (formato del entregable MVP) |
| `GET /api/v1/forecast/rain?model=GFS` | Lluvia pronosticada por municipio |
| `GET /api/v1/consensus/current` | Consenso multimodelo detallado |
| `GET /api/v1/enso/current` · `/enso/history` | El Niño / Neutral / La Niña (ONI, Niño 3.4, SOI) |
| `GET /api/v1/alerts/smn` | Alertas oficiales del SMN asignadas a municipios |
| `POST /api/v1/observations` | Cargar una observación real (escala la alerta si corresponde) |
| `POST /api/v1/radar/arrival-time` | Hora estimada de llegada de una tormenta a cada municipio |
| `GET /api/v1/verification/metrics` | MAE, RMSE y BIAS por modelo contra observaciones |
| `GET /api/v1/sources` | Fuentes integradas y su estado |
| `GET /health` · `/health/live` · `/health/ready` · `/health/deep` · `/health/data-freshness` | Salud del sistema |

Ejemplo de respuesta de `GET /api/v1/province/summary`:
```json
{"province": "Buenos Aires", "enso_phase": "EL_NINO", "rain_mm": 35.4, "alert_level": "YELLOW",
 "forecast_source": "GFS", "confidence": 0.6, "...": "más campos de detalle"}
```

Cargar una observación (con `ARGWX_ADMIN_TOKEN` configurado, enviar el header `X-ARGWX-Token`):
```bash
curl -X POST localhost:8000/api/v1/observations -H 'Content-Type: application/json' \
     -d '{"municipio": "La Plata", "rain_mm_24h": 85, "source": "Estación municipal"}'
```

---

## Fuentes de datos

| Fuente | Aporta | Estado |
|---|---|---|
| GFS, ICON, ECMWF, GEM, UKMO vía [Open-Meteo](https://open-meteo.com) | Pronóstico horario (lluvia, ráfagas, temperatura, tormentas) | Implementado |
| NOAA CPC | ENSO: ONI, Niño 1+2 / 3 / 3.4 / 4 semanales, SOI | Implementado |
| SMN | Alertas oficiales (CAP 1.2 o GeoRSS) | Implementado; **URL del feed a confirmar** (`ARGWX_SMN_CAP_URLS`) |
| OpenWeather, Meteoblue | Pronóstico adicional que entra al consenso | Beta; requiere API key |
| Weather Underground | Observaciones de estaciones personales | Beta; requiere API key e IDs de estación |
| GOES-Este (NOAA) | Imagen satelital | Enlace de referencia (sin procesamiento) |
| Observaciones manuales | Datos de estaciones propias, municipios, etc. | Implementado |
| Radar | Estimación de llegada (velocidad = distancia / tiempo; ETA = distancia restante / velocidad) | Calculadora; sin ingesta de radar todavía |

**Importante para uso con clientes:** el plan gratuito de Open-Meteo es para uso **no comercial**.
Para un servicio comercial hay que contratar su plan y cargar `ARGWX_OPEN_METEO_API_KEY`.

### Modos de datos (`ARGWX_DATA_MODE`)
- `live`: solo datos reales.
- `demo`: escenario simulado (un sistema de tormentas que cruza la provincia), para mostrar el motor sin internet.
- `auto` (por defecto): intenta datos reales y, si los modelos no responden, usa el simulado y lo avisa.

---

## Qué está verificado y qué no

**Verificado**
- 38 tests automáticos (motor, parsers, API) pasan, también en GitHub Actions.
- La API funciona con **SQLite** y con **PostgreSQL 16** (incluida la clave por archivo, como Docker Secret).
- La imagen Docker se construye en GitHub Actions.
- **Fuentes reales** (job `live-sources` del CI, 4/11/2026): Open-Meteo devolvió los 5 modelos para los
  135 municipios y las 3 ventanas; NOAA CPC devolvió ONI, índices Niño semanales y SOI.
- El panel se probó en navegador de escritorio y de celular.
- Los 135 partidos y sus límites salen de fuentes públicas (ver `app/data/README.md`).

**No verificado todavía**
- **SMN:** el feed respondió con formato válido pero sin alertas asignadas a partidos bonaerenses en ese momento.
  Falta ver una alerta real vigente para confirmar la asignación a municipios (el log del CI indica qué feed respondió).
- `docker compose` completo (API + PostgreSQL + Nginx) no se ejecutó; la imagen sí se construye.
- OpenWeather, Meteoblue y Weather Underground no se probaron: requieren claves.
- Los umbrales son iniciales y deben calibrarse con la verificación estadística.

---

## Estructura

```
argwx/
  app/
    main.py            arranque FastAPI + sincronización periódica
    config.py          variables de entorno (prefijo ARGWX_)
    models.py          tablas: municipality, forecast, alert, enso, observation, sync_run
    engine/            umbrales, consenso, niveles, ETA, verificación (sin dependencias externas)
    providers/         Open-Meteo, NOAA ENSO, SMN, opcionales y escenario demo
    services/          sincronización y cálculo del estado actual
    api/               endpoints /health y /api/v1
    static/index.html  panel web
    data/              135 partidos (puntos y límites simplificados)
  tests/               pytest
  docker-compose*.yml  base, desarrollo y producción (Nginx + Docker Secrets)
  Makefile             make help
```

## Configuración

Todo se configura con variables de entorno (ver `.env.example`). Nunca se guardan claves en el código.
En producción: `ARGWX_ENV=production`, `ARGWX_ADMIN_TOKEN` obligatorio para escribir, y la clave de la base en
`secrets/db_password.txt` (`make prod-up`).

## Próximos pasos sugeridos

- Confirmar el feed oficial del SMN y contratar Open-Meteo comercial.
- Ingesta de observaciones del SMN y de radar; procesamiento de imágenes GOES.
- Migraciones con Alembic; Redis/Celery si crece la carga.
- Calibrar umbrales por zona con la verificación (MAE/RMSE/BIAS) y ranking de modelos por municipio.
- Extender a todo el país (el motor ya trabaja con cualquier lista de puntos).
- Integración con ConDi vía esta API (CORS configurable).
