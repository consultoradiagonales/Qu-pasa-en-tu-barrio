# Clima y prevención (motor ARGWX en la app) · 6/11/2026

- Motor descargado en `MOTOR METEOROLOGICO/` desde `origin/main` (8b3452d9, incluye PR #2, #3 y #4). 70 pruebas Python OK.
- App: Mi perfil → **Clima y prevención** (`/profile/clima`), sólo para vecinos.
  - `lib/data/services/argwx_service.dart`: lee `argwx/data/alertas_pba.json` (180 KB) al abrir la sección; caché 10 min.
  - Ríos y arroyos (`crecidas.json`, ~4 MB) sólo con botón explícito.
  - `lib/data/services/argwx_municipalities.dart`: 135 partidos Georef → ARGWX, cruzado con la API Georef y verificado por centroide.
  - Distingue alerta oficial SMN de análisis ConDi; dato vencido (>3 h), ausente o en modo demo se avisa, nunca se muestra como "sin riesgo".
  - No genera notificaciones, no pide ubicación, no envía datos al motor.
  - Fuera de Buenos Aires: mensaje de cobertura no disponible.
- Pruebas: `test/argwx_service_test.dart` (8); suite completa 94 OK. Analizador sin errores.
- Android 1.0.25+26: `dist/ConDi-1.0.25+26-clima.aab`, SHA-256 `c16c9483b5971fdfd34a75433bddad0753b9e3ea615a844da16db112a07d8b11`,
  firma release verificada. Publicado en canal interno (`completed`) con `tools/publicar-play-clima.cjs`.
- Pendiente: probar en un celular real; adaptador en Firebase si el motor cambia de formato; capa "Clima y riesgos" en el mapa del panel.

Nota de compilación: `E:\condi` ya no es un alias del proyecto. Usar `tools/build-android.ps1 -bundle` lanzado con
`cmd /c "cd /d E:\CODEXC~1\04-APP~1 && powershell -File tools\build-android.ps1 -bundle > log 2>&1"`
(si se redirige la salida desde PowerShell, un aviso de Kotlin corta el script).

## Capa "Clima y riesgos" en el panel (6/11/2026)

- `web/admin/argwx-layer.js` + `argwx-municipalities.js`; interruptor en Mapa operativo, apagado al iniciar.
- Municipio: sólo su partido. Diagonales (integral o provincia 06): los 135. Otra provincia: sin cobertura.
- Pruebas: `node --test test/web/argwx-layer.test.mjs` (6). Verificado visualmente con datos reales en página de prueba
  (no con el panel completo: los emuladores piden Java 21 y la máquina tiene 17).
- Panel y web 1.0.25 publicados en Firebase Hosting el 6/11 (`firebase deploy --only hosting`).
- Aviso a vecinos enviado el 6/11 (`release_clima_v26_20261106`): 17 cuentas, 4 push, 13 bandeja.
- Hallazgo: el workflow del motor corre cada 4-9 h en vez de cada hora (GitHub demora los `schedule`).
- Commit 3a934e06 en master (no subido a GitHub).
- No usar `tools/build-web.ps1`: borra todo gh-pages salvo maqueta/assets, incluido `argwx/`.
- Recordatorio de actualización enviado el 6/11 (`recordatorio_v26_20261106`): 17 cuentas, 4 push, 13 bandeja. La app no registra la versión instalada por usuario, así que no se puede filtrar a quienes ya actualizaron.
