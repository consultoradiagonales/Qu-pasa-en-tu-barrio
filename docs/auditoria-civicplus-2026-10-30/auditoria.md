# Auditoría CivicPlus y oportunidades para ConDi

Consultora Diagonales | Corte: 30 de octubre de 2026 | Versión 1.0

## 1. Veredicto

ConDi debería evolucionar hacia un CRM de servicios municipales conservando Flutter y Firebase. La mayor enseñanza de SeeClickFix 311 CRM es organizar cada solicitud alrededor de un responsable, un plazo, una próxima acción y una comunicación verificable. La prioridad recomendada es asegurar permisos y datos completos, incorporar catálogo municipal y SLA, y luego separar reclamos de órdenes de trabajo.

No conviene comenzar por un chatbot ni replicar toda la suite CivicPlus. ConDi ya posee reportes geolocalizados, estados operativos, cuadrillas, evidencia fotográfica, comunicaciones, alertas meteorológicas y análisis con IA. El salto de valor está en convertir esas piezas en un proceso consistente. Confianza alta sobre capacidades documentadas y código local; media sobre esfuerzo; sin validación del CRM privado ni del despliegue de ConDi.

## 2. Alcance y método

Se revisó la pestaña que el usuario tenía abierta en Chrome, su DOM, recursos JavaScript declarados, formularios e indicadores semánticos. También se consultaron guías oficiales de CivicPlus y documentación de Firebase, y se inspeccionaron los modelos, repositorios, ADMIN, funciones y reglas locales de ConDi.

La URL entregada es una página comercial de acceso a videos de SeeClickFix 311 CRM. El recorrido pide nombre, apellido, correo, organización y estado. No se completó ni envió el formulario. Por tanto, esta auditoría no presenta el recorrido privado como probado. Las funciones del CRM se contrastan con ayuda operativa pública y se distinguen de afirmaciones comerciales.

Se intentó descargar el HTML y un JavaScript público del tema para inspección: el servidor respondió HTTP 403. No se eludió esa respuesta. La inspección de código externo se limita a estructura DOM, referencias de recursos y scripts inline servidos a la página abierta. No se accedió al backend, base de datos o código privado de CivicPlus.

En ConDi se examinó el árbol de trabajo local, que contiene cambios previos. No se modificó ni desplegó código de la aplicación. Los riesgos de reglas son hallazgos estáticos, no pruebas de explotación ni confirmación de incidentes. Esta entrega es una auditoría y un diseño para implementar después.

## 3. Qué hace la web comercial y qué aprender de ella

### 3.1 Recorrido visible

El parámetro de URL selecciona el producto CRM. Una navegación lateral permite elegir otros productos; una ficha central reúne la propuesta, los beneficios y el acceso al recorrido. Los textos prometen simplificar comunicación interna, permitir reportes desde web/app, apoyar decisiones con datos e involucrar a vecinos. Son objetivos declarados, no resultados medidos. [S0]

Para la web de ConDi conviene una landing propia con tres recorridos: vecino, cuadrilla y gestión. Cada uno debería mostrar un caso completo, desde el ingreso hasta la solución. Proponer una demo con datos ficticios sin registro y reservar el contacto comercial para quien quiera contratar. Mostrar el beneficio y las pantallas antes del formulario.

### 3.2 Inspección técnica de la página

| Observación directa | Qué permite concluir | Aplicación a ConDi |
|---|---|---|
| Recursos bajo wp-content y wp-includes; tema civicplus; jQuery y Algolia | Hay componentes de WordPress y búsqueda en esta web comercial. No identifica el stack del CRM. | Separar sitio comercial del ADMIN y del portal de vecinos. |
| Formularios HubSpot y reproductor Vidyard declarados | La captación y el video dependen de terceros. | Cargar integraciones comerciales solo cuando se necesiten; mantener el trámite independiente. |
| En la captura DOM: 55 etiquetas de script externo, 42 URL únicas y 13 etiquetas del mismo embed HubSpot | Hay duplicación de etiquetas en esta sesión. No prueba 13 descargas reales por la caché ni permite estimar latencia. | Inicializar una vez cada SDK y cargar la demo del producto activo bajo demanda. |
| Widgets Forethought, AudioEye, Cookiebot y varias familias de analítica/publicidad | La landing tiene una superficie amplia de terceros. No se auditó consentimiento efectivo ni transferencia de datos. | Evitar píxeles publicitarios en reclamos y ADMIN; medir con eventos mínimos y propósito definido. |
| El selector CRM usa un botón con clase activa, sin aria-selected ni aria-controls | El estado visual no está expresado con esos atributos en el control observado. | Implementar tabs con semántica, foco y teclado; o navegación de enlaces si corresponde. |
| No se observaron h1, h2 o h3 visibles en la inspección; había un elemento de heading en el documento completo | La jerarquía visual no se traduce claramente en encabezados semánticos en esa vista. No equivale a una auditoría WCAG completa. | Usar h1 único, secciones h2, labels persistentes, errores asociados y prueba con lector. |
| Los cinco campos de datos visibles tenían label asociado; tres declaraban autocomplete | Existe una base útil de accesibilidad de formularios. | Conservar labels; agregar autocompletado adecuado, mensajes de error y confirmación clara. |

Medición puntual del DOM: 30/10/2026, 16:58:47 de Argentina. No se ejecutó Lighthouse, prueba de carga ni benchmark de Core Web Vitals. La advertencia de consola observada sobre un origen de extensión no demuestra un defecto funcional del producto. Evidencia visual: evidencia/civicplus-demo.jpg.

### 3.3 Posicionamiento recomendado

ConDi puede posicionarse como una plataforma municipal en español, con implantación gradual, identidad local y seguimiento verificable. Su propuesta más concreta sería: «Cada reclamo, con responsable y respuesta». La diferenciación debe sostenerse con evidencia de cierre, calendario municipal, transparencia y costos operativos medidos. No hay una cotización comparable de CivicPlus ni datos para afirmar que ConDi sea más barato o genere determinado ahorro.

## 4. Cómo trabaja SeeClickFix según su documentación

La entrada reúne solicitudes por distintos canales en una bandeja. La documentación distingue recepción, reconocimiento público y ejecución; permite asignar responsables, filtrar, comentar y actuar sobre solicitudes. El catálogo configurable gobierna preguntas, privacidad, restricciones y parte del enrutamiento. [S1, S2, S3]

Los SLA se configuran por categoría y admiten calendario laboral y escalación. Un mismo problema puede requerir órdenes de trabajo vinculadas, con responsables y recursos propios. Las guías describen cantidades previstas y consumidas de recursos, además de exportación. Algunas funciones dependen del paquete contratado. [S3, S5, S6]

La gestión de duplicados vincula una solicitud con otra. Los contactos de atención pueden existir sin una cuenta pública. Los reportes documentan reconocimiento, cierre y SLA; la cohorte se determina por fecha de creación. Estas distinciones son más valiosas para ConDi que copiar nombres de estados o el diseño visual. [S4, S8, S9]

La API organizacional requiere licencia. La documentación indica expresamente que las API de SeeClickFix no utilizan webhooks. Los eventos y webhooks propuestos para ConDi son un diseño propio. El trabajo offline verificado pertenece a Community Development, no se comprobó para SeeClickFix. El agente conversacional tiene requisitos de integración; no es una capacidad universal de la landing. [S10, S11, S12, S14]

## 5. Comparación con el código actual de ConDi

Leyenda: «existente» significa observado en código local; «parcial» requiere ampliar el proceso; «no observado» describe la revisión, no prueba inexistencia en todo el ecosistema.

| Capacidad | CivicPlus: evidencia | ConDi: situación observada | Decisión |
|---|---|---|---|
| Alta web/app y geolocalización | Canales y mapas declarados/documentados [S1] | Existente en Flutter, report_flow y reports_repository | Conservar; añadir web vecinal ligera y alta por operador. |
| Catálogo municipal configurable | Categorías y reglas [S3] | Ocho categorías fijas en modelo/ADMIN | Prioridad alta: catálogo con versión por municipio. |
| Triage y bandejas personales | Filtros, prioridad, asignación [S2] | Filtros, prioridad y cuadrillas existentes | Añadir «Mías», «Sin acuse», «Por vencer» y próxima acción. |
| SLA y escalación | Configuración por categoría [S3] | Antigüedad y alerta fija de 72 h; SLA formal no observado | Prioridad alta: calendario y política versionada. |
| Solicitud / órdenes de trabajo | Entidades vinculables [S5] | Un reporte con cuadrilla asignada | Introducir OT sin romper los seis estados actuales. |
| Duplicados y seguimiento | Vinculación y detección declarada [S1, S4] | Voto de apoyo ya existente; fusión canónica no observada | Aprovechar apoyos como base; sugerir casos cercanos y unir con revisión. |
| Evidencia de ejecución | Trabajo y comunicación documentados [S2, S5] | Fotos antes/durante/después y fechas de campo | Fortaleza a preservar; asegurar permisos y metadatos. |
| Contactos sin cuenta | Constituents separado de usuario [S8] | Usuarios y residentes; CRM de contactos no observado | Crear contacto municipal para teléfono/presencial sin inventar logins. |
| Comunicación y plantillas | Comentarios, suscripciones [S2, S7] | Inbox, push, mensajes municipales, deduplicación | Añadir timeline, plantillas y separación interna/pública. |
| Indicadores y exportación | Reportes y programación [S9] | Resumen operativo e IA sobre consultas limitadas | Corregir cobertura antes de ofrecer KPI contractuales. |
| Integraciones GIS/API | API y conectores documentados [S10, S11] | Geohash, Georef, mapa; API externa formal no observada | Diseñar adaptadores, sin copiar la arquitectura privada. |
| IA y conocimiento | Agent y base con requisitos [S12, S13] | IA de reportes y análisis agregado con controles | Utilizar para sugerir y resumir; validar decisiones humanas. |

Evidencia local detallada, con rutas y líneas: inspeccion-condi.md. La arquitectura propuesta explica cómo ampliar cada entidad sin reescribir la aplicación.

## 6. Hallazgos que deben resolverse primero

| ID | Hallazgo local y evidencia | Impacto posible | Prioridad y tratamiento |
|---|---|---|---|
| H01 | storage.rules:22-32 permite lectura a autenticados y creación de imágenes bajo cualquier reportId sin comprobar pertenencia, fase o municipio | Exposición entre ámbitos y carga de archivos fuera del caso autorizado | P0. Verificar reglas desplegadas; probar y endurecer acceso por reporte, rol y fase. |
| H02 | firestore.rules:175-179 crea comentarios con usuario propio sin validar acceso al reporte; actualización usa staff global | Comentarios fuera del ámbito y moderación entre municipios | P0. Exigir acceso al padre, esquema permitido y permiso municipal. |
| H03 | firestore.rules:235-238 permite lectura/actualización de contentFlags a staff global | Moderación que podría cruzar municipios | P0. Definir si el rol es central o municipal y restringir por ámbito. |
| H04 | web/admin/app.js:747-751 limita a 2.000 reportes; 1023-1035 calcula métricas sobre los cargados | Casos viejos abiertos omitidos y tiempos incompletos al superar el límite | P1. Separar lista paginada de agregados completos. No aumentar el límite como solución. |
| H05 | app.js:804-808 carga hasta 2.000 vecinos para selección/alcance; dashboard-ai.js:314-319 limita a 1.000 reportes | Alcance visual parcial y análisis incompleto | P1. Contadores de servidor, búsqueda paginada y aviso de cobertura. No se afirma que el envío masivo trunque a 2.000. |
| H06 | app.js:830-835 consulta weatherAlerts sin filtro municipal; firestore.rules:216-217 exige ámbito autorizado | La consulta puede ser rechazada para roles municipales | P1. Consulta alineada con reglas e índice. Firebase no filtra automáticamente filas prohibidas. [F1] |
| H07 | firestore.rules:104 valida parte del alta, pero no todo el esquema operativo; la cuota diaria observada está en report_flow.dart:265 | Un cliente alternativo podría enviar campos o cantidades que no permite la interfaz | P0. Validar creación y cuota en servidor, con campos permitidos y reloj fiable. |
| H08 | functions/index.js:97-144 lee y después actualiza asignación sin transacción en ese flujo | Dos decisiones concurrentes pueden trabajar sobre estado desactualizado | P1. Transacción, versión esperada, evento y conflicto visible. |
| H09 | report_flow.dart:280 carga foto antes del documento y storage.rules:31 sólo acepta objetos nuevos | Un envío parcialmente completado puede colisionar al reintentarse | P1. Reservas y finalización recuperable de adjuntos. |

P0 expresa la prioridad de verificación y corrección, no la existencia confirmada de una intrusión. La restricción de actualización de fotos y el rechazo por defecto en reglas son controles existentes, pero no corrigen por sí solos los permisos de lectura/creación señalados.

## 7. Qué incorporar y en qué orden

| ID | Mejora | Impacto | Esfuerzo orientativo | Dependencias | Resultado comprobable |
|---|---|---|---|---|---|
| B01 | Permisos municipales y pruebas negativas | Alto | 3-6 días-persona | Validación del modelo de roles | Un usuario de A no opera casos de B. |
| B02 | Consultas, paginación y KPI completos | Alto | 4-8 | B01 | Caso abierto antiguo aparece en totales con más de 2.000 casos. |
| B03 | Catálogo municipal y formularios | Alto | 6-10 | B01 | Categoría nueva funciona sin publicar app. |
| B04 | Bandeja, acuse y enrutamiento explicable | Alto | 5-9 | B03 | Cada caso aceptado tiene responsable y próxima acción. |
| B05 | SLA, calendario y escalación | Alto | 7-12 | B03, eventos | Vencimientos reproducibles y una alerta por nivel. |
| B06 | Timeline de eventos y auditoría | Alto | 5-9 | B01 | Reconstrucción de cambios, autor y motivo. |
| B07 | Duplicados, seguidores y vínculo canónico | Medio-alto | 5-9 | B03, B06 | Dos reportes unidos conservan historia y apoyos únicos. |
| B08 | Órdenes de trabajo y evidencia | Alto | 8-14 | B04, B06 | Un reclamo con dos OT cierra sólo con criterio satisfecho. |
| B09 | Plantillas y bandeja de entregas | Medio-alto | 4-7 | B06 | Se diferencia aceptado por proveedor, fallido y leído. |
| B10 | Contactos y atención por operador | Medio | 5-9 | B01, B03 | Registro telefónico sin cuenta vecinal ficticia. |
| B11 | Exportación, métricas por cohorte | Medio-alto | 5-8 | B02, B05 | CSV/export y tablero concilian. |
| B12 | Base de servicios y asistencia IA | Medio | 5-10 | Catálogo y contenidos fiables | Respuestas citan fuente y borrador exige confirmación. |

Los rangos son una primera estimación de ingeniería, no una cotización ni una fecha comprometida. Incluyen desarrollo y revisión funcional básica; falta discovery municipal, pruebas de campo, contenidos y aprobación de publicación. Los ítems se solapan; no sumar ni convertir automáticamente a duración calendario. Integraciones, offline completo y mantenimiento patrimonial requieren alcance separado.

### Hoja de ruta por hitos

Hito A: confianza en permisos y datos (B01, B02). Hito B: operación gobernada (B03, B04, B05, B06). Hito C: ejecución y comunicación (B07, B08, B09). Hito D: atención y medición ampliadas (B10, B11), y B12 una vez que el contenido esté mantenido. Un piloto puede limitarse a un municipio y tres categorías acordadas. El paso de hito depende de criterios de aceptación, no de una fecha elegida sin capacidad de equipo.

## 8. Pantallas que debería tener ConDi

Para el vecino: elegir servicio, ver problemas parecidos, registrar evidencia, recibir número de seguimiento y consultar timeline con próxima acción. Al cierre, ver evidencia y poder solicitar revisión con motivo. La ETA visible debe expresar incertidumbre y política vigente; no prometer una fecha que la cuadrilla no pueda sostener.

Para el operador: ficha de contacto municipal, canal de ingreso, consentimiento de comunicación y alta en nombre del vecino. Para coordinación: bandeja con columnas de caso, zona, responsable, vencimiento, estado y próxima acción; detalle con dos timelines claramente separados, público e interno. El mapa acompaña la lista, no reemplaza la cola de trabajo.

Para cuadrillas: «Mi jornada», órdenes asignadas, inicio/pausa/finalización y evidencia; estado local pendiente de sincronización claramente visible. Para gestión: backlog por antigüedad, cumplimiento de SLA, mediana/p90 de resolución y reaperturas, con filtros de período y municipio. Para configuración: catálogo, equipos, calendario, plantillas y reglas de derivación.

El paquete incluye un esquema de estas pantallas y flujos en arquitectura.md. Es diseño propuesto, no una interfaz ya implementada.

## 9. Indicadores y condiciones de aceptación

| Indicador | Definición propuesta | Precaución |
|---|---|---|
| Tiempo de acuse | acknowledgedAt - createdAt | No confundir asignación automática con respuesta humana. |
| Backlog operativo al corte | Casos pending, assigned o in_progress en la fecha de corte | Incluir antiguos y sin acuse; separar resolved pendientes de validación y aplicar política explícita de duplicados. |
| Resolución mediana/p90 | Percentiles de resolvedAt - createdAt en casos resueltos del período | Publicar N y excluir/marcar fechas inválidas. |
| SLA al corte | Casos del denominador completados dentro de su SLA / casos evaluables cuya fecha límite ya llegó | Publicar relojes de respuesta y resolución por separado; excluir duplicados según política y mostrar pendientes vencidos. |
| SLA de cohorte | Casos cumplidos de una cohorte de creación / elegibles de esa cohorte | Identificar pendientes y período de maduración. |
| Reaperturas | Casos reabiertos / casos cerrados en cohorte definida | Declarar ventana de revisión. |
| Evidencia completa | Cierres con evidencia requerida / cierres que la requieren | No exigir fotos a categorías donde resulten inapropiadas. |
| Entregas | Aceptadas por proveedor, fallidas y lecturas registradas | Un push aceptado no demuestra recepción ni lectura. |

Antes del piloto: probar aislamiento entre dos municipios, un reporte antiguo fuera de las primeras 2.000 filas, una operación repetida por reintento, un feriado, dos cambios concurrentes, una unión de duplicados, un cierre sin evidencia y una notificación fallida. Verificar recorridos con teclado y a 390/412 px. Los datos de prueba serán sintéticos; no son métricas de usuarios reales.

## 10. Fuentes, límites y entregables

S0. [Demo solicitada](https://www.civicplus.com/demo/?product=citizen-relationship-management). Vista en Chrome el 30/10/2026; DOM y captura local.

S1. [Unified Platform](https://www.civicplus.com/seeclickfix-311-crm/unified-platform/). Declaraciones comerciales, consulta 30/10/2026.

S2. [Requests List Overview](https://www.civicplus.help/seeclickfix/docs/requests-list-overview). Ayuda oficial; actualización 11/04/2026.

S3. [Add New Request Categories](https://www.civicplus.help/seeclickfix/docs/add-new-request-categories). Ayuda oficial; actualización 12/05/2026.

S4. [Mark a Request as a Duplicate](https://www.civicplus.help/seeclickfix/docs/mark-a-request-as-a-duplicate). Ayuda oficial; contraste con URL anterior en el anexo de fuentes.

S5. [Create a Work Order](https://www.civicplus.help/seeclickfix/docs/create-a-work-order). Ayuda oficial; actualización 06/04/2026.

S6. [Work Order Resources](https://www.civicplus.help/seeclickfix/docs/work-order-resources). Ayuda oficial; actualización 15/04/2026.

S7. [Subscriptions](https://www.civicplus.help/seeclickfix/docs/subscriptions). Suscripciones del personal, no demostración de todo canal vecinal.

S8. [Constituents and User Accounts](https://www.civicplus.help/seeclickfix/docs/differences-between-constituents-and-user-accounts). Ayuda oficial; publicación 18/04/2026.

S9. [Requests Reports](https://www.civicplus.help/seeclickfix/docs/understand-and-use-requests-reports). Ayuda oficial; actualización 06/04/2026.

S10. [API Information](https://www.civicplus.help/seeclickfix/docs/seeclickfix-api-information). Ayuda oficial; actualización 07/05/2026.

S11. [Integrations Overview](https://www.civicplus.help/seeclickfix/docs/integrations-overview). Ayuda oficial; actualización 21/10/2026.

S12. [Agent y SeeClickFix](https://www.civicplus.help/docs/civicplus-agent-and-seeclickfix-311-crm). Ayuda oficial; actualización 03/06/2026.

S13. [Agent Knowledge Base](https://www.civicplus.help/civicplus-help-center/docs/configure-the-civicplus-agent-knowledge-base). Ayuda oficial; actualización 02/06/2026.

S14. [Offline Inspection PWA](https://www.civicplus.help/community-development/docs/using-the-mobile-offline-inspection-pwa). Producto Community Development, no CRM.

F1. [Firebase: consultas seguras](https://firebase.google.com/docs/firestore/security/rules-query). Reglas no equivalen a filtros. Consulta 30/10/2026.

El anexo fuentes-civicplus.md registra alcance y fechas de 15 fuentes del fabricante. El anexo inspeccion-condi.md localiza la evidencia de código. La arquitectura es una propuesta para ConDi: no pretende reconstruir componentes privados de CivicPlus. No se certificó accesibilidad, seguridad, rendimiento, SLA contractual ni ahorro económico de ninguno de los productos.
