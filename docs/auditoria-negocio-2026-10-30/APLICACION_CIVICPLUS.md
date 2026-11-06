# Aplicación del aporte CivicPlus a ConDi

Consultora Diagonales · 30/10/2026.

**Actualización posterior:** la publicación solicitada ya se realizó con una política explícita de compatibilidad para móviles anteriores. Ver [PUBLICACION.md](PUBLICACION.md); la cuota nueva todavía no es universal mientras esa vía permanezca habilitada.

## Aporte incorporado

Se conservó el texto recibido en [auditoria-condi-civicplus-aporte.txt](auditoria-condi-civicplus-aporte.txt). Es un análisis de referencia, no una orden para desplegar, registrar contactos, enviar mensajes ni copiar un producto completo. Sus afirmaciones sobre inspecciones anteriores y capacidades de terceros corresponden a ese documento; no se realizó una nueva sesión privada de CivicPlus.

El aporte confirma la secuencia de la auditoría del proyecto: permisos y datos confiables; catálogo/compromisos; ejecución y comunicación. La frase del documento «no se modificó ni desplegó» describe su elaboración original. Las mejoras inicialmente locales se publicaron después de la instrucción expresa del usuario, con el alcance registrado en PUBLICACION.md.

## Qué se aplicó ahora

**Alta validada por servidor.** Las reglas exigen identidad y municipio compatibles, cuenta habilitada, categoría conocida, longitudes acotadas, coordenadas dentro de rango, esquema permitido y consentimiento coherente. La solicitud comienza pendiente, con prioridad inicial uno, contadores en cero, sin asignación, trabajo, valoración o resolución inventados. Creación y actualización inicial usan tiempo del servidor. Las referencias de fotos tienen tipo y longitud acotados; su propiedad y contenido real siguen pendientes de la reserva de adjuntos. Tampoco se certifica todavía pertenencia del punto al polígono municipal ni correspondencia del geohash con las coordenadas.

**Cuota verificable.** Reporte y reserva de cuota se confirman en una transacción Firestore. El documento `reportSubmissionQuotas/{uid}` tiene diez posiciones. Cada posición se marca con tiempo del servidor y no puede borrarse ni reutilizarse durante 24 horas. La regla comprueba que la actualización esté unida a un reporte nuevo de ese usuario. No depende del contador editable del perfil, de la hora del teléfono ni del municipio elegido. Cambiar de municipio o recrear el perfil con el mismo UID conserva la cuota. Es un límite por UID, no una defensa completa contra creación masiva de cuentas.

**Envío recuperable.** Antes de cargar una foto en una ruta existente se compara su contenido. Se reutiliza únicamente una imagen idéntica; una diferente exige un nuevo reporte. Ante una respuesta de carga perdida, se verifica el objeto guardado antes de informar éxito. Si la escritura del reporte ya se había confirmado, la transacción reconoce el mismo UUID y los mismos datos de origen, sin modificar estado, asignación ni evidencia posteriores. Un UUID con contenido distinto se rechaza. No se vuelve a incrementar el contador auxiliar al reconocer un reintento.

La cuota autoriza el documento después de subir la imagen. Todavía es posible tener un archivo huérfano si el alta se rechaza: limitar archivos antes de subirlos requiere resolver H01 con reservas. No se presenta esta mejora como protección completa de Storage ni como sincronización offline.

## Trazabilidad del backlog recibido

| Bloque | Estado real local | Paso siguiente y condición de aceptación |
|---|---|---|
| B01 Permisos | Parcial: comentarios/denuncias aislados; altas con esquema y cuota; asignación transaccional. | Reserva de adjuntos, propiedad/fase, control de URLs existentes y ciclo de vida de cuentas. Pruebas negativas de todos los recursos. |
| B02 Datos/KPI | Parcial: límite del panel declarado; IA rechaza cohortes truncadas; alertas municipales corregidas. | Listas paginadas y métricas completas independientes, incluyendo abiertos antiguos. No aumentar el límite para aparentar cobertura. |
| B03 Catálogo | Diseño; no implementado. | Tres servicios piloto configurables con requisitos, responsable y versión; conservar categorías antiguas durante migración. |
| B04 Bandeja/acuse | Filtros y asignación existentes; acuse/próxima acción formal pendientes. | Cada caso con dueño operativo y siguiente acción visible; derivación sin equipo termina en bandeja de revisión. |
| B05 SLA | Pendiente. La antigüedad de 72 h no es SLA. | Empezar con política simple versionada por servicio; incorporar calendario laboral si lo exige el piloto. Probar pausa, feriados y tareas obsoletas. |
| B06 Timeline | Parcial: eventos privados de asignación atómicos; alta por UUID recuperable. | Historial de todas las transiciones y separación público/interno. No hay todavía idempotencia de todos los comandos. |
| B07 Duplicados | Apoyos existentes; vínculo canónico pendiente. | Unir con revisión, conservar originales y evitar ciclos/doble seguimiento. |
| B08 Órdenes | Fotos y flujo de cuadrilla existentes; entidad OT pendiente. | Introducir OT cuando un caso necesite varias tareas; condicionar cierre a evidencia y tareas requeridas. |
| B09 Entregas | Inbox/push existentes; trabajos durables y plantillas pendientes. | Estados y reintentos por canal; proveedor aceptó y vecino leyó son señales distintas. |
| B10 Operador/contactos | Pendiente. | Alta telefónica/presencial con contacto del municipio y origen trazable, sin cuentas ficticias. |
| B11 Exportación/cohortes | Definiciones propuestas; exportación completa pendiente. | Archivo privado que concilie con el tablero y declare filtros, corte y total. |
| B12 Base/IA | IA asistida existente; base de servicios pendiente. | Añadir contenidos con fuente/versionado después del catálogo y controlar gasto por cliente. |

El sitio comercial con recorridos vecino/cuadrilla/gestión queda como trabajo de captación. No se crearon formularios externos ni integraciones publicitarias en esta entrega. El tablero provincial conserva la condición de datos agregados, cobertura explícita y permisos concedidos; no recibe rol admin global.

## Pruebas de esta ampliación

Se verificaron el flujo ciudadano y modelos existentes, once pruebas nuevas de recuperación/comparación/cuota, reglas reales de alta y cuotas concurrentes en emuladores y análisis estático de los archivos Dart tocados. Los resultados finales figuran en [VALIDACION.md](VALIDACION.md). Las reglas se prueban sobre datos sintéticos y proyecto demo; no se consultó producción.

La validación de la cuota usa [operaciones atómicas y `getAfter` de Firestore](https://firebase.google.com/docs/firestore/security/rules-conditions), consultado el 30/10/2026. Esta solución mantiene la transacción del cliente con autorización efectiva en servidor; un comando Admin SDK futuro deberá aplicar su propio límite porque ese SDK omite las reglas.

## Condiciones de publicación

**Las nuevas reglas de alta necesitan el cliente actualizado.** Un cliente anterior no escribe la reserva de cuota ni los timestamps de servidor. Publicar únicamente estas reglas le impediría reportar; publicar únicamente el cliente contra reglas viejas también impediría escribir la cuota. No ejecutar el deploy habitual como si fueran cambios independientes.

Preparar una transición en staging y una ventana coordinada, o una política temporal de compatibilidad con activación controlada y fecha de retiro. Validar Android, iOS y web y definir el mínimo de versión antes del cambio productivo. La versión comercial de este repositorio no se incrementó ni se publicó automáticamente.

Las cuotas nuevas no incluyen automáticamente altas históricas. Antes del cambio, decidir si el límite empieza con la nueva política o se precargan desde servidor las últimas diez altas de cada UID en las 24 horas previas. Esta última opción exige una migración con corte, conciliación y control de concurrencia; no permitir que el cliente precargue timestamps arbitrarios. No se ejecutó una migración sobre datos reales.

Tras el corte: comprobar primer envío, reintento con foto existente, reintento con reporte ya confirmado, once envíos concurrentes, rechazo de alteración de cuota, cambio de municipio y cuenta suspendida. Conservar borradores y revisar huérfanos mediante una política de retención; no borrar evidencia como parte de la publicación.

El siguiente bloqueo de seguridad continúa siendo H01/A01, seguido del ciclo de vida de cuentas. Catálogo y SLA se implementan sobre esa base. Los plazos, órdenes, duplicados y canales nuevos del aporte son backlog; no se presentan como funciones ya disponibles.
