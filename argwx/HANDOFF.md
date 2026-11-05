# Handoff · ConDi · motor meteorológico ARGWX

Estado al **4/11/2026, 19:04 UTC**. Rama `claude/weather-engine-mvp-jafv4d`, carpeta `argwx/`.
Este documento separa lo **verificado** (probado con datos reales) de lo **pendiente** o **no verificado**.

---

## 1. Qué es y en qué estado está

MVP de un motor meteorológico para la **Cámara de Diputados de la Provincia de Buenos Aires**, que después se
integra a ConDi. Hace cuatro cosas:

- Alertas por consenso de 9 modelos en los 135 partidos.
- Tormentas en movimiento.
- El Niño en la provincia.
- Crecidas de ríos, arroyos y canales.

Suma además una **base histórica pública** para verificar los modelos y calibrar las probabilidades.

| Pieza | Dónde | Estado |
|---|---|---|
| Dashboard (celular y compu) | https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/ | Publicado. Última corrida: 23 de 24 partes bien |
| Código | https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio/tree/claude/weather-engine-mvp-jafv4d/argwx | Último commit antes de este documento: `00078d4` |
| API REST (FastAPI) | `app/api/v1.py` | Funciona en local y en Docker (imagen probada en CI). No está desplegada en un servidor |
| Tests | `tests/` | 63 de Python + 1 de JavaScript. Pasan en local y en GitHub Actions |
| Pull request a `main` | — | **No existe.** No se creó porque no se pidió (ver pendiente 1) |

El repo viejo `SentirUrbano/...` se dejó de usar por indicación del usuario.

---

## 2. Reglas del proyecto (respetarlas)

1. **Nunca** poner claves en el repo. Van como variables de entorno o *secrets* de GitHub (`ARGWX_*`).
2. Los cálculos de pronóstico **no usan IA generativa**: son conteos, umbrales y estadística.
3. El sitio se publica en la rama `gh-pages`, **solo dentro de `argwx/`**. El resto de esa rama tiene otra app
   publicada que no se toca. Lo hace el workflow; no hay que escribir a mano en `gh-pages`.
4. Las alertas oficiales son las del SMN. ConDi es una herramienta de análisis y lo dice en el sitio.
5. Al informar: separar hechos de suposiciones y decir "no lo sé" cuando corresponde (preferencia del usuario).
6. Toda la interfaz y los textos van en español rioplatense.

---

## 3. Cómo corre (pipeline)

**`.github/workflows/argwx-dashboard.yml`**
- Corre en cada push a la rama o a `main`, a mano, y **cada hora solo desde `main`** (GitHub ejecuta los
  `schedule` únicamente en la rama principal).
- Ejecuta `python -m app.cli export-site ../_site ../ghp/argwx/data`. El segundo argumento es la copia publicada
  anterior, que se usa como caché.
- Después reemplaza `gh-pages/argwx/` y hace commit.
- En los push, `ARGWX_FORCE=true` recalcula todo salvo la red hídrica.

**`.github/workflows/argwx-ci.yml`**
- Corre los tests, construye la imagen Docker y ejecuta el job `live-sources`.
- `live-sources` llama a `scripts/probe_sources.py` y `scripts/probe_historico.py` contra las fuentes reales. No
  bloquea el CI.
- Es **la forma de verificar fuentes**: el entorno de Claude Code en la nube no tiene salida a esas webs, pero
  GitHub sí.

### Partes de `export_site.build()`

Cada parte es independiente. Si una falla, se usa la copia anterior y `data/meta.json` lo informa; el sitio
muestra el aviso con nombres legibles.

| Parte | Archivo | Reuso | Fuente |
|---|---|---|---|
| enso | `enso.json` | — | NOAA CPC (ONI, Niño semanal, SOI) |
| smn | `smn_argentina.json` | — | SMN, API CAP (`ssl.smn.gob.ar/CAP/AR.php`) |
| en_vivo_respaldo | `live_pba/ar/sa.json` | 3 h | Open-Meteo (las mismas consultas que hace el navegador) |
| observaciones_smn | `observaciones_smn.json` | — | SMN datos abiertos (`tiepre`, `estaciones`) |
| rios | `rios.json` | 6 h (historia 30 días) | GloFAS: 7 puntos de referencia, percentiles 1984-hoy |
| rios_observados | `rios_observados.json` | 1 h | API pública del INA (escalas de Prefectura y Red Hidrológica Nacional) |
| costa | `costa.json` | 3 h | Open-Meteo Marine |
| ambiente | `ambiente.json` | 6 h | Open-Meteo Air Quality (CAMS) |
| probabilidades | `probabilidades.json` | 6 h | Ensamble ECMWF de 51 miembros |
| historico_* | `historico/*` | incremental | Ver sección 5 |
| enso_pba | `enso_pba.json` | 30 días | ERA5 (usa la serie de la base histórica) |
| red_hidrica | `red_hidrica.json` | 30 días (no se rehace en cada push) | OpenStreetMap (Overpass) |
| suelo | `suelo.json` | 12 h | Open-Meteo (lluvia de 30 días y humedad del suelo) |
| caudales_red | `caudales_red.json` | 12 h | GloFAS: hasta 400 puntos sobre los cauces |
| alertas_pba | `alertas_pba.json` | 6 h | Consenso de 9 modelos + SMN + observaciones (base SQLite efímera) |
| crecidas | `crecidas.json` | siempre | Cálculo propio (`hydro.compute_floods`) |

**Ojo:** el paso de publicación borra y vuelve a escribir `gh-pages/argwx/`. Por eso `data/historico/` se copia desde la
publicación anterior al empezar cada corrida. Si se cambia ese paso, **la base acumulada se pierde**.

---

## 4. Cómo decide (resumen técnico)

**Alertas por partido** (`app/engine/consensus.py`, `thresholds.py`, `app/services/state.py`)
- Un nivel exige al menos 2 modelos y al menos el 50 % de los modelos analizados.
- Umbrales propios en 24 h:
  - lluvia: 30, 60, 100 y 150 mm;
  - ráfagas: 60, 80, 100 y 120 km/h;
  - temperatura máxima: 36, 39 y 42 °C;
  - tormenta según el código WMO.
- Prevalecen sobre el modelo, en este orden: la observación del SMN (tormenta o granizo) y la alerta oficial del SMN.
- Ventanas: 0-24, 24-48 y 48-72 h.

**Tormentas en movimiento** (`app/site/tracking.js`)
- Se calculan en el navegador con 5 modelos consultados en vivo a Open-Meteo: celdas, trayectorias, radio con
  dispersión entre modelos y partidos afectados.

**Crecidas** (`app/providers/hydro.py`, `ina.py`)
- **Red:** 527 cursos con nombre de OpenStreetMap (49 ríos, 65 canales, 413 arroyos). Cada uno trae su trazado, los
  partidos que cruza y las localidades a menos de 4 km. El río Negro se agrega desde su punto de referencia porque
  su cauce es el límite provincial.
- **Nivel = el mayor de:**
  1. Lluvia prevista a 72 h en la cuenca: 40, 70 y 110 mm. Sube un nivel si llovió 150 mm o más en 30 días.
  2. Caudal GloFAS de los próximos 7 días frente al de las últimas 3 semanas: 2, 4 y 8 veces, con una subida
     mínima de 5 m³/s. **Si es la única fuente, se queda en Amarilla**, salvo que la confirme la lluvia
     (40 mm previstos, 50 mm en 7 días o 150 mm en 30 días).
  3. Punto de referencia GloFAS frente a su historia 1984-hoy (p90, p98 y máximo). En los ríos que lo tienen, se usa
     en lugar de los puntos de la red.
  4. **Escala oficial observada** del mismo río, a menos de 5 km: sobre el nivel de alerta, al menos Naranja; sobre
     el de evacuación, Roja. La observación prevalece.
- **Por qué existe el tope en Amarilla:** la primera corrida real dio 9 arroyos en Roja con apenas 26-48 mm de lluvia
  en la semana. Los arroyos venían de caudales muy bajos y la relación se inflaba.

**Probabilidad calibrada** (`app/engine/calibration.py`)
- Para cada partido y ventana se cuenta cuántos modelos pronostican 10, 30 o 60 mm o más.
- Se informa con qué frecuencia ocurrió eso en la base histórica, en 5 grupos según la fracción de modelos.
- Con menos de 10 casos se marca "pocos casos".

---

## 5. Base histórica pública (`data/historico/`, `app/providers/historico.py`)

Se descarga desde la pestaña Alertas. Se actualiza en forma incremental en cada corrida.

| Tabla | Contenido al 4/11/2026 | Fuente |
|---|---|---|
| `lluvia_era5_diaria.csv` | 16.768 días (1/12/1980 a 28/10/2026), 8 puntos (uno por sección electoral) | ERA5 vía Open-Meteo |
| `verificacion_modelos.csv` | 9.600 filas: 9 modelos, 1 a 3 días de anticipación, desde el 30/9/2025 | Corridas anteriores de Open-Meteo + ERA5 |
| `calibracion.json` | 394 días, 83.016 pares pronóstico-observación | Cálculo propio |
| `climatologia_lluvia.json` | Frecuencias por mes, 1981-2025 | Cálculo propio sobre ERA5 |
| `alertas_smn.csv` | Registro de las alertas oficiales leídas (41 al cierre) | SMN CAP |
| `smn_horarios_AAAA-MM.csv` | 28 estaciones de la provincia y CABA (sin lluvia: el SMN no la publica ahí) | SMN datos abiertos |
| `pronosticos_condi_AAAA-MM.csv` | Pronósticos diarios de ConDi por partido (405 filas por día) | ConDi |
| `rios_observados_AAAA-MM.csv` | 1.663 mediciones de 25 escalas (desde el 5/10/2026), con alerta y evacuación | INA (Prefectura y Red Hidrológica Nacional) |
| `catalogo.json` | Qué hay, de dónde sale, período y cantidad de registros | — |

**Resultados reales**

Lluvia de 20 mm o más con 1 día de anticipación:

| Modelo | Detecta | Falsas alarmas |
|---|---|---|
| ECMWF-IA (el mejor) | 64 % | 44 % |
| Los demás | 47 a 59 % | 53 a 61 % |
| CMA (el más flojo) | 38 % | 55 % |

Probabilidad calibrada para lluvia de 30 mm o más, con 1 día de anticipación:

| Cuántos modelos la pronostican | Cuántas veces ocurrió |
|---|---|
| Ninguno | 0,1 % |
| Más de la mitad | 31 % (16 casos) |
| Más de 3 de cada 4 | 50 % (8 casos, pocos) |

**Límite conocido:** la "verdad" es ERA5, un reanálisis que suaviza las tormentas locales. Mi suposición, que no
comparé con pluviómetros, es que eso hace que las probabilidades de lluvia fuerte queden conservadoras. Para 60 mm
o más no hay casos suficientes.

---

## 6. Fuentes: qué se probó y con qué resultado (desde GitHub, 4/11/2026)

**Funcionan**
- **Open-Meteo:**
  - forecast con 9 modelos;
  - ensamble;
  - Flood (GloFAS, con historia desde 1984);
  - Marine;
  - Air Quality (con cortes intermitentes; ver sección 7);
  - Archive (ERA5);
  - Previous Runs (desde el 30/9/2025);
  - Historical Forecast.
- **SMN:**
  - API CAP;
  - datos abiertos `tiepre`, `estaciones`, `datohorario`, `regtemp`, `observaciones` y `pron5d`. Las URL salen del
    catálogo de datos.gob.ar.
- **INA alerta5:**
  - `obs/puntual/estaciones` (4.695 estaciones);
  - `obs/puntual/series?var_id=2` (1.144 series de altura);
  - las mediciones de cada serie.
  - Es JSON, sin clave y permite consultas desde el navegador (CORS abierto).
- **Otras:** NOAA CPC, RainViewer, NOAA STAR GOES-19, teselas de OpenStreetMap y Overpass.

**No funcionan o están cerradas**

| Fuente | Resultado | Qué hacer |
|---|---|---|
| `ws.smn.gob.ar` | HTTP 503 | — |
| `ws1.smn.gob.ar/v1` | HTTP 401: pide autorización | Para usarla, el SMN tiene que dar credenciales. No se usó el token de su web: sería saltar un control de acceso |
| `smn.gob.ar/descarga-de-datos` y `estadisticas.txt` | HTTP 403 | — |
| "Alertas de 365 días" del SMN | Archivo vacío | Reemplazado por el registro propio (`alertas_smn.csv`) |
| Página de alturas de Prefectura | Sin respuesta desde GitHub | Los mismos datos llegan por el INA |
| NASA GIBS | Inestable | Capa satelital desactivada |
| Modelos KMA, BOM y GraphCast en Open-Meteo | Sin datos | — |
| SNIH (BDHI) | El sitio responde | No se integró |

---

## 7. Pendientes, en orden de prioridad

1. **Pasar la rama a `main`.** Sin eso, los datos (SMN, crecidas, base histórica) **solo se actualizan con cada push**.
   El mapa en vivo sí se actualiza solo en el navegador. Requiere un PR y la aprobación del dueño del repo.
2. **Uso comercial:** el plan gratuito de Open-Meteo es **no comercial**. Antes de cobrar, contratar el plan y cargar
   el secret `ARGWX_OPEN_METEO_API_KEY` (el código ya lo usa).
3. **Calidad del aire:** `ambiente` falló en las dos últimas corridas por tiempo de espera de conexión. `extras._get`
   reintenta ante el error 429 pero no ante cortes de red; agregar el mismo reintento que tiene `hydro._get`.
4. **Calibrar los umbrales** de alertas y crecidas con registros históricos (Autoridad del Agua de la provincia, INA).
   Usar pluviómetros como verdad en lugar de ERA5, por ejemplo las redes de precipitación del INA o del INTA.
   Todavía no se verificó si alerta5 las expone en forma pública.
5. **Más puntos de verificación:** hoy son 8, uno por sección electoral. Cada punto nuevo agrega, por única vez,
   la descarga de ERA5 desde 1981 y de 400 días de corridas anteriores; después se actualiza de forma incremental.
   No medí cuánto de la cuota gratuita de Open-Meteo consume.
6. **Crecidas:** reemplazar la comparación con las últimas 3 semanas por una climatología GloFAS por punto. Conviene
   hacerlo de a poco y guardarlo en caché, porque es caro.
7. **SMN:** validar la asignación de polígonos a partidos con una alerta real sobre la provincia. Hasta ahora las
   vigentes eran de otras provincias. Para revisarla: `python -m app.cli smn-debug`.
8. **SMN, API `ws1`:** pedir credenciales si se quieren los "avisos a muy corto plazo" en formato JSON.
9. **Producción:**
   - teselas de mapa de un proveedor contratado (las de OpenStreetMap son para uso liviano);
   - probar `docker compose` completo (API + PostgreSQL + Nginx; la imagen sola sí se probó);
   - desplegar la API para que ConDi la consuma (`/api/v1`).
10. **Claves opcionales**, ya con conector: `ARGWX_OPENWEATHER_API_KEY`, `ARGWX_METEOBLUE_API_KEY`,
    `ARGWX_WUNDERGROUND_API_KEY` y la variable `ARGWX_WUNDERGROUND_STATIONS`. No se probaron porque no hay claves.

---

## 8. Cómo trabajar sobre esto

```bash
cd argwx
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q                      # 63 tests
node tests/js/tracking.test.js           # seguimiento de tormentas
make demo                                # API con escenario simulado (sin internet), http://localhost:8000
make run                                 # API con datos reales
python -m app.cli sync all | status | resumen | smn-debug
python -m app.cli export-site SALIDA [CACHE]   # genera el dashboard estático (necesita internet)
```

**Ver el dashboard con los datos publicados**

```bash
git fetch origin gh-pages
git archive origin/gh-pages argwx | tar -x -C /tmp/prev
cp app/site/* /tmp/prev/argwx/
cd /tmp/prev
python3 -m http.server
```

**Verificar una corrida**
- `data/meta.json` del sitio publicado: `ok` y `error` por parte.
- Los registros del job `live-sources` del CI.

**Para un agente de Claude Code en la nube**
- No hay salida a las fuentes de datos desde el contenedor. Las pruebas se hacen agregando casos a
  `scripts/probe_historico.py` y leyendo los registros del CI.
- Los commits se suben solo a la rama de trabajo.
- No crear PR sin pedido explícito.

**Archivos clave**

| Área | Archivos |
|---|---|
| Configuración | `app/config.py` (todas las variables `ARGWX_*`) |
| Generación del sitio | `app/export_site.py` |
| Fuentes | `app/providers/` (`openmeteo`, `smn`, `enso`, `extras`, `hydro`, `ina`, `historico`, `optional`, `demo`) |
| Motor | `app/engine/` |
| Interfaz | `app/site/` (`index.html`, `app.js`, `tracking.js`, `style.css`) |
| Datos geográficos | `app/data/`: 135 partidos y provincias; fuentes en su README |
