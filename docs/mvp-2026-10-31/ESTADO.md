# ConDi — MVP y preparación de Google Play

Fecha: 31/10/2026. Versión web y Android: **1.0.23+24**.

## Accesos

- App web para compartir: https://project-5fc9024a-e961-42b7-9ee.web.app/
- Gestión: https://project-5fc9024a-e961-42b7-9ee.web.app/admin/
- Prueba interna Android: https://play.google.com/apps/internaltest/4701647237677047143
- Agregar verificadores de la prueba cerrada: https://play.google.com/console/u/1/developers/5136895399514402259/app/4972058149285363473/tracks/4700085297915828169?tab=testers

El acceso directo existente del escritorio apunta al mismo panel publicado. La prueba interna sólo está disponible para cuentas habilitadas como verificadores.

## Entregado

- Logo ConDi junto al escudo del ámbito seleccionado. Catálogo solicitado: Provincia de Buenos Aires, La Plata, Trenque Lauquen, Saladillo, Escobar y Rivadavia. Fuentes y licencias en `assets/images/municipalities/SOURCES_MVP.md`. El catálogo y los escudos no representan adhesiones ni clientes contratados.
- Diagonales: cartera integral de municipios e indicadores completos de los reportes visibles. Cuenta central provisionada sólo desde servidor. Municipios: acceso exacto al `municipalityId` asignado, incluyendo administradores municipales; el rol `admin` por sí solo ya no otorga alcance global.
- Aislamiento aplicado en reglas Firestore y funciones de asignación, prioridad, avisos, mensajería, analítica, gestión de cuadrillas, publicidad y configuración de versiones. Los clientes no pueden otorgarse la organización central ni cambiar su municipio operativo desde el perfil.
- Totales calculados en servidor con páginas de 500, caché privada de cinco minutos y límite explícito de 50.000 casos por consulta. Si se supera, se rechaza el cálculo para evitar totales parciales. El detalle usa páginas de 200 y permite seguir cargando; las categorías usan el agregado completo. Mediana de resolución, atrasos de más de 72 horas y estados desconocidos explícitos.
- Los ámbitos históricos de un mismo municipio se identifican visualmente; no se fusionan permisos ni se reescriben datos. El selector diferencia sus identificadores.
- Inicio de la app: un fallo de Firebase presenta error y reintento. La demostración requiere `CONDI_DEMO=true`; no reemplaza silenciosamente datos reales.
- Información del proveedor privado y fuentes institucionales, política de privacidad y página pública para solicitar eliminación. Ficha de Google Play corregida y correo público de soporte completado.

## Publicación y validación

- Firebase Hosting, reglas e índices Firestore y doce funciones de gestión publicados. Se verificó que las reglas remotas coinciden con el archivo probado y que los 14 recursos públicos revisados responden correctamente, incluidos los seis escudos y los módulos del panel.
- Navegador con sesión existente del propietario: tablero integral y selección de La Plata consultan datos productivos. Se comprobó la marca conjunta ConDi + escudo. Las pruebas de aislamiento con usuarios municipales se ejecutaron en emuladores, sin crear cuentas ni casos productivos.
- **198 pruebas aprobadas:** 96 backend, 16 de seguridad en emuladores y 86 Flutter. El analizador de los archivos Dart cambiados no reportó errores; conserva cuatro avisos informativos previos en la consola nativa.
- Web de producción compilada; Android AAB firmado, validado y aceptado por Google Play. SHA-256: `22a0f026c6ef49601a974df87b0e1afe22c92b49de0841eb0580b2a9d69f820c`.
- Prueba interna: versión 24 completada. Prueba cerrada Alpha: versión 24 **en borrador**, por indicación del usuario de agregar verificadores después. Se comprobó visualmente en Play Console. Producción permanece inactiva y el nombre puede mostrarse temporalmente como paquete sin revisar.

Evidencias técnicas privadas: `output/mvp-2026-10-31/`. Esa carpeta no forma parte de Hosting. No compartir los respaldos de perfiles ni credenciales.

## Bloqueos y condiciones antes de vender con datos reales

1. **Fotos — pendiente de seguridad.** La revisión automática rechazó publicar Storage por las reglas heredadas que permiten leer/crear fotos a cualquier usuario autenticado y por URLs permanentes. Se publicó el trabajo independiente y se comprobó que Storage quedó sin cambios. La restricción central de publicidad preparada en `storage.rules` tampoco se publicó. Por lo tanto, el aislamiento probado de Firestore y las funciones no equivale todavía a aislamiento completo de todos los archivos.

   La corrección requiere una migración compatible: reservas de carga vinculadas al usuario/municipio, reglas por reporte y fase, lectura autenticada de imágenes en web y Android, y sustitución/revocación de los enlaces antiguos. Debe probarse contra versiones móviles anteriores antes de activarse. No aprobar las reglas amplias como solución ni presentar este MVP como apto para datos sensibles.

2. **Google Play — prueba obligatoria.** Play Console muestra 0 verificadores inscritos. Deben agregarse los verificadores, revisar y enviar la versión cerrada a Google y mantener al menos 12 participantes inscritos durante 14 días continuos. Después se solicita acceso a producción; Google decide su aprobación. Preparar el borrador no inicia el plazo. La prueba interna no lo reemplaza y la app aún no aparece en el buscador público.

   Fuente oficial: https://support.google.com/googleplay/android-developer/answer/14151465. Disponibilidad de las pruebas: https://support.google.com/googleplay/android-developer/answer/9845334.

3. **Cuota de altas — transición heredada.** Se conserva `reportSubmissionPolicy/current.legacyEnabled=true` para las versiones ya distribuidas. Las nuevas altas usan protocolo transaccional y cuota; no se afirma que la cuota sea universal hasta retirar la compatibilidad tras la actualización de clientes.

4. **Escala y rentabilidad.** El escaneo limitado con caché sirve para el piloto; para aumentar volumen se requieren agregados incrementales/reconciliación, presupuesto y alertas de costos por municipio, respaldos probados y monitoreo. El precio comercial debe incluir implementación, abono por municipio y adicionales de IA/almacenamiento/soporte con límites claros. No hay rentabilidad medida ni contratos municipales confirmados por incorporar sus escudos.

## Operación posterior

Agregar los verificadores en la pestaña de Play Console que quedó abierta. Luego revisar la versión cerrada, enviarla a Google y compartir su enlace una vez habilitado. No se enviaron invitaciones ni mensajes a terceros. Antes del primer piloto con datos reales, cerrar la migración de fotos y documentar responsables, retención y recuperación de cada cliente.

Para compilar Android en este equipo, usar la unidad temporal ASCII del proyecto y ejecutar la compilación con resolución de paquetes habilitada. `--no-pub` puede dejar un registro de `integration_test` incompatible con release. La copia local del SDK evita escribir en el SDK compartido; al terminar se restauraron las rutas del proyecto y se quitó la unidad temporal.
