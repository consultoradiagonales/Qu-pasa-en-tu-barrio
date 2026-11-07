# Publicación para validación en celular

30/10/2026 · ConDi web **1.0.22, compilación 23**.

- [Aplicación para abrir y compartir](https://project-5fc9024a-e961-42b7-9ee.web.app/).
- [Panel de gestión](https://project-5fc9024a-e961-42b7-9ee.web.app/admin/).

## Publicado y verificado

Firebase Hosting actualizado; reglas Firestore publicadas y cotejadas con el archivo local; índices desplegados; funciones `assignReportTeam` y `generateMunicipalityReport` actualizadas en `southamerica-east1`, Node 22. No se desplegaron indiscriminadamente las demás funciones ni se publicaron APK/AAB/iOS.

El acceso `ConDi - Gestión Municipal.lnk` del escritorio fue reemplazado y verificado: abre Chrome en modo aplicación sobre el panel HTTPS. Se conservó el acceso anterior en `output/publicacion-2026-10-30/ConDi - Gestión Municipal.anterior.lnk`.

Verificación pública en Chrome con viewport móvil de 390 × 844: app real iniciada, versión 1.0.22/23, panel mostrando login, sin desbordamiento horizontal ni errores JavaScript. Se revisaron las capturas. No se iniciaron sesiones ni se crearon vecinos o reclamos productivos durante esa prueba. Cámara, permisos del dispositivo y circuitos autenticados quedan para la validación solicitada en el celular.

## Transición de versiones móviles

La app web nueva escribe `submissionProtocol: 1`; su creación requiere esquema validado, timestamps del servidor y cuota atómica. Se incorporó y probó una vía explícita de compatibilidad para las aplicaciones móviles ya distribuidas, gobernada por el documento exclusivamente servidor `reportSubmissionPolicy/current`.

Se publicó `legacyEnabled: true` antes de cambiar las reglas. Las versiones anteriores, sin marcador de protocolo, conservan su contrato de alta previo, con identidad/municipio y cuenta habilitada. La cuota nueva **no es todavía universal**: un cliente que use la vía antigua sigue sujeto al contrato anterior. No presentar esta transición como cierre definitivo de H07/A04 para todo el tráfico.

La compatibilidad no se desactiva sola. Retirarla después de publicar y validar clientes actualizados, establecer una política de versión mínima y resolver la incorporación de altas históricas a la cuota. Desactivar antes impediría reportar a las versiones anteriores. El acceso vecinal a configuración de transición está denegado y se probó en emuladores.

## Evidencia y reproducción

- `output/publicacion-2026-10-30/verificacion-web.json`: resultado HTTP/navegador, versión y límites.
- `output/publicacion-2026-10-30/app-celular.png` y `panel-celular.png`: capturas revisadas.
- `output/publicacion-2026-10-30/firestore-anterior.json`: versión de reglas previa.
- `output/publicacion-2026-10-30/politica-anterior.json`: estado previo de la política.
- `output/publicacion-2026-10-30/firestore-publicado.json`: identificación de la versión de reglas publicada.
- `tools/publicar-web-validacion.ps1`: publicación dirigida, con bloqueo de Hosting si falla el backend previo.
- `tools/actualizar-acceso-gestion.ps1`: preparación e instalación del acceso, conservando el anterior.
- `scripts/qa-runtime/verify-published-web.cjs`: verificación pública sin credenciales.

La última suite de emuladores tiene **14 pruebas aprobadas**, incluida activación/retiro de compatibilidad y exigencia de cuota para protocolo nuevo incluso durante la transición. Se mantienen las 91 pruebas de backend y 24 de Flutter aprobadas: 129 en conjunto, además de la compilación web de release. La validación del runtime Node 22 aquí corresponde al despliegue exitoso, no a una repetición completa de la suite unitaria sobre ese runtime.

Los pendientes de permisos/reservas de adjuntos, ciclo de vida de cuentas y métricas completas continúan en [la auditoría](AUDITORIA_Y_PLAN.md). No se certifica seguridad integral ni funcionamiento físico de todos los celulares.
