# CivicPlus / SeeClickFix 311 CRM: evidencia pública para la auditoría de ConDi

Fecha de consulta: 30 de octubre de 2026. Investigación pasiva en páginas públicas oficiales. No se enviaron formularios, no se solicitaron credenciales ni se operó un CRM de cliente. La documentación confirma funciones; no demuestra su rendimiento ni su configuración en cada municipio. No permite conocer la arquitectura interna privada de CivicPlus.

## 1. Qué producto se está comparando

La URL solicitada es una página comercial de demos, no el panel de producción. El producto de gestión de solicitudes municipales se comercializa actualmente como **SeeClickFix 311 CRM** dentro de CivicPlus. Deben distinguirse el CRM, Work Orders y productos integrados como Asset Management, Community Development y CivicPlus Agent. La existencia de una integración no implica que todas sus prestaciones estén incluidas en el abono básico.

Fuentes: [demo solicitada](https://www.civicplus.com/demo/?product=citizen-relationship-management), [producto SeeClickFix](https://www.civicplus.com/seeclickfix-311-crm/). Páginas sin fecha de publicación visible.

## 2. Capacidades confirmadas y lección para ConDi

| Capacidad | Evidencia y alcance | Incorporación razonable en ConDi |
|---|---|---|
| Entrada multicanal | La página comercial Unified Platform presenta app, portal web, SMS, Agent y operador de llamadas en una bandeja central. Es una afirmación comercial, no una prueba de todos los canales. [S1](#s1) | Un registro canónico de solicitud con `source`; comenzar por app, web y operador. Habilitar SMS/WhatsApp solo con proveedor, consentimiento y costo definidos. |
| Recepción y triage | La guía Requests List documenta Open al ingresar, asignación automática o manual, reconocimiento por Owner/Manager con comentario público y reasignación para ejecutar. Incluye filtros, prioridad, vencimiento y acciones masivas. [S2](#s2) | Bandejas «Sin asignar», «Mías», «Por vencer», «Vencidas»; acuse separado del inicio del trabajo. |
| Catálogo configurable | Categorías con opciones de privacidad, entrada guest/anónima, ubicación obligatoria, suscriptores y autoasignación a persona o departamento. [S3](#s3) | Catálogo por municipio, formularios de preguntas y reglas versionadas; evitar categorías fijas en el cliente. |
| SLA y escalación | SLA por categoría; horas/días/semanas y calendario laboral. Puede avisar por correo al contacto de escalación al vencer; ciertas opciones dependen de Work. [S3](#s3) | Plazo interno y fecha pública estimada separados; calendario municipal argentino, alertas y escalación auditable. |
| Duplicados | Marketing anuncia detección antes del envío. La ayuda operativa documenta marcar un reporte como duplicado de otro mediante su ID; el duplicado se archiva y no puede reabrirse en ese flujo. [S1](#s1), [S4](#s4) | Sugerir casos cercanos antes de crear; permitir seguir el caso existente. La unión administrativa debe conservar historial y permitir corrección controlada. |
| Solicitud frente a orden de trabajo | Una solicitud puede necesitar tareas de varios departamentos. Las OT tienen responsable, categoría, vencimiento, lugar y descripción; pueden ser hijas de una solicitud o independientes. [S5](#s5) | Separar el problema que ve el vecino de una o varias tareas operativas y exigir evidencia para cerrar. |
| Recursos y costo | Work Order Resources registra cantidades previstas y usadas; se exportan OT para evaluar consumo. [S6](#s6) | Horas, materiales y equipos en OT como segunda etapa, con unidades y moneda, antes de prometer gestión patrimonial completa. |
| Comunicación | Suscripciones de personal generan correos ante comentarios/estados; ciertas acciones agregan automáticamente al miembro. La lista de solicitudes admite comentarios y contenido preparado. [S7](#s7), [S2](#s2) | Plantillas, comentarios internos/públicos separados, seguidores y trazabilidad de entregas. No confundir la documentación de miembros con prueba de cada canal vecinal. |
| CRM de vecinos sin cuenta | Constituents permite registrar contactos de llamadas/conversaciones y crear solicitudes por ellos sin que tengan una cuenta. Una cuenta pública de usuario es otra entidad y no pertenece a una sola organización. [S8](#s8) | Ficha de contacto municipal distinta de credencial de acceso; permiso mínimo y registro de atención presencial/telefónica. |
| Indicadores | Reportes por categoría, asignado y origen; tabla/gráfico, envío de una vez o recurrente, XLSX/PDF. Métricas de reconocimiento, cierre y cumplimiento de SLA. Agrupan por fecha de creación. [S9](#s9) | Métricas con cohorte explícita, mediana/p90 y denominadores; exportación verificable y reportes programados. |
| Interoperabilidad | Open311 público, APIv2 y APIv2 organizacional privada. API org requiere licencia y autorización. La guía aclara que sus API no usan webhooks. [S10](#s10) | API pública segura y adaptadores opcionales. Si ConDi usa eventos/webhooks propios, presentarlo como diseño de ConDi, nunca como réplica interna comprobada. |
| GIS e integraciones | Catálogo oficial describe ArcGIS Online de una vía y Field Maps bidireccional; distintas integraciones de activos/expedientes sincronizan mediante polling y pueden exigir licencias externas. [S11](#s11) | Adaptadores con IDs externos, reintentos y conciliación. La dirección y frecuencia de sincronización son parte del contrato. |
| Agente conversacional | CivicPlus Agent recoge ubicación, categoría, descripción e imágenes. La integración requiere Web Central o Evolve y únicamente categorías con guest habilitado. [S12](#s12) | Asistente optativo para preparar borradores; confirmación del vecino y mismas validaciones del formulario antes de crear un caso. |
| Base de conocimiento | Agent puede usar referencias de aplicaciones, archivos y sitios. La ayuda advierte que el contenido subido a su base es accesible a usuarios sin login. [S13](#s13) | Base pública de servicios y preguntas frecuentes con dueño editorial, vigencia y enlaces. No incluir datos privados de reclamos. |

## 3. Flujo documentado, sin inferir el backend

```text
Vecino / operador
    → solicitud con categoría y ubicación
    → bandeja común: Open
    → asignación + reconocimiento público: Acknowledged
    → personal / departamentos ejecutan una o varias OT
    → comentarios, evidencia y seguimiento
    → cierre de solicitud: Closed
    → medición por cohorte, tiempos y SLA
```

SLA, duplicados y suscripciones atraviesan el flujo. Este esquema sintetiza las guías S2–S9; no afirma que los estados de una OT sean idénticos a los de una solicitud. La guía de OT indica To-Do/Done; el modelo de solicitudes también contempla reapertura. La política exacta depende del rol, categoría e integración.

## 4. Límites y puntos que no deben darse por demostrados

- **Offline de SeeClickFix: no verificado en esta investigación.** Existe una PWA de inspecciones offline documentada para **Community Development**, producto distinto y con suscripción específica. No trasladar esa capacidad al CRM. [S14](#s14)
- **Cumplimiento de accesibilidad completo: no certificado.** El centro oficial tiene recursos de accesibilidad/VPAT. Eso no sustituye pruebas con teclado, lectores y dispositivos de un flujo concreto. [S15](#s15)
- **IA móvil, calidad de clasificación y ahorro cuantificado: no medidos.** La comunicación corporativa o una demo no valida precisión, latencia, costos ni cobertura funcional en todos los clientes.
- **Arquitectura privada:** no se verificaron servidores, base de datos, colas, stack del CRM autenticado o topología de despliegue. Una web comercial y sus scripts no demuestran esa arquitectura.
- **Costos y licencias:** no hay una cotización vigente comparable para ConDi. La ayuda menciona licencias adicionales para API organizacional e integraciones; no se debe prometer paridad incluida ni asignar un precio inventado.
- **SLA estadounidense:** la ayuda configura jornada lunes–viernes 9–17 y feriados federales. ConDi necesita parámetros y calendario locales; copiar la fórmula generaría métricas engañosas.
- **Páginas de ayuda migradas:** algunas URLs actuales entregan al lector web un contenedor Document360; se usó el texto indexado oficial del mismo documento cuando fue necesario. Las fechas siguientes son las publicadas por ese sitio, no fechas de validación funcional.

## 5. Registro de fuentes

### S1

[Unified Platform for All Service Requests](https://www.civicplus.com/seeclickfix-311-crm/unified-platform/). Página comercial, sin fecha visible. Respalda canales, duplicados preventivos y catálogo configurable como prestaciones declaradas.

### S2

[Requests List Overview](https://www.civicplus.help/seeclickfix/docs/requests-list-overview). Publicado 24/07/2025; actualizado 11/04/2026. Guía de roles, estados, filtros, asignaciones, acciones y comentarios.

### S3

[Add New Request Categories](https://www.civicplus.help/seeclickfix/docs/add-new-request-categories). Publicado 01/08/2025; actualizado 12/05/2026. Guía de configuración, SLA, privacidad y automatismos. No presupone capacidades de pago habilitadas en cualquier cliente.

### S4

[Mark a Request as a Duplicate](https://www.civicplus.help/seeclickfix/docs/mark-a-request-as-a-duplicate). Publicado 29/07/2025; actualizado 11/04/2026 según índice oficial. El contenido también está disponible en la [URL oficial anterior](https://www.civicservice.civicplus.help/hc/en-us/articles/360043293074-Mark-a-Request-as-a-Duplicate), actualizada 09/02/2023. La restricción de archivo irreversible aparece en ese procedimiento.

### S5

[Create a Work Order](https://www.civicplus.help/seeclickfix/docs/create-a-work-order). Publicado 31/07/2025; actualizado 06/04/2026. Guía de OT vinculadas e independientes.

### S6

[Work Order Resources](https://www.civicplus.help/seeclickfix/docs/work-order-resources). Publicado 17/07/2025; actualizado 15/04/2026. Recurso previsto/usado y análisis de consumo.

### S7

[Subscriptions](https://www.civicplus.help/seeclickfix/docs/subscriptions). Publicado 29/07/2025; actualizado 07/04/2026. Alcance explícito: miembros de la organización; no prueba todas las modalidades vecinales.

### S8

[Differences Between Constituents and User Accounts](https://www.civicplus.help/seeclickfix/docs/differences-between-constituents-and-user-accounts). Publicado 18/04/2026. Distingue contactos/atenciones de cuentas públicas.

### S9

[Understand and Use Requests Reports](https://www.civicplus.help/seeclickfix/docs/understand-and-use-requests-reports). Publicado 31/07/2025; actualizado 06/04/2026. Fórmulas, cohorte, exportación y programación.

### S10

[API Information](https://www.civicplus.help/seeclickfix/docs/seeclickfix-api-information). Publicado 06/04/2026; actualizado 07/05/2026. Tres API, licencia organizacional, entorno de pruebas y ausencia de webhooks en esas API.

### S11

[Integrations Overview](https://www.civicplus.help/seeclickfix/docs/integrations-overview). Publicado 18/04/2026; actualizado 21/10/2026. Describe Open311, sistemas de activos/expedientes y conectores GIS; requisitos y sincronización varían por conector.

### S12

[CivicPlus Agent and SeeClickFix 311 CRM](https://www.civicplus.help/docs/civicplus-agent-and-seeclickfix-311-crm). Publicado 02/06/2026; actualizado 03/06/2026. Integración conversacional y sus restricciones. Existe también [otra URL oficial indexada](https://www.civicplus.help/docs/civicplus-agent-seeclickfix-311-crm).

### S13

[Configure the CivicPlus Agent Knowledge Base](https://www.civicplus.help/civicplus-help-center/docs/configure-the-civicplus-agent-knowledge-base). Publicado 11/03/2026; actualizado 02/06/2026. Fuentes admitidas y advertencia de publicidad del contenido aportado.

### S14

[Using the Mobile Offline Inspection PWA](https://www.civicplus.help/community-development/docs/using-the-mobile-offline-inspection-pwa). Publicado 14/07/2025; actualizado 01/10/2025. Evidencia de offline solo en Community Development; la guía impone condiciones de inicio/sincronización.

### S15

[SeeClickFix 311 CRM Help Center](https://www.civicplus.help/seeclickfix). Centro oficial consultado 30/10/2026, sin una fecha única. Incluye entrada de accesibilidad y VPAT; no se evaluó un VPAT completo ni se certificó conformidad del producto.

## 6. Decisión de producto sugerida

La ventaja replicable es la **cadena de responsabilidad**: cada solicitud tiene responsable, fecha, próxima acción, comunicación y evidencia. Para ConDi conviene priorizar catálogo municipal, bandeja operativa, autoasignación explicable, SLA y expediente de eventos. Luego sumar deduplicación, OT y medición. Un agente conversacional y conectores avanzados aportarán más cuando ese ciclo ya sea fiable. Esta priorización es una recomendación para ConDi, no una afirmación del fabricante.
