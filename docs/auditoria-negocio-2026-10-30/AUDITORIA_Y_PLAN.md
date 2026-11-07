# ANÁLISIS COMERCIAL/EMPRESARIAL — ConDi municipal y provincial

**Consultora Diagonales · Corte: 30 de octubre de 2026**

**Actualización de publicación:** la web 1.0.22/23 ya está publicada para validación. En [PUBLICACION.md](PUBLICACION.md) figuran los enlaces, comprobaciones y la transición temporal para clientes móviles anteriores.

## 1. Veredicto

ConDi tiene una base reutilizable para vender un servicio de atención y gestión territorial por suscripción. El producto inicial debe resolver un circuito concreto: recibir un reclamo, asignarlo, informar el avance y acreditar su cierre. La expansión provincial debe venderse como un módulo de información agregada y coordinación sobre municipios adheridos, con permisos propios. Mantener Flutter y Firebase; desarrollar un único producto configurable. Antes de vender un despliegue general, cerrar los riesgos P0 y demostrar un piloto pago con costos medidos. Confianza alta en el diagnóstico del código; media en el diseño propuesto; disposición a pagar y rentabilidad real todavía sin validar.

**Propuesta comercial:** «ConDi ordena los reclamos y muestra qué necesita atención, quién lo está resolviendo y con qué resultado».

**Decisión recomendada:** iniciar por municipios con un responsable de atención, tres servicios operativos y voluntad de pagar una implementación acotada. Ofrecer la capa provincial después de conciliar datos de varios municipios. La contratación provincial puede financiar licencias municipales, pero debe identificar qué organismo paga, qué municipios participan y qué información recibe cada uno.

## 2. La aplicación y el mercado

### Alcance y evidencia

Se inspeccionaron el árbol local, modelos Flutter, flujo ciudadano, repositorio de reportes, panel web, reglas Firebase y funciones. Hay numerosos cambios anteriores en el proyecto: se conservaron. No se consultaron vecinos, facturas, IAM ni datos de producción. La auditoría previa de CivicPlus se utiliza como antecedente; no se presenta como una prueba nueva de aquel producto.

El archivo `C:/Users/FAMILIA/Downloads/arquitectura-condi-crm.txt` contiene sólo título y descripción del documento, sin modelo de datos ni arquitectura desarrollada. Se encontró el contenido completo en [arquitectura.md](../auditoria-civicplus-2026-10-30/arquitectura.md). Se trata como propuesta de referencia; no como una instrucción para ejecutar migraciones o implementar todos sus módulos.

### Qué conservar y qué simplificar

| Pieza actual observada | Valor para el comprador | Decisión |
|---|---|---|
| Reportes con municipio, ubicación, categoría y fotos | Recibir pedidos verificables | Conservar y medir abandono del envío. |
| Cuadrillas, estados y evidencia antes/después | Coordinar ejecución y demostrar resultado | Priorizar permisos, asignación segura y trazabilidad. |
| Valoración al resolver y apoyos | Recoger devolución del vecino | Mostrar cantidad de respuestas y evitar interpretar votos como prioridad absoluta. |
| Inbox, push y mensajes municipales | Informar sin llamadas repetidas | Mantener app/portal como canales iniciales; mensajería paga con presupuesto separado. |
| Identidad municipal y Georef | Adaptar el producto a distintos territorios | Configuración compartida y códigos estables; evitar versiones de código por cliente. |
| IA agregada y análisis territorial | Ayudar a leer la operación | Función opcional con cuota, cobertura explícita y revisión humana. |
| Publicidad local en app/panel | Ingreso adicional posible | No incluirla como sustento del negocio ni interrumpir el envío de un reclamo. Validar aceptación por separado. |

El inicio ciudadano está centrado en la cámara (`lib/features/home/screens/citizen_home_screen.dart`). Es claro para reportes fotográficos, pero puede dificultar un reclamo sin imagen. La obligatoriedad de foto debería depender del servicio: luminaria puede admitir descripción y ubicación; una denuncia sensible requiere otro tratamiento. Medir finalización antes de rediseñar toda la navegación.

### Tres experiencias sencillas

| Usuario | Pantalla principal propuesta | Resultado esperado |
|---|---|---|
| Vecino | Reportar / Mis solicitudes / Avisos | Número de caso, estado comprensible y próxima respuesta. Foto sólo cuando aporte o sea requisito justificado. |
| Personal municipal | Mi bandeja / Mapa / Equipos | Cada caso con área, responsable y próximo vencimiento; cierre con evidencia cuando corresponda. |
| Gestión provincial | Territorio / Servicios / Evolución | Cobertura, backlog y tiempos por municipio adherido, con definiciones comparables. |

El operador debe poder cargar un pedido telefónico o presencial sin obligar al vecino a instalar la app. Este canal reduce el sesgo de adopción y evita dejar fuera a personas con baja conectividad. No está implementado en este cambio.

### Producto inicial vendible

Un municipio, tres servicios elegidos con sus responsables, una bandeja operativa, notificaciones, evidencia de cierre y un informe mensual con cobertura explícita. Una configuración inicial, capacitación y soporte delimitados. Catálogo, SLA y permisos deben configurarse desde gestión; el vecino ve sólo los pasos necesarios para su trámite.

La escala comercial exige un único repositorio y un despliegue compartido configurable. Las apps separadas con marca propia, integraciones y entornos dedicados deben tener precio adicional que cubra mantenimiento, publicación y soporte. No regalar desarrollos exclusivos dentro del abono.

## 3. Competencia y posicionamiento

La comparación usa las mismas capacidades observables. Los portales municipales son alternativas existentes, no proveedores necesariamente disponibles para contratar. Las páginas públicas no permiten inferir costos, ahorros ni calidad de operación.

| Alternativa | Entrada y seguimiento | Gestión operativa documentada | Evidencia y límite | Implicación para ConDi |
|---|---|---|---|---|
| BA Colaborativa | Solicitudes online, seguimiento y refuerzo en mapa | Derivación al área competente | Fuente oficial de la Ciudad; sin acceso al backoffice [S1] | Un mapa de reclamos ya no diferencia por sí solo. |
| Rosario / SUA | Canal web integrado al 147 y seguimiento | Integración de canales declarada por el municipio | Fuente oficial; sin prueba de tiempos reales [S2] | El operador y un número único de caso deben entrar en el plan. |
| MuniDigital | Solicitudes, reclamos y seguimiento digital | Tareas operativas y delegaciones | Descripción de implantación municipal; sin cotización comparable [S3] | Competir por implantación repetible y resultados medidos, no por acumular módulos. |
| ConDi local | App, mapa, estados y avisos observados en código | Cuadrillas y evidencia existentes | Pruebas locales; capacidad productiva y costos no medidos | Convertir el núcleo actual en un servicio confiable antes de ampliar. |

El posicionamiento defendible es **implementación acotada, operación simple y cierre verificable**. No existe evidencia para prometer que ConDi sea más barato, reduzca un porcentaje concreto de costos o resuelva más rápido que estas alternativas.

### Mercado alcanzable

No se asigna un TAM nacional ni se multiplica el total de gobiernos locales por una tarifa hipotética. Municipio, comuna, departamento y provincia no son clientes equivalentes. Buenos Aires cuenta con 135 municipios según la fuente oficial [S4]; eso describe un universo administrativo, no 135 compradores disponibles.

Como objetivo de validación, no previsión de ventas: entrevistar diez compradores/usuarios municipales y lograr entre uno y tres pilotos pagos. Calificar cada oportunidad por problema actual, responsable operativo, presupuesto, proceso de compra, sistemas existentes y capacidad de implantación. Seleccionar el segmento después de estas entrevistas.

## 4. Auditoría técnica y riesgos

### Hallazgos y tratamiento

| ID | Prioridad | Hallazgo verificado | Estado de esta entrega | Aceptación pendiente |
|---|---|---|---|---|
| A01 | P0 | Storage permite lectura a cualquier autenticado y altas en rutas de reporte sin comprobar titular, municipio o fase. | Pendiente. No se endureció de forma aislada porque la foto se carga antes del documento padre. | Reserva de adjuntos, lectura autorizada y reintento probado. Revisar también URLs con token ya emitidas. |
| A02 | P0 | Comentarios podían crearse sin acceso al padre y moderarse desde otro municipio. | Corregido localmente: acceso al padre, cuenta habilitada, esquema, límites y autoridad de respuesta oficial. Moderación limitada a visibilidad. | Publicación y humo con clientes reales. |
| A03 | P0 | `contentFlags` admitía moderación global y creación sin validar destino. | Corregido localmente: ámbito del reporte, destino, esquema y revisión limitada a estado. | Consultas futuras deben filtrar por reporte; no usar una lista global para un coordinador. |
| A04 | P0 | La creación directa de reportes no validaba íntegramente esquema, contadores, tiempos y cuota. | Publicado para protocolo nuevo: esquema inicial estricto, timestamps de servidor y transacción reporte/cuota de diez altas por UID en 24 horas. Se conserva temporalmente el contrato de clientes anteriores mediante política explícita. | Completar migración, incorporar altas históricas y retirar compatibilidad antes de declarar aplicación universal de la cuota. Ver [publicación](PUBLICACION.md). |
| A05 | P1 | Asignación leía estado/permisos y luego escribía fuera de transacción. | Corregido localmente: transacción con revalidación, versión de asignación e historial privado atómico. Panel envía versión esperada. | Clientes antiguos siguen sin control de vista obsoleta; migrarlos antes de exigirlo en servidor. No es idempotencia general de comandos. |
| A06 | P1 | Panel calcula métricas sobre hasta 2.000 reportes visibles; puede omitir abiertos antiguos. | Mitigado: advertencia de cobertura parcial al alcanzar el límite; eliminado el falso «sin casos vencidos». | Paginación y agregados completos con conciliación, incluyendo ocultos según la definición operativa. |
| A07 | P1 | IA limitaba la cohorte a 1.000 sin detectar truncamiento. | Corregido localmente: lee hasta 1.001 y rechaza análisis si excede 1.000 antes de llamar al proveedor. Devuelve alcance de cohorte. | Agregados completos para períodos grandes. Esta cohorte no mide todo el backlog histórico. |
| A08 | P1 | Consulta de alertas meteorológicas global incompatible con coordinador municipal. | Corregido localmente: filtro municipal para personal local e índice compuesto declarado. | Publicar índice, esperar disponibilidad y verificar la pantalla con coordinador. |
| A09 | P1 | Foto con ruta fija se carga antes de crear el reporte; reintento podía chocar con objeto inmutable. | Corregido localmente para el flujo ciudadano: reutilización sólo de bytes idénticos y alta idempotente por UUID sin sobrescribir el caso. | Prueba de dispositivo/staging y reservas de adjuntos de A01. No equivale a una cola offline general. |
| A10 | P1 | No hay modelo específico de permisos provinciales observado; admin es global. | Diseño propuesto en esta auditoría. | Nunca asignar admin a un cliente provincial para conseguir su tablero. |
| A11 | P1 | Activación de propietario usa correo fijo sin verificar explícitamente `email_verified`; el cliente puede borrar su perfil y crear uno nuevo. | Pendiente de revisar bootstrap, bajas y ciclo de vida de cuentas. | Privilegios por identidad verificada/provisión servidor; impedir recreación de perfil para eludir una suspensión. |
| A12 | P2 | No se verificaron cuotas de análisis municipal, presupuestos, backup/restauración ni enforcement de App Check. | Pendiente; no implica que todos estén ausentes de la consola. | Cuotas antes del gasto, consumo por cliente y restauración probada. |
| A13 | P1 | El selector de vecinos carga hasta 2.000; el backend de mensajes consulta la audiencia completa en memoria. | Pendiente. La estimación de alcance puede diferir del envío real y el consumo crece con la audiencia. | Audiencia paginada, trabajo durable y total definitivo separado de la estimación. |

`flaggedCount` sigue siendo incrementable por clientes sin una denuncia única enlazada. No usarlo como señal confiable para ocultar automáticamente o priorizar. El historial añadido cubre exclusivamente asignaciones; no acredita auditoría completa de todas las transiciones.

Las reglas de Firebase autorizan consultas completas; no filtran resultados después de cargarlos [S5]. Las funciones con Admin SDK necesitan sus propias comprobaciones. Un índice declarado en el repositorio todavía no es un índice disponible en producción.

### Riesgos de negocio

Probabilidades cualitativas estimadas, no frecuencias observadas.

| Riesgo | Probabilidad / impacto | Mitigación |
|---|---|---|
| Bajo uso por falta de responsables municipales | Alta / alto | Piloto con dueño de proceso y revisión semanal de casos. |
| Personalización y soporte consumen el margen | Alta / alto | Configuración estándar, horas incluidas y cambios fuera de alcance cotizados. |
| Demoras de compra o cobro | Media / alto | Hitos de implementación, flujo de caja por cobro y reserva operativa. Validar procedimiento de cada organismo. |
| Acceso entre municipios o fuga por fotos/exportaciones | Media / crítico | Cerrar P0, probar aislamiento en todos los recursos y revisar enlaces existentes. |
| Provincia interpreta pocas denuncias como ausencia de problemas | Alta / alto | Mostrar cobertura/adopción y separar reclamos de indicadores externos. |
| Una campaña o uso de IA dispara consumo | Media / alto | Cuotas por cliente, trabajos paginados, límites de adjuntos y canales contratados. Una alerta de gasto no es un corte efectivo. |
| Cambio de gestión o dependencia del proveedor | Media / alto | Titularidad contractual, exportación portable y salida documentada. |

### Datos, privacidad y gobernanza

La Ley 25.326 establece principios de finalidad, calidad, seguridad y confidencialidad aplicables al diseño [S6]. El acuerdo debe precisar responsable del tratamiento, prestación de ConDi, finalidades, retención, acceso, incidentes y devolución de datos. Confirmar el régimen provincial y la contratación aplicable con el organismo antes de ofertar; esta auditoría no certifica cumplimiento.

La gobernación no adquiere acceso automático a fotos, direcciones, contactos o denuncias individuales por financiar el producto. Definir permisos y base de intercambio. Para el tablero usar inicialmente agregados con controles sobre grupos pequeños y filtros que puedan reidentificar. Un umbral por sí solo no garantiza anonimización. Revisar destino real del hosting y transferencias internacionales, sin inferirlos de la región de una función [S7].

## 5. Arquitectura sencilla y escalable

Mantener un monolito modular sobre Firebase: identidad/permisos, solicitudes, asignación, adjuntos, comunicaciones y métricas. Las operaciones sensibles pasan gradualmente por comandos de servidor. No introducir microservicios ni una reescritura total como requisito inicial.

| Capa | Primera implementación recomendada | Cuándo ampliar |
|---|---|---|
| Ámbito municipal | `municipalityId` obligatorio y validado en cada recurso/consulta | Proyectos separados si un contrato exige aislamiento dedicado y lo financia. |
| Membresías | Permisos concedidos por servidor por municipio; rol central reservado al proveedor | Permisos por área o servicio si la operación lo requiere. |
| Provincia | `provinceMemberships` y concesiones a municipios participantes; permiso de lectura de agregados | Casos de competencia provincial en un ámbito operativo propio y con aceptación de derivaciones. |
| Configuración | Catálogo, marca, áreas, plazos, cupos y módulos habilitados por municipio | Versionar cambios y evitar reescribir históricos. |
| Escrituras | Comandos con validación, transacción y eventos; adjuntos reservados | Cola durable para operaciones con canales externos y reintentos. |
| Lecturas | Páginas pequeñas; filtros en servidor; métricas independientes de la lista | Agregados por día/servicio/municipio con conciliación y fecha de actualización. |
| Analítica territorial | Tablero de servicios agregados con cobertura y fuente | Fuentes oficiales externas e integraciones contratadas con actualización trazable. |

No reutilizar `departmentId` geográfico como área municipal: usar `assignedDepartmentId`. No confundir `assignmentVersion`, incorporado en esta entrega, con una versión global del reporte. Una provincia debe tener `provinceId` canónico validado; no deducir jurisdicción sólo de un texto libre.

### Qué debe conocer una gobernación

Primero: demanda registrada por servicio/territorio, casos pendientes, antigüedad, respuesta útil, resolución y reaperturas. Después: contexto de población, cobertura de servicios e infraestructura a partir de fuentes externas identificadas. El dato ciudadano no es una encuesta representativa ni prueba de prevalencia de delitos o enfermedades.

Cada indicador territorial debe declarar fuente, período, unidad, cobertura municipal, adopción y actualización. Comparar municipios sólo con categorías y definiciones compatibles; separar baja demanda de baja adopción. No generar puntajes políticos o perfiles individuales a partir de reclamos.

## 6. Números clave y rentabilidad

### Modelo de cobro propuesto

1. **Implementación:** configuración, importación acotada, formación y puesta en marcha, con entregables e hitos cobrables.
2. **Abono municipal:** plataforma, mantenimiento, soporte limitado y consumo incluido definido.
3. **Módulos:** gestión avanzada, capa provincial e integraciones con precio adicional.
4. **Excedentes:** canales pagos, almacenamiento, IA y soporte extraordinario bajo condiciones acordadas antes de consumirlos.

La licencia provincial y las municipales deben estar desglosadas para evitar cobrar dos veces el mismo alcance. La app ciudadana puede ser gratuita para el vecino. Publicidad y venta de datos personales no sostienen el modelo propuesto.

### Escenario ilustrativo, no tarifario ni cotización

Valores en **USD equivalentes internos por mes**, corte 30/10/2026. Son supuestos de diseño para probar sensibilidad; no precios relevados, costos de Firebase cotizados ni evidencia de disposición a pagar. No se utiliza tipo de cambio. La moneda de contratación, facturación, impuestos y revisión de precios se acuerdan con cada comprador bajo su régimen aplicable.

| Paquete hipotético | Abono | Costo directo estimado | Contribución | Margen bruto |
|---|---:|---:|---:|---:|
| Municipal inicial | 600 | 180 | 420 | 70,0% |
| Municipal avanzado | 1.200 | 330 | 870 | 72,5% |
| Tablero provincial, hasta 10 municipios adheridos | 2.500 | 750 | 1.750 | 70,0% |

El paquete provincial sólo ilustra analítica agregada; las licencias operativas municipales se presupuestan aparte. Los límites comerciales finales deben salir de la medición del piloto: casos/mes, usuarios internos, fotos, almacenamiento retenido, sesiones, envíos, IA y soporte. No vender consumo ilimitado.

Descomposición hipotética del costo directo municipal inicial de 180: cómputo/base 50; fotos/egreso 20; canales pagos 15; IA 10; soporte 60; operación de cuenta 25. Son asignaciones internas del escenario, no tarifas de proveedores. Implementación se cobra aparte, debe cubrir su costo completo y no se cuenta como MRR.

Fórmulas reproducibles:

```text
Contribución mensual por municipio = abono - costo directo
Margen bruto = contribución / abono
Precio mínimo con margen objetivo = costo directo / (1 - margen objetivo)
Equilibrio en clientes = techo(costos fijos mensuales / contribución por cliente)
Recuperación de adquisición = costo de adquisición / contribución mensual cobrada
```

Con costo directo 180 y margen objetivo 70%, el piso es 600. Si el costo crece a 300 manteniendo el precio 600, el margen baja a 50%: habría que reducir consumo/soporte o revisar el abono. La rentabilidad no se consigue sólo con infraestructura barata.

| Sensibilidad: sólo paquete inicial | 10 municipios | 20 municipios | 40 municipios |
|---|---:|---:|---:|
| MRR supuesto | 6.000 | 12.000 | 24.000 |
| Costos directos a 180 cada uno | 1.800 | 3.600 | 7.200 |
| Contribución | 4.200 | 8.400 | 16.800 |
| Costos fijos supuestos de producto/ventas/administración | 5.000 | 5.000 | 5.000 |
| Resultado mensual antes de impuestos y financiación | -800 | 3.400 | 11.800 |

Los costos fijos excluyen los rubros ya incluidos en costos directos para no duplicarlos. El escenario supone capacidad fija suficiente; a 40 clientes puede ser necesario ampliarla. No incorpora morosidad, bajas, impuestos ni financiamiento y no representa un pronóstico.

Equilibrio: techo(5.000 / 420) = **12 municipios**. Con adquisición hipotética de 900 por cliente: 900 / 420 = **2,14 meses de contribución cobrada**. Una demora de cobro de tres meses con veinte clientes requeriría cubrir aproximadamente (5.000 + 3.600) × 3 = **25.800** de operación, más implementación e impuestos que correspondan. Validar caja además de margen.

### Métricas que debe producir el piloto

| Métrica | Definición y límite |
|---|---|
| Finalización del envío | Casos confirmados por servidor / inicios de reporte del período; eventos mínimos sin texto privado. |
| Primera respuesta útil | Tiempo desde alta hasta primera respuesta humana útil; separar acuse automático. |
| Backlog | Casos activos al corte, cualquiera sea su fecha de creación. |
| Cumplimiento | Casos evaluables dentro de política SLA versionada / casos evaluables; declarar pausas y exclusiones. |
| Resolución | Mediana y p90 por servicio/cohorte; no sólo promedio de cerrados recientes. |
| Reapertura | Casos reabiertos / casos resueltos elegibles, con ventana definida. |
| Satisfacción | Valoración y tasa de respuesta; no extrapolar sólo quienes califican. |
| Costo directo por cliente | Infraestructura atribuible + canales + IA + soporte y operación de cuenta del mes. |
| Margen bruto | (Abono devengado - costo directo) / abono devengado; caja cobrada por separado. |

Los objetivos iniciales se acuerdan con la operación después de medir una línea de base. Como criterio comercial interno propuesto: margen bruto previsto al menos 70% y evidencia de cobro; no se presentan como resultados ya alcanzados.

## 7. Plan de mejora de 90 días

Horizonte orientativo, sujeto a capacidad y dependencias. Los plazos no son una estimación cerrada de desarrollo.

| Fase | Trabajo y responsable sugerido | Criterio de salida |
|---|---|---|
| Días 1–15: base segura | Ingeniería: A01/A04/A09/A11, consultas y accesos cruzados. Operación: elegir servicios y responsable municipal. Comercial: diez entrevistas. | Adjuntos recuperables, creación validada, suspensión efectiva, reglas negativas aprobadas y alcance del piloto firmado. |
| Días 16–30: operación útil | Producto/ingeniería: catálogo mínimo, responsable/área, acuse y plazo simple versionado, bandeja por vencimiento, métricas completas. | Un caso antiguo sigue en backlog; cada caso piloto tiene próximo paso; tablero concilia con datos completos. |
| Días 31–60: piloto pago | Municipio: uso diario. ConDi: capacitación, soporte medido, informe semanal y registro de costos. | Un ciclo real completo por cada servicio; cierre con evidencia; medición de adopción, tiempos, consumo y cobro. |
| Días 61–90: repetibilidad | Configurar segundo municipio sin bifurcar código. Probar agregado provincial con ámbitos concedidos. Comercial: propuesta anual basada en piloto. | Aislamiento probado, onboarding repetible y economía unitaria calculada con datos reales. |

Postergar órdenes de trabajo complejas, activos, WhatsApp bidireccional, chatbot general y analítica predictiva hasta que un comprador y un caso de uso financien su complejidad. Offline de cuadrilla sí debe adelantarse si la conectividad del piloto impide ejecutar tareas.

### Criterio para salir a vender

Se puede presentar una demo con datos sintéticos y contratar una implementación por hitos. Para habilitar datos reales del piloto, cerrar los P0 relevantes, probar restauración y asignar responsables de tratamiento/operación. Para vender expansión, demostrar uso, costos, exportación y funcionamiento entre municipios. No prometer SLA de disponibilidad, ahorros o precisión provincial sin haberlos medido.

## 8. Cambios y validación de esta entrega

Las mejoras están detalladas en [VALIDACION.md](VALIDACION.md). El aporte adicional CivicPlus se incorporó en [APLICACION_CIVICPLUS.md](APLICACION_CIVICPLUS.md), con trazabilidad B01–B12. La primera entrega quedó local; tras la instrucción de publicar se desplegaron web, reglas, índices y las dos funciones modificadas. [PUBLICACION.md](PUBLICACION.md) registra el alcance efectivo y los límites de la transición. Esto no equivale a certificación de seguridad integral.

## 9. Fuentes

Fuentes públicas consultadas el 30/10/2026. Cuando no se indica publicación, la página consultada no ofrece una fecha útil para esta auditoría. Se parafrasean capacidades; no se copian extensamente sus textos.

- S1. [Gobierno de la Ciudad: BA Colaborativa](https://buenosaires.gob.ar/gcaba_historico/innovacionytransformaciondigital/ba-colaborativa). Descripción pública de entrada, derivación y seguimiento; página bajo sección histórica, no prueba del servicio actual desplegado.
- S2. [Municipalidad de Rosario: integración del portal web con SUA y 147](https://www.rosarionoticias.gov.ar/page/noticias/id/410487/title/El-municipio-suma-un-nuevo-canal-para-consultas-y-reclamos-en-su-portal-web). Publicación histórica de implantación, consultada en esta fecha; no benchmark de resultados.
- S3. [Portal para Personal Municipal: ampliación de MuniDigital](https://comunicar.gob.ar/munidigital062026/), junio de 2026. Relato municipal de capacidades implantadas; no auditoría independiente ni lista de precios.
- S4. [Argentina.gob.ar: gobiernos locales de Buenos Aires](https://www.argentina.gob.ar/buenosaires/municipios). Universo administrativo de 135 municipios, no mercado comprador validado.
- S5. [Firebase: consultas y reglas](https://firebase.google.com/docs/firestore/security/rules-query) y [agregaciones](https://firebase.google.com/docs/firestore/query-data/aggregation-queries). Base técnica para separar autorización, listas y métricas.
- S6. [Ley 25.326, texto original oficial](https://www.argentina.gob.ar/normativa/nacional/ley-25326-64790/texto), sanción 4/10/2000. Se usa para principios de diseño, sin certificar adecuación jurídica ni vigencia de cada obligación local.
- S7. [AAIP: transferencias internacionales](https://www.argentina.gob.ar/transferencias-internacionales). Verificar destino y mecanismo aplicable antes de contratar infraestructura.
- Evidencia primaria local: `storage.rules`, `firestore.rules`, `functions/index.js`, `functions/report-assignment.js`, `functions/dashboard-ai.js`, `web/admin/app.js`, `lib/features/report/report_flow.dart`, `lib/data/repositories/reports_repository.dart` y `lib/data/services/auth_service.dart`.
- Antecedentes: [auditoría CivicPlus](../auditoria-civicplus-2026-10-30/auditoria.md), [inspección anterior](../auditoria-civicplus-2026-10-30/inspeccion-condi.md) y [arquitectura completa](../auditoria-civicplus-2026-10-30/arquitectura.md). Los hallazgos de esta entrega se cotejaron con el código actual.

**A VERIFICAR:** costos reales por cliente, disponibilidad de presupuesto, compra pública aplicable, voluntad de pago, tasa de adopción, reglas efectivamente desplegadas, backups, residencia del dato y cobertura provincial. Ninguno se reemplaza con los supuestos financieros anteriores.
