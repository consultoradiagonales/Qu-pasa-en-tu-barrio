# Inspección técnica de ConDi y arquitectura evolutiva

Fecha: 30 de octubre de 2026. Inspección estática del código local, sin modificar la aplicación, ejecutar ataques, consultar datos de vecinos ni verificar despliegues de producción. Las rutas y líneas corresponden a la copia de trabajo examinada; ésta contiene cambios locales anteriores. «No observado» significa que la capacidad no se encontró en los módulos inspeccionados, no que sea imposible que exista en otra herramienta o servicio.

## 1. Decisión técnica

ConDi ya posee el núcleo de un sistema municipal de solicitudes: captura ciudadana, geolocalización, seis estados, asignación a cuadrillas, evidencias de trabajo, valoración y notificaciones. Conviene conservar Flutter, Firebase y los flujos existentes, y añadir un catálogo municipal de servicios, reglas de derivación, compromisos de atención, historial de decisiones y una bandeja operativa escalable. Antes de extender canales o incorporar automatizaciones, se recomienda cerrar las brechas de autorización y confiabilidad identificadas.

La propuesta es evolutiva: convertir progresivamente las escrituras operativas en comandos validados por servidor, con versión de reporte, evento de auditoría y trabajo de notificación. No exige reescribir la aplicación ni adoptar microservicios por anticipado.

## 2. Capacidades que ya existen

| Capacidad | Evidencia local verificada | Implicación |
|---|---|---|
| Flutter con Riverpod, GoRouter y Firebase Auth/Firestore/Storage/Functions/FCM | `pubspec.yaml:11`; `pubspec.yaml:19`; `pubspec.yaml:42` | Mantener la base multiplataforma. |
| Ciclo pending → assigned → in_progress → resolved, además de rejected y closed | `lib/data/models/report_model.dart:32`; `firestore.rules:129` | No diseñar otro gestor de estados desde cero; formalizar transiciones y reapertura. |
| Reporte con ubicación, categoría, prioridad, cuadrilla, tiempos y cuatro grupos de fotos | `lib/data/models/report_model.dart:118` | La evidencia operativa es una fortaleza reutilizable. |
| Borrador local con UUID persistente | `lib/features/report/report_flow.dart:62`; `lib/features/report/report_flow.dart:152` | Hay base para recuperación del envío, pero no equivale a una cola offline integral. |
| Cuadrillas y asignación validadas en servidor por rol, municipio, equipo activo y estado | `functions/index.js:69`; `functions/index.js:121` | Reutilizar el servicio y reforzar atomicidad. |
| Control de acceso a reportes según titular, municipio y equipo | `firestore.rules:20`; `firestore.rules:31`; `firestore.rules:37` | Existe separación municipal significativa, con excepciones a corregir. |
| Mensajes a vecino, selección, municipio o todos, con autorización municipal | `functions/user-messaging.js:80`; `functions/user-messaging.js:98`; `functions/user-messaging.js:129` | La comunicación segmentada ya existe; la brecha es el seguimiento del caso y el proceso de entrega. |
| Bandeja y push con identificador de aviso estable por destinatario, lotes y fallback in-app | `functions/push-delivery.js:44`; `functions/push-delivery.js:55`; `functions/push-delivery.js:97` | No afirmar que ConDi carece de idempotencia o notificaciones. Ampliar a trabajos durables y métricas de entrega. |
| IA de reporte con consentimiento, acceso autenticado a fotos y cuotas transaccionales | `functions/ai-trigger.js:17`; `functions/ai-trigger.js:24`; `functions/report-ai.js:69` | Mantener IA como asistencia con revisión humana. |
| IA de gestión que envía agregados, más analítica territorial con consentimiento | `functions/dashboard-ai.js:319`; `functions/dashboard-ai.js:327`; `functions/usage-analytics.js:148` | Reutilizar privacidad y agregación; corregir cobertura de datos. |
| Valoración tras resolución y apoyos con voto identificado | `firestore.rules:122`; `firestore.rules:165`; `lib/data/repositories/reports_repository.dart:109` | Incorporar satisfacción y seguimiento sin duplicar mecanismos existentes. |

## 3. Hallazgos técnicos prioritarios

Las prioridades siguientes son decisiones de diseño propuestas; no son puntuaciones CVSS ni pruebas de incidentes en producción.

### P0. Autorización de adjuntos y datos auxiliares

**Evidencia.** `storage.rules:22` permite leer fotos a cualquier cuenta autenticada. `storage.rules:31` permite crear imágenes en cualquier ruta `reports/{reportId}/{fase}/{archivo}` con autenticación, tamaño, tipo y ausencia de objeto previo, sin comprobar autor del reporte, municipio, cuadrilla, fase o cuenta deshabilitada. La inmutabilidad evita reemplazos y borrados, pero no establece quién puede agregar evidencia. El flujo ciudadano sube la foto antes de crear el documento (`lib/features/report/report_flow.dart:280`; `lib/features/report/report_flow.dart:292`), por lo que introducir una comprobación ingenua de existencia del reporte rompería ese envío.

**Diseño recomendado.** Reservar primero un borrador/adjunto mediante comando, con uid, municipio, fase, caducidad y ruta autorizada; cargar el archivo en esa ruta; finalizar el reporte validando metadatos. Restringir lecturas privadas con la misma política del reporte. Publicar una proyección específica si se desea que otros vecinos vean imágenes o ubicaciones. Mantener archivos originales inmutables y miniaturas redactadas cuando corresponda.

**Evidencia adicional.** `firestore.rules:175` exige acceso al reporte padre para leer comentarios, pero `firestore.rules:177` sólo exige usuario autenticado y autor propio para crear. `firestore.rules:179` permite actualizar comentarios a cualquier staff sin comprobar municipio. `firestore.rules:235` también permite leer/actualizar contentFlags a staff global. Debe aplicarse el mismo ámbito municipal y validación de campos en todos los caminos. Estas observaciones son del código local, sin intento de explotación.

### P0. Validación de creación y antiabuso en servidor

**Evidencia.** `firestore.rules:104` valida identidad, municipio, estado inicial, visibilidad y campos de consentimiento; no impone una lista completa de claves, rangos de prioridad, contadores iniciales, campos de asignación nulos, tiempos de servidor ni tipos/longitudes de todos los campos. La cuota de diez reportes diarios está en el cliente (`lib/features/report/report_flow.dart:265`; `lib/core/constants/app_constants.dart:11`); no se observó su equivalente en la regla de creación.

**Riesgo.** El formulario normal puede funcionar correctamente mientras un cliente alternativo escribe valores que no produciría la interfaz, infla prioridad o evita la cuota cliente.

**Diseño recomendado.** `createReport` en servidor con idempotencyKey y DTO de campos permitidos, cuota transaccional por usuario/municipio, reloj de servidor y límites de adjuntos. Si se conserva creación directa, expresar restricciones equivalentes en reglas y someterlas a pruebas de emuladores. Evitar que el número de apoyos determine por sí solo la atención de seguridad, salud o emergencias.

### P1. Concurrencia de asignación e historial

**Evidencia.** `functions/index.js:97` lee usuario, reporte y equipo; `functions/index.js:135` comprueba estado; `functions/index.js:144` actualiza después, sin transacción en ese flujo. Entre lectura y escritura otro proceso puede iniciar trabajo o cambiar asignación. El esquema conserva estado y algunas fechas, pero no se observó un registro general inmutable de transiciones con actor, motivo y versión (`lib/data/models/report_model.dart:146`). Las notificaciones no sustituyen ese historial.

**Diseño recomendado.** Comando `assignReportTeam` transaccional con `expectedVersion`; revalidar estado y asignación dentro de la transacción; escribir reporte, `reportEvents/{eventId}` y `outbox/{eventId}` de forma atómica. Mensaje comprensible si la versión cambió. Todas las transiciones relevantes deben pasar por la misma política.

### P1. Métricas parciales y consultas a gran escala

**Evidencia.** `web/admin/app.js:747` consulta como máximo 2.000 reportes; para el administrador central no filtra municipio en servidor. `web/admin/app.js:1023` calcula resumen y tiempos sobre la lista cargada. El límite puede dejar fuera casos viejos todavía abiertos y producir cifras que no representan todo el municipio. `functions/dashboard-ai.js:314` limita el conjunto a 1.000 sin declarar truncamiento en su resultado. `web/admin/app.js:804` carga como máximo 2.000 vecinos para el selector y cálculo de alcance. Esto no limita el envío municipal de backend: `functions/user-messaging.js:143` consulta todos los destinatarios y luego los procesa, por lo que el alcance mostrado puede diferir del real.

**Diseño recomendado.** Paginar listas mediante cursores; filtrar municipio, estado, fecha y categoría en servidor; separar métricas completas de la página visible. Mantener agregados por municipio/día/servicio y mostrar fecha de corte/cobertura. El informe IA debe recibir esos agregados completos o declarar muestra y truncamiento. Para campañas grandes, crear un job con audiencia congelada y páginas de destinatarios; mostrar estimación y luego el total definitivo.

### P1. Consulta de alertas incompatible con el ámbito del coordinador

**Evidencia.** `web/admin/app.js:831` consulta las últimas cien `weatherAlerts` de toda la colección sin filtro municipal; `firestore.rules:216` exige staff del municipio del documento, salvo administrador. Las reglas de Firestore autorizan consultas, no filtran después los resultados; ese patrón puede fallar para coordinadores. No se probó con una sesión real.

**Diseño recomendado.** Agregar filtro municipal para personal local e índice correspondiente; conservar vista global exclusivamente central. Añadir prueba con dos municipios y roles admin/coordinator/field/citizen.

### P1. Recuperación de envío y operación offline

**Evidencia.** Existe borrador persistido en SharedPreferences (`lib/features/report/report_flow.dart:152`). El envío usa ruta fija `reports/{draft.id}/citizen/photo...` y carga antes de crear el reporte (`lib/features/report/report_flow.dart:280`). Storage sólo autoriza objetos nuevos (`storage.rules:31`). Si se cargó una foto pero falló el paso posterior, un reintento sobre la misma ruta puede encontrar un objeto existente. No se observó una máquina de estados durable de envío ni resolución de conflictos para trabajo de campo. Firestore puede aportar caché según plataforma/configuración, pero eso no garantiza carga de fotos offline ni confirmación segura de cierre.

**Diseño recomendado.** Outbox local con estados draft/uploading/queued/syncing/sent/needs_action; ruta determinista con verificación de adjunto ya finalizado o token de carga; identidad de comando estable; archivos locales conservados hasta confirmación. Para cuadrillas: precarga de tareas, captura sin red, cola de fotos y transición enviada una vez que los adjuntos estén confirmados, con conflicto visible si cambió el responsable.

### P2. App Check, observabilidad y mantenimiento

**Evidencia.** `lib/main.dart:61` activa App Check nativo y omite web. Las funciones callable examinadas no declaran `enforceAppCheck`; no se inspeccionó la consola para comprobar enforcement de Firestore/Storage. Las declaraciones de App Check en cliente no demuestran protección obligatoria. `web/admin/app.js:1` importa SDK desde CDN y centraliza la lógica de todos los módulos en un solo archivo; `web/admin/app.js:48` conecta emuladores automáticamente por hostname local. El watchdog de arranque existe (`web/admin/index.html:19`; `web/admin/index.html:44`) y evita una espera indefinida, aunque no sustituye un servidor HTTP correcto al abrir un archivo con módulos.

**Diseño recomendado.** Configurar entornos explícitos, empaquetar dependencias, modularizar ADMIN por función y compartir contratos/esquemas de API; prueba de humo de arranque y gestión de errores recuperables. Incorporar trazas por commandId/eventId, alertas de jobs fallidos, tablero de colas y presupuesto de lecturas/envíos/IA. Introducir App Check web y enforcement sólo tras validar clientes reales y accesibilidad de proveedores.

## 4. Brechas funcionales a cubrir

No se observaron en los módulos inspeccionados:

- Catálogo de servicios configurable por municipio con formularios, requisitos, área responsable, plazo y reglas de derivación. Las ocho categorías actuales son generales (`lib/data/models/report_model.dart:11`).
- SLA por servicio/prioridad, calendario hábil, primera respuesta, pausa por causa documentada, alertas de vencimiento y escalamiento. La heurística de antigüedad de 72 horas en `web/admin/app.js:1035` no equivale a SLA.
- Detección y vinculación de reportes duplicados con un caso principal y suscriptores. El voto de apoyo ya existente ayuda, pero no reemplaza la relación entre solicitudes del mismo hecho.
- Cola de triage por área y responsable con vistas guardadas, tareas en lote, notas internas diferenciadas de mensajes públicos y reapertura con motivo.
- Base de conocimiento orientada a autoservicio y derivación de consultas que no requieren cuadrilla.
- Captura por operador de atención telefónica/presencial y conectores de canales con consentimiento y trazabilidad. No se debe prometer WhatsApp o correo bidireccional sin un proveedor, presupuesto y operación definidos.
- Historial consolidado de casos e interacciones del vecino con permisos de mínima necesidad; no un perfil para vigilancia ni puntajes personales.
- Exportación operativa completa y API de integración documentada para GIS/activos/mesa de entradas.

## 5. Arquitectura objetivo propuesta

```text
Vecino Flutter/web   Operador ADMIN   Cuadrilla Flutter   Adaptadores de canal
          \              |                |                    /
                  API de comandos y consultas
           Auth + contexto municipal + autorización + esquema
                  cuota + idempotencia + versión
                                 |
                  Transacción Firestore por comando
                /                |                 \
       reports (estado)    reportEvents        outbox/jobs
                |           (historial)             |
        vistas paginadas      sólo servidor      workers/Tasks
                |                                   |
       métricas agregadas                  FCM / futuro email/SMS
                |                         reintentos y fallidos
       dashboard + IA agregada

Adjuntos: reserva autorizada → Storage → validación → vínculo al reporte
SLA: política versionada → dueAt → evaluador programado → evento/escalamiento
```

Los adaptadores, Cloud Tasks y nuevas colecciones son componentes propuestos. No describen una infraestructura ya instalada. Al principio pueden ser módulos dentro del mismo proyecto Firebase. Separar servicios sólo si volumen, equipos o aislamiento contractual lo requieren.

### Modelo mínimo, compatible con migración gradual

| Recurso | Campos propuestos | Regla principal |
|---|---|---|
| `serviceCatalog/{id}` | municipalityId, code, title, schemaVersion, fields, ownerDepartmentId, routingPolicyId, slaPolicyId, active | Catálogo versionado; sólo gestión autorizada edita. |
| `reports/{id}` | campos actuales + serviceId, serviceVersion, sourceChannel, assignedDepartmentId, version, visibility, duplicateOf, sla | El servidor calcula estado, prioridad operativa y plazos; el vecino mantiene sólo campos habilitados. |
| `reports/{id}/events/{eventId}` | municipalityId, actorId, actorRole, action, at, beforeVersion, afterVersion, reason, commandId, publicSummary | Append-only por servidor; notas internas no expuestas al vecino. |
| `commands/{tenantCommandKey}` | actorId, municipalityId, payloadHash, state, result, expiresAt | Misma clave y mismo payload devuelve mismo resultado; clave reutilizada con payload distinto se rechaza. |
| `attachmentReservations/{id}` | reportId/draftId, municipalityId, ownerId, phase, storagePath, status, expiresAt | Storage sólo acepta la reserva vigente y fase autorizada; finalizar valida integridad. |
| `slaPolicies/{id}` | municipalityId, version, timezone, businessCalendar, responseTarget, resolutionTarget, escalationRules | La política se copia/versiona en cada caso para evitar cambios retroactivos invisibles. |
| `outbox/{eventId}` / `deliveryJobs/{id}` | type, recipientScope, state, attempt, nextAttemptAt, leaseUntil, errorCode | Reintentos durables, lease y dead-letter; FCM aceptado no se presenta como leído. |
| `municipalityDaily/{key}` | municipalityId, serviceId, date, open, created, resolved, breached, coverageVersion | Agregación idempotente con reconciliación programada. |
| `publicReportViews/{id}` | ubicación y texto redactados, categoría, estado, publicSummary | Sin datos de contacto, notas internas ni rutas originales de evidencias privadas. |

`departmentId` ya existe para geografía en perfil/reporte: no reutilizarlo para área municipal. El nuevo campo debe tener un nombre distinto, como `assignedDepartmentId`, con migración y contrato explícitos.

### Comandos y contratos de referencia

`createReport`, `assignReport`, `startWork`, `appendEvidence`, `resolveReport`, `reopenReport`, `linkDuplicate`, `sendCaseMessage`, `createCampaign`. Cada comando recibe municipio esperado, id de recurso, expectedVersion e idempotencyKey; el servidor obtiene actor/rol del token y perfil, y nunca confía en un rol enviado por el cliente.

Respuesta: commandId, reportId, acceptedVersion, state y eventId. Error de conflicto: versión actual y acción sugerida sin sobrescribir silenciosamente. Los eventos se usan para auditoría y procesamiento; el documento del reporte sigue siendo una vista actual eficiente. No hace falta implementar event sourcing completo.

## 6. Primera versión útil

**Iteración 0: base confiable.** Corregir reglas auxiliares/adjuntos, validar creación y cuota, asignación transaccional, consultas municipales y métricas explícitas. Pruebas de emuladores con dos municipios y accesos cruzados, más un envío recuperado tras caída de red.

**Iteración 1: gestión del compromiso.** Catálogo inicial de servicios, área/responsable, SLA simple en horas corridas con calendario hábil posterior si el municipio lo necesita, historial visible y bandeja por vencimiento. Seleccionar servicios piloto con responsables operativos reales antes de automatizar derivación.

**Iteración 2: cierre del circuito.** Vinculación de duplicados, mensajes dentro del caso, reapertura justificada y satisfacción al cierre. Registrar primera respuesta útil separada del acuse automático.

**Iteración 3: expansión.** Outbox offline de cuadrilla, operador multicanal, base de conocimiento y conectores GIS/activos. Incorporar canales pagos sólo cuando se definan atención, consentimiento, costos y soporte.

## 7. Criterios de aceptación y medición

- Ninguna cuenta de un municipio puede leer/modificar evidencia, comentarios, banderas o notas privadas de otro. Administrador central sujeto a registro de acceso y permisos explícitos.
- Repetir un mismo comando tras una desconexión no crea otro caso, otra asignación, otra transición o un segundo aviso. Probar fallas después de guardar y antes de devolver respuesta.
- Dos asignaciones concurrentes producen una sola versión vigente y un conflicto visible; ningún comando devuelve assigned sobre una tarea que ya pasó a in_progress.
- Métricas del tablero coinciden con la colección completa bajo un dataset de prueba mayor que los límites anteriores; cada exportación declara filtros y fecha de corte.
- Un reporte pendiente anterior a la página más reciente sigue entrando en backlog y SLA.
- Envío de reporte recuperable cuando la foto existe pero falló la escritura del documento.
- Trabajo offline conserva fotos y borradores; la UI distingue guardado local, en sincronización y confirmado por servidor.
- Medir mediana/p90 de primera respuesta útil, resolución por servicio, porcentaje dentro de SLA, reaperturas, duplicados vinculados y satisfacción con tasa de respuesta. No comparar municipios sin ajustar servicio, volumen y cobertura.
- Medir jobs completados/fallidos, costo por caso y lecturas por sesión, junto con tasa de comandos rechazados y conflictos; fijar umbrales con datos del piloto, no inventar objetivos universales.

## 8. Límites y verificación pendiente

No se auditaron IAM, consola Firebase, backups, restauración, App Check enforcement, facturación, infraestructura externa ni datos de producción. Los hallazgos de reglas deben reproducirse en emuladores antes de publicar cambios. No se ejecutaron suites ni se modificó código durante esta inspección. Hay pruebas unitarias existentes para múltiples funciones, pero su mera presencia no acredita cobertura ni que hayan pasado en esta fecha.

Para comparar con CivicPlus, utilizar las capacidades verificadas en su sitio y documentación pública que recopile el informe principal. No inferir el backend de CivicPlus a partir de su web de marketing ni asumir equivalencia entre esa web y su producto autenticado.
