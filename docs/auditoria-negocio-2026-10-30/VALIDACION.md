# Validación de la auditoría y primeras mejoras

Fecha: 30/10/2026. Resultado actualizado: **129 pruebas aprobadas, cero fallidas**: 91 de backend, 14 de integración con reglas reales y 24 de Flutter. La primera entrega verificó 99 y la ampliación inicial 128; se añadió la prueba de transición para publicar sin interrumpir versiones móviles anteriores. Ver [PUBLICACION.md](PUBLICACION.md) para el despliegue y comprobación pública de web 1.0.22/23. Esto no certifica la aplicación completa.

## Cambios aplicados al código local

- `functions/report-assignment.js`: asignación transaccional con relectura de perfil, reporte y equipo en cada intento. Rechaza equipo inactivo/de otro municipio, usuario sin permiso, estado no asignable y versión de asignación obsoleta. Guarda un evento privado junto al cambio. Conserva clientes anteriores que todavía no envían versión.
- `functions/index.js`: conecta el comando existente con el nuevo módulo; conserva la rama previa de activación del propietario, pendiente de revisión separada.
- `firestore.rules`: comentarios con acceso al padre, esquema y límites; respuesta oficial reservada a gestión del ámbito; moderación limitada a ocultar/mostrar. Denuncias con destino válido y acceso municipal; revisión sólo de estado.
- `functions/dashboard-ai.js`: detecta más de 1.000 casos mediante una lectura limitada a 1.001 y rechaza ese análisis antes de llamar al proveedor. Devuelve cobertura de la cohorte creada en el período. No calcula el backlog histórico completo.
- `functions/dashboard-ai.test.js`: prueba la frontera 1.000/1.001 y el filtro municipal.
- `web/admin/app.js`: consulta meteorológica acotada al municipio para personal local; versión esperada en asignaciones; mensaje de conflicto; cobertura parcial al alcanzar 2.000 reportes; antigüedad de 72 horas sin denominarla SLA. Conserva mensajes útiles de error del servidor.
- `firestore.indexes.json`: índice de municipio/fecha para alertas.
- `functions/package.json`: incluye el nuevo módulo en el control sintáctico.
- `firebase.audit.json`, `scripts/test-municipal-audit.ps1` y `functions/municipal-security.emulator.test.js`: verificación reproducible con proyecto demo y emuladores locales. No instala dependencias nuevas.
- Ampliación de `firestore.rules`: esquema inicial de reporte, reloj del servidor y cuota atómica de diez posiciones por UID, reutilizables sólo después de 24 horas.
- `lib/data/repositories/reports_repository.dart` y `lib/data/services/report_submission_policy.dart`: creación transaccional de reporte/cuota, reconocimiento de UUID ya confirmado y rechazo de reintentos con distinto contenido. Conserva el contador de perfil como auxiliar, sin usarlo para autorizar la cuota.
- `lib/features/report/report_flow.dart` y `lib/data/services/immutable_report_photo.dart`: recuperación de foto previamente guardada con comparación de bytes y confirmación antes de informar éxito. La cuota no impide todavía subir un archivo huérfano.
- `test/report_submission_policy_test.dart` y `test/immutable_report_photo_test.dart`: once pruebas nuevas; además se ejecutaron las pruebas existentes del flujo ciudadano y del modelo.
- [APLICACION_CIVICPLUS.md](APLICACION_CIVICPLUS.md): origen del aporte, trazabilidad B01–B12, alcance y condiciones de publicación.

No se eliminaron cambios previos ni se hicieron commits. Tras la instrucción de publicación se desplegaron reglas, índices, dos funciones y frontend web, y se actualizó el acceso directo del escritorio.

## Comprobaciones realizadas

| Verificación | Resultado | Qué demuestra |
|---|---|---|
| `npm.cmd test`, desde `functions` | 91/91 aprobadas | Suites del backend y frontera de cobertura de IA. |
| `npm.cmd run check`, desde `functions` | Aprobada | Sintaxis de los módulos declarados, incluida asignación. |
| `scripts/test-municipal-audit.ps1`, desde la raíz | 14/14 aprobadas | Reglas reales, altas/cuotas, concurrencia y compatibilidad controlada. |
| Flutter: política de envío, fotos inmutables, flujo ciudadano y modelo | 24/24 aprobadas | Recuperación, contenido inmutable, selección de cuota y pantallas existentes. |
| Análisis estático de seis archivos Dart afectados | Sin incidencias | Tipos e imports de política, fotos, repositorio, flujo y pruebas nuevas. |
| Sintaxis del panel como módulo ES | Aprobada | Parseo de `web/admin/app.js`; no sustituye una prueba visual. |
| Configuración JSON | Aprobada | Parseo de índices, configuración de auditoría y package.json. |
| Cálculos del informe comercial | Aprobados | Márgenes 70%/72,5%/70%; equilibrio 12; recuperación 2,14 meses; caja 25.800 y resultados -800/3.400/11.800 según supuestos. |

Las catorce pruebas de integración verifican:

1. Comentarios del municipio admitidos y accesos de otro municipio, padre ausente, caso privado y cuenta deshabilitada rechazados.
2. Rechazo de respuesta oficial falsa, texto excesivo, autor ajeno y campos extra; aceptación de respuesta oficial autorizada.
3. Moderación municipal/central de visibilidad; rechazo de reescritura del texto y moderación cruzada.
4. Alta de denuncias con destino válido y revisión municipal; rechazo de destinos inventados y acceso cruzado.
5. Consulta meteorológica municipal compatible con reglas; consulta global exclusiva de administrador.
6. Dos asignaciones simultáneas con versión cero producen una aceptación, un conflicto, una versión nueva y un solo evento coherente. El vecino no lee el evento privado.
7. Rechazo de asignación por ciudadano, cuenta deshabilitada, coordinador de otro municipio, equipo de otro municipio o inactivo; no revierte trabajo iniciado.
8. Rechazo de sesión/identificador inválidos y compatibilidad de asignación sin versión en cliente anterior.
9. Lecturas iniciales de UUID/cuota inexistentes autorizadas y creación atómica con estado inicial y timestamps de servidor.
10. Rechazo de veinte variantes de esquema: prioridad, contadores, asignación, notas, valoración, ubicación, categorías, evidencia, texto y consentimiento manipulados.
11. Rechazo de alta sin cuota, reloj de cliente, autor/municipio ajenos y cuenta deshabilitada; aislamiento del documento de cuota.
12. Diez altas simultáneas aceptadas; undécima rechazada sin guardar reporte ni modificar cuota. Rechazo de borrado de posiciones previas.
13. Reutilización sólo de una posición vencida después de 24 horas; rechazo de actualización aislada o eliminación de la cuota.
14. El alta antigua requiere activación explícita; protocolo nuevo no elude cuota, ni se permite alterar política desde el cliente. Retirar la política vuelve a rechazar el contrato anterior.

## Repetir la verificación

Desde la raíz del proyecto, con Node, Java y el CLI Firebase local disponibles:

```powershell
.\scripts\test-municipal-audit.ps1
```

El script utiliza el proyecto fijo `demo-condi-audit`, puertos 8187 y 9197, copia temporal de las reglas actuales y un directorio temporal ASCII para evitar el problema de rutas Unicode de Java en Windows. La suite rechaza ejecutarse sin hosts de emuladores locales. El JAR se reutiliza de la caché existente; si falta, el CLI puede necesitar descargarlo. Los puertos deben estar libres. El directorio temporal conserva sólo material de pruebas y configuración; no contiene datos de vecinos.

Entorno observado: Node 25.9.0; el backend declara Node 22. No se ejecutó esta entrega sobre el runtime productivo Node 22. Se mantuvieron sintaxis y APIs compatibles, pero esa validación corresponde a staging. El CLI no pudo consultar su aviso remoto y el SDK emitió un aviso de metadata inaccesible; las suites finales terminaron con código cero, usando Firestore/Auth locales.

Flutter/Dart: 3.47.7/3.13.5. Se utilizó la copia de SDK dentro de `dev/flutter`, con su ruta corta Windows para sortear un problema de hooks nativos con espacios. Las dependencias del SDK se resolvieron desde caché en modo offline; no se añadieron dependencias a la aplicación. El SDK compartido externo no permitía escribir su lockfile desde este entorno restringido.

Comando Flutter equivalente, con un SDK escribible:

```powershell
flutter test --no-pub test/report_submission_policy_test.dart test/immutable_report_photo_test.dart test/citizen_photo_flow_test.dart test/report_model_test.dart
```

La comprobación de recuperación usa pruebas unitarias del almacenamiento y reglas reales de las escrituras; no se simuló una caída física de conexión en un dispositivo real.

## Límites y siguiente publicación

Se compiló y publicó la web de release y se verificaron versión, inicio y login del panel con tamaño móvil. Las reglas desplegadas se cotejaron con el archivo local. No se verificaron circuitos autenticados en navegador real, compilaciones Android/iOS, costos reales ni restauración. La cuota de reportes se verificó en emuladores; otras cuotas de gasto/IA siguen pendientes. La publicación confirmó el despliegue de índices, sin una prueba productiva de cada consulta autenticada.

El contrato estricto de alta requiere transacción reporte/cuota y timestamps de servidor. Para la publicación se añadió una política servidor que conserva temporalmente el contrato anterior. La web nueva declara protocolo 1 y debe cumplir cuota incluso durante la transición. Ver [PUBLICACION.md](PUBLICACION.md) para el estado efectivo y los requisitos para retirar la compatibilidad. El límite no es universal mientras se admita la vía antigua.

La creación se recupera por UUID; el control de versión es sólo de asignaciones y no hay idempotencia general ni historial de todos los comandos. Los eventos privados todavía no tienen pantalla de consulta. Siguen abiertos los permisos/reservas de adjuntos, ciclo de vida de cuentas, métricas completas y campañas grandes. Antes de incorporar nuevos municipios con datos reales, resolver los bloqueos P0 de [la auditoría](AUDITORIA_Y_PLAN.md).
