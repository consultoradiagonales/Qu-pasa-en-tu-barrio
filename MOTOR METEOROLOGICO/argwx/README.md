# ConDi · Motor meteorológico (MVP, motor ARGWX)

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

## Marca y cliente

El sistema se presenta como **ConDi · inteligencia territorial** (logo tomado del sitio publicado del repo).
El logo del cliente (Cámara de Diputados de la Provincia de Buenos Aires, provisto por ConDi) está en
`app/site/img/cliente.png`. Para cambiarlo, reemplazar ese archivo (PNG con fondo transparente).

## Dashboard público (sin instalar nada)

**https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/** — pensado para celular (iOS y Android) y compu.

**En vivo** (mapa interactivo: Buenos Aires, Argentina o Sudamérica):
- **Tormentas en movimiento:** círculos semitransparentes del color de la alerta con la zona probable de cada
  tormenta hora por hora, flecha de dirección, recorrido previsto y lista de municipios por los que pasaría con
  la hora estimada. La opacidad indica cuántos de los 5 modelos coinciden (probabilidad); si el círculo crece, la
  tormenta se amplía o los modelos dudan más; si se achica, se debilita.
- **Viento:** flechas animadas que muestran hacia dónde sopla (color por velocidad) y partículas en movimiento.
- **Lluvia:** íconos de nube con rayo (tormenta eléctrica), gotas grandes (lluvia fuerte) y gotitas (lluvia débil).
- **Línea de tiempo:** botón ▶ para animar las próximas 12 horas.
- **Alertas oficiales del SMN** sombreadas y botón **📍 Mi ubicación**. (La capa satelital GOES-Este de NASA GIBS
  quedó desactivada: en las pruebas no respondió de forma estable.)

**Alertas:** alertas del SMN y alertas ARGWX de los 135 municipios (24/48/72 h).
**El Niño:** fase actual, ONI desde 1950 y efecto histórico en la lluvia bonaerense (ERA5 desde 1981).
**Crecidas:** nivel de crecida de los ríos, arroyos y canales de la provincia para los próximos 3 días, partidos y
localidades sobre cada curso, buscador y botón "Ver en el mapa" (el cauce se pinta del color de la alerta). Incluye
la tarjeta **🌱 Suelo y siembra** (humedad del suelo y lluvia de 30 días por partido). Ver "Crecidas" más abajo.

**En el celular:** la barra superior se contrae al desplazar la página o mover el mapa; las capas se despliegan con
el botón "Capas" y el detalle de cada punto se abre en un panel inferior.

**Mapa base:** OpenStreetMap, sin clave (con límites provinciales propios encima). Para uso intensivo o comercial
conviene contratar un proveedor de mapas (sus servidores públicos son para uso liviano).

**Qué significa "en vivo":** el navegador consulta directamente a Open-Meteo los 5 modelos (GFS, ICON, ECMWF, GEM,
UKMO) y se actualiza cada 15 minutos. Es pronóstico numérico, **no radar ni observación**. Si Open-Meteo no responde,
usa la última copia guardada por el servidor y lo indica arriba ("Copia del servidor"). El seguimiento de tormentas
se calcula en el navegador (`app/site/tracking.js`) con umbrales horarios propios iniciales: tormenta si hay código
WMO de tormenta o ≥ 4 mm/h; naranja ≥ 10 mm/h o ráfagas ≥ 80 km/h; roja ≥ 20 mm/h o ≥ 100 km/h; púrpura ≥ 40 mm/h
o ≥ 120 km/h.

Lo publica el workflow `.github/workflows/argwx-dashboard.yml` en la rama `gh-pages`, **solo dentro de la carpeta
`argwx/`** (no toca la app web publicada en esa rama). Corre en cada cambio del código y, una vez que esté en `main`,
cada hora (alertas del SMN cada hora; el resto se reutiliza hasta 3 horas para no saturar las fuentes).

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

Todas gratuitas y sin clave, probadas desde GitHub con `scripts/probe_sources.py` (4/11/2026):

| Fuente | Aporta | Uso en ConDi |
|---|---|---|
| Open-Meteo: GFS, ICON, ECMWF IFS, **ECMWF IA (AIFS)**, GEM, UKMO, **JMA**, **ARPEGE**, **CMA** | Pronóstico horario de 9 modelos | Consenso de alertas en los 135 municipios (el mapa en vivo usa 5 para no saturar) |
| Open-Meteo Ensemble (ECMWF, 51 escenarios) | Probabilidades reales | Probabilidad de ≥10/30/60 mm por zona |
| SMN · alertas CAP (`ssl.smn.gob.ar/CAP/AR.php`) | Alertas oficiales con polígonos | Capa del mapa y nivel final de cada municipio |
| SMN · datos abiertos (tiempo presente + estaciones) | Observación real en ~120 estaciones | Capa de estaciones; tormenta o granizo observado **eleva la alerta** (la observación prevalece) |
| RainViewer | Radar de los últimos minutos (donde hay cobertura) | Capa de radar |
| NOAA STAR · GOES-19 | Imagen satelital cada 10 min | Tarjeta satelital |
| GloFAS (Copernicus) vía Open-Meteo Flood | Caudal de ríos pronosticado e histórico desde 1984 | Estaciones de referencia (Paraná, Luján, Salado, Quequén, Negro) y caudal en hasta 400 puntos de cauces |
| OpenStreetMap · Overpass API | Ríos, arroyos y canales con nombre, y localidades (ODbL) | Red hídrica de la provincia para las crecidas |
| INA · Sistema de Alerta Hidrológico (API alerta5, pública) | Alturas observadas de escalas de Prefectura Naval y de la Red Hidrológica Nacional, con niveles oficiales de alerta y evacuación | Escalas en el mapa; la altura observada prevalece en las crecidas |
| Open-Meteo (modelo de mejor ajuste / ICON / ECMWF / GFS) | Lluvia de los últimos 30 días y humedad del suelo | Suelo y siembra; suelo cargado eleva la crecida |
| Open-Meteo Marine | Altura de olas | Costa atlántica bonaerense |
| CAMS (Copernicus) vía Open-Meteo Air Quality | Índice UV y PM2.5 | Ambiente por municipio |
| NOAA CPC | ONI, Niño 1+2/3/3.4/4, SOI | El Niño |
| ERA5 (Copernicus) vía Open-Meteo Archive | Lluvia histórica 1981-hoy | Efecto de El Niño en la provincia |
| OpenStreetMap | Mapa base | Fondo del mapa |

Disponibles pero no usadas: MET Noruega (repite ECMWF). No respondieron: KMA (Corea), BOM (Australia),
GraphCast; capa satelital de NASA GIBS (inestable).

**Con registro (gratis para empezar, pagas al escalar):** OpenWeather, Meteoblue y Weather Underground ya tienen
conector (`ARGWX_OPENWEATHER_API_KEY`, `ARGWX_METEOBLUE_API_KEY`, `ARGWX_WUNDERGROUND_API_KEY`); se cargan como
*secrets* del repositorio en GitHub y el motor los suma al consenso.

**Importante para uso con clientes:** el plan gratuito de Open-Meteo es para uso **no comercial**.
Para un servicio comercial hay que contratar su plan y cargar `ARGWX_OPEN_METEO_API_KEY`.

### Modos de datos (`ARGWX_DATA_MODE`)
- `live`: solo datos reales.
- `demo`: escenario simulado (un sistema de tormentas que cruza la provincia), para mostrar el motor sin internet.
- `auto` (por defecto): intenta datos reales y, si los modelos no responden, usa el simulado y lo avisa.

### Crecidas de ríos y arroyos (`app/providers/hydro.py`)

1. **Red hídrica:** ríos, arroyos y canales con nombre de OpenStreetMap dentro de la provincia (se descarta el Río
   de la Plata, que es un estuario). Los tramos con el mismo nombre que se tocan forman un curso; se listan los de más
   de 5 km (ríos) u 8 km (arroyos y canales). Para cada curso: partidos que cruza y localidades a menos de 4 km del
   cauce. Se recalcula una vez por mes.
2. **Lluvia en la cuenca:** lluvia prevista a 72 h (suma de las medianas diarias de los 9 modelos) promediada en los
   partidos que cruza el curso. Amarilla ≥ 40 mm, Naranja ≥ 70, Roja ≥ 110; sube un nivel si en los últimos 30 días
   llovieron 150 mm o más (suelo cargado).
3. **Caudal (GloFAS):** en hasta 400 puntos sobre los cauces de más de 15 km se compara el máximo esperado de los
   próximos 7 días (mediana del ensamble) con el caudal típico de las últimas 3 semanas: Amarilla ≥ 2×, Naranja ≥ 4×,
   Roja ≥ 8×, con una subida mínima de 5 m³/s. Si el caudal típico es menor a 1 m³/s, GloFAS no representa ese cauce
   y solo cuenta la lluvia. **Como en el consenso de alertas, una sola fuente no alcanza para Naranja o Roja:** si la
   subida de GloFAS no la confirma la lluvia (≥ 40 mm previstos, ≥ 50 mm en la última semana o ≥ 150 mm en 30 días),
   se informa como Amarilla. Motivo: tras una semana con lluvias moderadas, los arroyos chicos parten de caudales muy
   bajos y la relación con las últimas 3 semanas se infla (en la primera corrida real dio 8 a 17 veces con 26-48 mm
   de lluvia en la semana).
4. **Puntos de referencia GloFAS:** en Paraná, Luján, Salado, Quequén Grande y Negro se usa la comparación con la
   historia 1984-hoy del modelo (p90, p98 y máximo) en lugar de los puntos de la red, que en ríos anchos o en el delta
   pueden caer fuera del cauce principal. Son celdas del modelo, no estaciones de aforo. El Negro no está
   en la red de OpenStreetMap de la provincia (su cauce es el límite), así que figura solo con su punto de referencia.
5. **Alturas observadas:** si una escala oficial sobre el curso (mismo río, a menos de 5 km del cauce) supera su nivel
   de alerta, el curso queda al menos en Naranja; si supera el de evacuación, en Roja. La observación prevalece.
6. El nivel del curso es el mayor de todos. Si tiene alerta, se listan todos los partidos que cruza (primero
   donde está la señal) y sus localidades ribereñas.

**Límites, dicho claro:** los umbrales son iniciales y propios, hay que calibrarlos con registros de crecidas
(Autoridad del Agua, INA). GloFAS funciona mejor en ríos grandes; en arroyos chicos y en la llanura del Salado, donde
el agua se mueve lento y se desborda en bajos, pesa más el criterio de lluvia. La humedad del suelo se informa en
bandas orientativas (seco, adecuado, húmedo, muy húmedo) y no sube por sí sola el nivel de crecida. "Localidad a menos de 4 km" es una
referencia de cercanía, no un mapa de zonas inundables. La humedad del suelo es un valor de modelo (orientativo), no
una medición en el lote.

### Base histórica pública y probabilidades calibradas (`app/providers/historico.py`, `app/engine/calibration.py`)

Se publica en `data/historico/` del dashboard (CSV y JSON, descargables desde la pestaña Alertas) y se actualiza sola en
cada corrida, en forma incremental:

| Tabla | Qué tiene | Fuente |
|---|---|---|
| `lluvia_era5_diaria.csv` | Lluvia diaria desde 1981 en un punto por sección electoral | ERA5 (Copernicus/ECMWF) vía Open-Meteo |
| `verificacion_modelos.csv` | Lluvia pronosticada por los 9 modelos con 1, 2 y 3 días de anticipación y la observada (ERA5), desde el 30/9/2025 | Corridas anteriores vía Open-Meteo |
| `alertas_smn.csv` | Registro de cada alerta oficial del SMN leída (fenómeno, nivel, vigencia, zonas) | API CAP del SMN |
| `smn_horarios_AAAA-MM.csv` | Datos horarios de las estaciones del SMN en la provincia y CABA (temperatura, humedad, presión, viento) | Datos abiertos del SMN |
| `pronosticos_condi_AAAA-MM.csv` | Lo que pronosticó ConDi para cada partido, una vez por día | ConDi |
| `rios_observados_AAAA-MM.csv` | Alturas de los ríos en escalas de la provincia, con alerta y evacuación | Prefectura Naval / Red Hidrológica Nacional vía INA |
| `climatologia_lluvia.json` | Frecuencia histórica de lluvias por mes y percentiles | Cálculo sobre ERA5 |
| `calibracion.json` | Aciertos y falsas alarmas de cada modelo; probabilidad calibrada | Cálculo sobre la verificación |

**Probabilidad calibrada:** para cada partido y ventana se cuenta cuántos modelos pronostican 10, 30 o 60 mm o más, y se
informa con qué frecuencia ocurrió eso en la base (por ejemplo: "cuando más de la mitad de los modelos pronosticó 30 mm
o más, ocurrió en el X % de los casos"). Si hay menos de 10 casos se marca "pocos casos". La "verdad" es ERA5 (un
reanálisis, no un pluviómetro): suaviza tormentas locales, pero es la misma referencia para todos los modelos.

**Fuentes probadas y descartadas (4/11/2026, desde GitHub):** el archivo "alertas de 365 días" del SMN en datos.gob.ar
se publica vacío; la API JSON del SMN (`ws.smn.gob.ar`) respondió 503 y la nueva (`ws1.smn.gob.ar`) pide autorización
(401); los datos horarios del SMN no incluyen lluvia; la página de alturas de Prefectura no respondió desde GitHub, pero esas mismas escalas llegan por la API pública del
INA (4695 estaciones y 1144 series de altura verificadas).
Las alertas oficiales siguen llegando por la API CAP del SMN (la que el SMN registra ante la OMM).

---

## Qué está verificado y qué no

**Verificado**
- 63 tests automáticos (motor, parsers, API, crecidas, base histórica, calibración e INA) pasan, también en GitHub Actions.
- **Crecidas con datos reales** (4/11/2026): Overpass devolvió la red hídrica de la provincia (527 cursos con nombre:
  49 ríos, 65 canales y 413 arroyos; el Salado mide 640 km en OpenStreetMap y cruza 16 partidos) y Open-Meteo la
  humedad del suelo de los 135 partidos. En esa primera corrida la consulta de caudales GloFAS sobre los cauces se
  cortó por un tiempo de espera de conexión; se agregaron reintentos.
- La API funciona con **SQLite** y con **PostgreSQL 16** (incluida la clave por archivo, como Docker Secret).
- La imagen Docker se construye en GitHub Actions.
- **Fuentes reales** (job `live-sources` del CI, 4/11/2026): Open-Meteo devolvió los 5 modelos para los
  135 municipios y las 3 ventanas; NOAA CPC devolvió ONI, índices Niño semanales y SOI; el feed CAP del SMN
  se leyó completo (niveles por color y fenómeno reconocidos).
- El panel se probó en navegador de escritorio y de celular.
- Los 135 partidos y sus límites salen de fuentes públicas (ver `app/data/README.md`).

**No verificado todavía**
- **SMN:** el feed oficial se leyó completo (51 alertas vigentes, CAP 1.2 con polígonos), pero en ese momento
  todas eran de otras provincias. Falta ver una alerta real sobre Buenos Aires para confirmar la asignación a partidos
  (`python -m app.cli smn-debug` muestra cada alerta y cuántos partidos toca).
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

## Red hídrica y cuencas

La cobertura cartográfica DPH/IGN/GCBA, su procedencia, actualización y límites de
evaluación están documentados en [HIDROGRAFIA.md](HIDROGRAFIA.md).
