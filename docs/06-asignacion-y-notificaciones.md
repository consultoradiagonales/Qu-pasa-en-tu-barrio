# Asignación y avisos

El coordinador ve reportes de su municipio y elige un equipo activo. La función `assignReportTeam` valida el rol del usuario, el municipio y que el reporte esté pendiente o asignado. La operación es transaccional: establece `status=assigned`, equipo, fecha de asignación y limpia el trabajador anterior si hubo reasignación. Los trabajadores ven las tareas por `assignedTeamId`.

`onReportCreated` crea un aviso para coordinadores del municipio. `onReportStatusChanged` crea avisos cuando se asigna o reasigna un equipo, cuando llega el trabajador y cuando se resuelve el reporte. Cada aviso queda en Firestore y, si el usuario tiene token FCM, se envía push. El ID del evento evita repetir avisos al reintentar el trigger. La foto final sigue siendo obligatoria para pasar a `resolved`.

`onReportAnalytics` mantiene `municipalityStats/{municipalityId}` con totales de reportes, estados, categorías, apoyos y horas de resolución. Usa un registro de eventos para evitar doble conteo en reintentos. El panel de Flutter escucha ese documento en tiempo real. Si ya existían reportes antes de desplegar la función, hay que reconstruir los totales iniciales antes de usar el indicador.

Las fotos opcionales durante el trabajo se suben a `/progress/` y quedan en `photosProgress`; aparecen en el detalle del reporte.

## Puesta en marcha

1. Configurar Firebase real con `flutterfire configure` y los archivos nativos Android/iOS. El archivo `lib/firebase_options.dart` actual contiene marcadores de posición.
2. Crear documentos `teams/{id}` con `name`, `municipalityId`, `active: true`, `categories` y trabajadores `users/{uid}` con `role: field_worker`, `teamId` y el mismo `municipalityId`. Los coordinadores deben tener `role: coordinator` y su `municipalityId`. Estos roles deben asignarse desde una cuenta administradora o consola confiable.
3. En la raíz: `firebase deploy --only firestore:rules,firestore:indexes,functions`. Las funciones usan Node 20. Configurar un proyecto Firebase y plan que permita Cloud Functions antes de desplegar.
4. En Flutter: `flutter pub get`, `flutter analyze` y una prueba en dispositivo de asignar → llegada → resolución → avisos.

No se realizó un despliegue: este repositorio no contiene un proyecto Firebase configurado ni credenciales reales.
