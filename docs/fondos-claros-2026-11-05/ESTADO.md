# Fondos claros y contraste · 5/11/2026

Cambios preparados: inicio y acceso de cámara, bienvenida/splash, ingreso,
registro y recuperación por tema Flutter compartido; acceso y navegación del
panel administrativo; paneles, controles y mapa ARGWX.

Se fuerza tema claro en vez de heredar el modo oscuro del sistema. Los fondos
son blancos o azul muy tenue; el texto principal es oscuro. Se ajustaron los
grises secundarios del panel, placeholders, botones y etiquetas meteorológicas.

Validación: web release compilada; analizador sin errores (dos avisos previos de
deprecación); tres pruebas existentes del inicio aprobadas; sintaxis JS y prueba
de seguimiento ARGWX aprobadas. Paleta principal con contraste mínimo 4,5:1.
Se comprobaron en navegador el inicio y formulario ciudadano, el acceso al panel
y el módulo meteorológico en tema claro aunque el sistema prefiera modo oscuro.

CanvasKit se carga desde los archivos incluidos en el propio sitio mediante
`web/flutter_bootstrap.js`, evitando depender de la CDN para el motor gráfico.

Evidencias locales: `output/fondos-claros-2026-11-05/`.

Publicación web completada después de la autorización del usuario: Firebase
Hosting para app y panel; PR #4 fusionado, CI y GitHub Pages exitosos.
https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio/pull/4

Android 1.0.24+25 preparado en `dist/ConDi-1.0.24+25-contraste.aab` (71.564.318
bytes), firma verificada con jarsigner. SHA-256:
`854a7d0c62f647e2c047027f2f5bcdf7704398de4d9d80f7bac0c7f72dd75150`.
Se compiló desde una copia temporal dentro de `dev/build-contraste-android`,
mediante una unidad ASCII, para evitar fallos de Java/Gradle en la ruta original.
La unidad temporal se retiró y se restauraron las rutas de dependencias.

La publicación Android está pendiente de una autorización explícita adicional:
la revisión automática rechazó la operación de Play indicando que la autorización
registrada cubría Firebase/ARGWX. El canal interno sigue en versión 24 y Alpha
en borrador 24; producción no está activa. No se tocaron los verificadores.

El usuario autorizó enviar un aviso de actualización a los usuarios activos.
Mensaje preparado para vecinos con `disabled=false`: consulta previa 17 cuentas,
4 con token FCM. No se envió todavía porque la versión Android 25 aún no está
publicada. Herramienta idempotente: `tools/avisar-actualizacion-contraste.cjs`.

Después de autorizar Android: ejecutar `tools/publicar-play-contraste.cjs --publish`,
verificar con `tools/inspeccionar-play-contraste.cjs` (que actualiza la prueba de
versión disponible), y enviar una sola vez con
`tools/avisar-actualizacion-contraste.cjs --send`. El aviso enlaza al canal interno.
No desplegar reglas, funciones, índices ni elevar la versión mínima obligatoria.

## Cierre · 6/11/2026

- Play: confirmado canal interno con versión 25 `completed` (subida del 5/11,
  SHA-256 coincide). Alpha sigue en borrador 24; producción inactiva.
- Aviso de actualización enviado una sola vez (`release_fondos_claros_v25_20261105`):
  17 cuentas, 4 push aceptados, 13 solo bandeja, 0 pendientes.
  Registro: `output/fondos-claros-2026-11-05/aviso-enviado.json`.
