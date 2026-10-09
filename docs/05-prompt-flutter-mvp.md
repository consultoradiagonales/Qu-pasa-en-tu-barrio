# Módulo 5 — Prompt para generar la app en Flutter

## Cómo usar este prompt

Copiar el bloque XML completo y enviarlo como prompt a GPT-5.6 Luna (o Codex).
Enviar un módulo por vez, en el orden indicado abajo.

---

## PROMPT 1 — Estructura base del proyecto Flutter

```xml
<task>
Crear la estructura base de un proyecto Flutter para una app ciudadana de reporte de problemas urbanos llamada "¿Qué pasa en tu barrio?".

La app usa:
- Flutter 3.x (último estable)
- Firebase (Auth, Firestore, Storage, Cloud Messaging)
- Google Maps SDK
- Paquetes: firebase_core, firebase_auth, cloud_firestore, firebase_storage, firebase_messaging, google_maps_flutter, geolocator, image_picker, geoflutterfire_plus (para GeoHash), cached_network_image, go_router, riverpod (gestión de estado), flutter_local_notifications

Roles en la app: citizen, field_worker, coordinator, admin. El routing cambia según el rol.

Estructura de carpetas requerida:
lib/
  main.dart
  firebase_options.dart
  core/
    constants/
    theme/
    router/
    utils/
  data/
    models/         ← clases Dart con fromJson/toJson
    repositories/   ← acceso a Firestore y Storage
    services/       ← Firebase Auth, FCM, Geolocation
  features/
    auth/           ← login, registro, recuperar contraseña
    map/            ← mapa principal con marcadores y filtros
    report/         ← crear reporte (ciudadano)
    report_detail/  ← ver detalle, fotos, comentarios
    my_reports/     ← lista de reportes propios
    field/          ← modo equipo de campo (foto antes/después, GPS)
    coordinator/    ← panel de asignación
    profile/        ← perfil y eliminar cuenta
    notifications/  ← lista de notificaciones
  shared/
    widgets/
</task>

<structured_output_contract>
1. pubspec.yaml completo con todas las dependencias y versiones pinned.
2. main.dart con inicialización de Firebase y routing por rol.
3. core/router/app_router.dart con go_router, rutas protegidas por rol.
4. core/theme/app_theme.dart con paleta de colores: primario=#1565C0 (azul municipal), acento=#FF6F00 (naranja urgencia), fondo claro.
5. Un archivo por cada model en data/models/: UserModel, ReportModel, TeamModel, CommentModel, NotificationModel con fromJson/toJson/copyWith.
6. Comentarios en español dentro del código.
Output: archivos de código, uno por sección, sin texto explicativo entre bloques.
</structured_output_contract>

<default_follow_through_policy>
Si falta un detalle menor, elige la opción más estándar para Flutter y continúa.
No preguntes sobre detalles de UI que no afectan la arquitectura.
</default_follow_through_policy>

<action_safety>
Solo genera los archivos pedidos. No modifiques la estructura de carpetas propuesta sin explicarlo.
</action_safety>
```

---

## PROMPT 2 — Autenticación completa

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar el módulo de autenticación completo en lib/features/auth/.

Flujo requerido:
1. SplashScreen: chequea si hay sesión activa → redirige a home o login
2. WelcomeScreen: botones "Registrarse" y "Iniciar sesión"
3. RegisterScreen: nombre completo, correo, contraseña (mín. 8 chars), confirmación. Llama a Firebase Auth createUserWithEmailAndPassword. Guarda el usuario en Firestore (colección users) con role: "citizen".
4. LoginScreen: correo + contraseña + botón "Continuar con Google" (GoogleSignIn + Firebase)
5. ForgotPasswordScreen: envía correo de recuperación con sendPasswordResetEmail
6. Después del login, lee el campo `role` de Firestore y redirige:
   - citizen → /map
   - field_worker → /field
   - coordinator → /coordinator
   - admin → /coordinator

Requisito Play Store: el usuario puede eliminar su cuenta desde ProfileScreen.
La eliminación borra: Firebase Auth, Firestore users/{uid}, Storage users/{uid}/, y todos los reportes donde userId == uid (soft-delete: hidden=true).
</task>

<structured_output_contract>
Un archivo por pantalla. Incluir:
- auth_repository.dart en data/repositories/
- auth_service.dart en data/services/
- Pantallas en features/auth/screens/
- Widgets reutilizables en features/auth/widgets/ (form fields con validación)
- Manejo de errores de Firebase con mensajes en español
</structured_output_contract>

<completeness_contract>
Verificar antes de entregar:
- [ ] Google Sign-In funciona en Android (requiere SHA-1 en Firebase Console — agregar comentario con instrucciones)
- [ ] El token FCM se guarda en Firestore al hacer login
- [ ] La eliminación de cuenta es completa (Auth + Firestore + Storage)
</completeness_contract>
```

---

## PROMPT 3 — Mapa principal con reportes

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar el mapa principal en lib/features/map/.

Requerimientos:
1. GoogleMap widget con posición inicial en la ubicación del usuario (Geolocator).
2. Marcadores de reportes cargados desde Firestore (colección reports).
   - Color del marcador por estado: rojo=pending, amarillo=assigned/in_progress, verde=resolved
   - Clustering de marcadores cuando hay muchos juntos (usar google_maps_cluster_manager_2 o flutter_map_marker_cluster)
3. Filtros en barra inferior: categoría (chips), estado (chips), fecha (últimos 7d / 30d / todos)
4. Al tocar un marcador: BottomSheet con tarjeta del reporte (título, categoría, estado, foto miniatura, botón "Ver detalle").
5. FAB "Reportar problema" (solo rol citizen): navega a /report/new
6. Stream de Firestore en tiempo real para actualizar marcadores sin recargar.
7. Consulta geográfica: cargar solo los reportes dentro del boundingBox visible en el mapa (para no descargar toda la colección).

La consulta Firestore usa el campo location.geohash con geoflutterfire_plus.
</task>

<structured_output_contract>
- map_screen.dart
- map_controller.dart (Riverpod NotifierProvider)
- report_marker_widget.dart
- report_card_bottom_sheet.dart
- map_filters_bar.dart
- reports_repository.dart (con consulta GeoHash + filtros de estado/categoría)
</structured_output_contract>

<verification_loop>
Verificar que:
- [ ] El mapa solicita permiso de ubicación con rationale dialog antes de acceder (requisito Play Store)
- [ ] Si el usuario niega el permiso, el mapa igual funciona centrado en el municipio
- [ ] Los marcadores se actualizan en tiempo real sin parpadeo
</verification_loop>
```

---

## PROMPT 4 — Crear reporte (ciudadano)

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar el módulo de creación de reportes en lib/features/report/.

Flujo de la pantalla:
1. Formulario con: título (máx 80 chars), descripción (máx 500 chars), categoría (DropdownButton con 8 categorías), fotos (ImagePicker: cámara o galería, máx 5 imágenes).
2. Selector de ubicación: mini-mapa con pin arrastrable + botón "Usar mi ubicación GPS".
3. Vista previa antes de enviar.
4. Al confirmar:
   a. Subir fotos a Storage en /reports/{reportId}/citizen/
   b. Guardar el reporte en Firestore con los campos del modelo ReportModel
   c. Calcular geohash de la ubicación con geoflutterfire_plus
   d. Toast de confirmación y navegación a /my_reports
5. Validación: no más de 10 reportes del usuario en 24h (verificar lastReportAt en Firestore antes de guardar).

Las fotos deben comprimirse a máx 1200px antes de subir (usar flutter_image_compress).
</task>

<structured_output_contract>
- new_report_screen.dart
- report_form.dart
- photo_picker_widget.dart
- location_picker_widget.dart (mini mapa con pin)
- report_preview_screen.dart
- report_repository.dart (createReport, uploadPhotos)
</structured_output_contract>

<action_safety>
El permiso de cámara se pide con un dialog explicativo ANTES de llamar a ImagePicker.
El permiso de almacenamiento se pide solo en Android < 13 (en Android 13+ usar READ_MEDIA_IMAGES).
Agregar comentarios con las instrucciones de configuración de permisos en AndroidManifest.xml y Info.plist.
</action_safety>
```

---

## PROMPT 5 — Modo equipo de campo (diferencial)

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar el módulo de equipo de campo en lib/features/field/.

Este es el diferencial de la app: el técnico llega al sitio, documenta con fotos y resuelve desde el celular.

Pantallas y flujo:
1. FieldHomeScreen: lista de tareas asignadas al worker (filtro: pendientes / en progreso / resueltas hoy). Cada tarjeta muestra: título, categoría, distancia al punto GPS, estado.
2. TaskDetailScreen: ver el reporte completo + foto del ciudadano + botón "Navegar" (abre Google Maps con la ubicación exacta) + botón "Estoy en el lugar".
3. Al tocar "Estoy en el lugar":
   a. Actualiza el reporte: status=in_progress, workerArrivedAt=ahora
   b. Fuerza captura de foto del ANTES con la cámara (no galería, para que sea en tiempo real)
   c. Sube la foto a /reports/{reportId}/before/
4. WorkInProgressScreen: contador de tiempo activo, botón "Registrar foto del trabajo" (opcional, durante el trabajo), botón "Trabajo terminado".
5. Al tocar "Trabajo terminado":
   a. Fuerza captura de foto del DESPUÉS con la cámara
   b. Campo de texto para nota del técnico (opcional, máx 200 chars)
   c. Sube foto a /reports/{reportId}/after/
   d. Actualiza el reporte: status=resolved, workFinishedAt=ahora, workerNotes
   e. La Cloud Function onReportResolved envía el push al ciudadano

Restricción importante: las fotos del equipo de campo DEBEN ser tomadas con la cámara en ese momento (deshabilitar galería para before/after). Esto garantiza autenticidad.
</task>

<structured_output_contract>
- field_home_screen.dart
- task_card_widget.dart (con distancia en km)
- task_detail_screen.dart
- before_photo_capture_screen.dart
- work_in_progress_screen.dart
- after_photo_capture_screen.dart
- field_repository.dart (updateStatus, uploadFieldPhoto)
</structured_output_contract>

<verification_loop>
Verificar:
- [ ] La distancia al punto se actualiza en tiempo real con Geolocator
- [ ] La captura de foto before/after no permite seleccionar de galería
- [ ] Si se pierde la conexión, las fotos se guardan localmente y se sincronizan al recuperar (usar connectivity_plus + queue)
</verification_loop>
```

---

## PROMPT 6 — Detalle del reporte (ciudadano: ve el antes/después)

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar la pantalla de detalle del reporte en lib/features/report_detail/.

Contenido de la pantalla:
1. Header: título, categoría (chip con color), estado (chip con color), fecha.
2. Galería de fotos del ciudadano (PhotosReport) — deslizable.
3. Mini mapa con pin en la ubicación exacta.
4. Botón "Apoyar este reporte" (ícono de mano arriba + contador). Solo ciudadanos. Un voto por usuario.
5. Sección "Resolución" (visible solo si status = in_progress o resolved):
   - Foto del ANTES del equipo (photosBefore)
   - Foto del DESPUÉS del equipo (photosAfter) — visible solo si resolved
   - Nota del técnico (workerNotes)
   - Comparador ANTES/DESPUÉS: slider horizontal que permite ver ambas fotos superpuestas (before_after_slider)
6. Sección de respuesta oficial del coordinador (si existe, destacada con borde azul).
7. Sección de comentarios: lista + campo de texto para agregar comentario.
8. Si el reporte está resuelto y el ciudadano es el dueño y no calificó: BottomSheet de calificación (1-5 estrellas + comentario opcional).
9. Botón "Reportar como inapropiado" (ícono de bandera).

El comparador antes/después es el widget destacado de esta pantalla.
Usar el paquete before_after o implementar uno custom con Stack + GestureDetector.
</task>

<structured_output_contract>
- report_detail_screen.dart
- photos_gallery_widget.dart
- before_after_slider_widget.dart ← DIFERENCIAL, cuidarlo
- support_button_widget.dart
- resolution_section_widget.dart
- comments_section_widget.dart
- rating_bottom_sheet.dart
- report_flag_dialog.dart
</structured_output_contract>
```

---

## PROMPT 7 — Panel coordinador

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar el panel del coordinador en lib/features/coordinator/.

Este rol accede a todos los reportes del municipio y los asigna.

Pantallas:
1. CoordinatorHomeScreen: lista de reportes con filtros (estado, categoría, zona, prioridad). Ordenados por campo `priority` desc por defecto.
2. Al tocar un reporte: CoordinatorReportDetailScreen con todos los campos + historial de cambios de estado.
3. AssignTeamDialog: dropdown con equipos activos del municipio. Botón "Asignar".
4. Puede cambiar el estado manualmente: rechazar (con motivo obligatorio) o marcar como in_review.
5. Puede agregar respuesta oficial (texto) que aparece destacada en el reporte.
6. Estadísticas básicas (tab o pantalla aparte): cantidad por estado (pie chart), categorías más frecuentes (bar chart), tiempo promedio de resolución.

Usar fl_chart para los gráficos.
</task>

<structured_output_contract>
- coordinator_home_screen.dart
- coordinator_report_list.dart
- coordinator_report_detail_screen.dart
- assign_team_dialog.dart
- coordinator_stats_screen.dart
- coordinator_repository.dart (assignTeam, changeStatus, addOfficialResponse)
</structured_output_contract>
```

---

## PROMPT 8 — Notificaciones push

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar notificaciones push con Firebase Cloud Messaging en lib/data/services/fcm_service.dart y lib/features/notifications/.

Requerimientos:
1. Al iniciar la app: solicitar permiso de notificaciones (con dialog explicativo en Android 13+).
2. Guardar el FCM token en Firestore users/{uid}/fcmToken.
3. Manejar mensajes:
   - App en primer plano: mostrar notificación local con flutter_local_notifications
   - App en background/cerrada: notificación del sistema operativo, al tocarla navega al reporte correspondiente
4. NotificationsScreen: lista de notificaciones del usuario (colección notifications/{userId}), marcar como leídas al abrir.
5. Ícono con badge en la barra de navegación si hay notificaciones no leídas.

Cloud Functions (escribir el código Node.js para Firebase Functions):
- onReportAssigned: envía push al field_worker asignado
- onWorkerArrived: envía push al ciudadano "Tu problema está siendo atendido"
- onReportResolved: envía push al ciudadano "Tu problema fue resuelto, mirá el resultado"
- onOfficialResponse: envía push al ciudadano cuando el coordinador responde
</task>

<structured_output_contract>
Flutter:
- fcm_service.dart
- notifications_screen.dart
- notification_badge_widget.dart

Firebase Functions (functions/index.js o functions/src/index.ts):
- Función por cada trigger mencionado
- Cada función usa admin.messaging().send() con el fcmToken del destinatario
</structured_output_contract>

<verification_loop>
- [ ] El token se actualiza en Firestore cuando se renueva (onTokenRefresh)
- [ ] Las notificaciones deep-link al reporte correcto (reportId en el payload)
- [ ] Funciona en background en Android e iOS
</verification_loop>
```

---

## PROMPT 9 — Play Store: cumplimiento completo

```xml
<task>
Continuar el proyecto Flutter "¿Qué pasa en tu barrio?".
Implementar todo lo necesario para aprobar la revisión de Google Play Store.

Checklist a resolver:

1. ELIMINACIÓN DE CUENTA (obligatorio desde agosto 2023):
   - ProfileScreen → Configuración → "Eliminar mi cuenta"
   - Dialog de confirmación con texto de advertencia
   - La eliminación borra: Firebase Auth, Firestore users/{uid}, reportes del usuario (hidden=true, no borrado físico para no romper el historial del mapa), Storage users/{uid}/
   - URL de eliminación de cuenta (requerido por Play Store): crear una página web simple o usar Firebase Hosting para alojar una página con el formulario de baja

2. PERMISOS:
   - Ubicación: pedir solo cuando el usuario toca "Usar mi GPS" (no al inicio). Dialog explicativo previo.
   - Cámara: pedir solo cuando el usuario toca el botón de foto. Dialog explicativo previo.
   - Notificaciones: pedir al primer login, con explicación del beneficio.
   - Nunca pedir todos los permisos al inicio (play store policy violation)

3. CONTENIDO GENERADO POR USUARIOS:
   - Botón "Reportar" en cada reporte y comentario (ya incluido en prompts anteriores)
   - Política de moderación visible en la app (pantalla Acerca de / Términos)

4. POLÍTICA DE PRIVACIDAD:
   - URL pública requerida. Crear /assets/legal/privacy_policy.html
   - Enlace en RegisterScreen antes de "Crear cuenta"
   - Enlace en la ficha de Play Store

5. BUILD:
   - android/app/build.gradle: targetSdkVersion 35, compileSdkVersion 35, minSdkVersion 24
   - Generar keystore para firma del APK (instrucciones en comentarios)
   - Configurar flavors: development y production (Firebase projects distintos)
</task>

<structured_output_contract>
- profile_screen.dart con sección eliminar cuenta
- delete_account_dialog.dart
- permissions_service.dart (centraliza todos los permisos con rationale dialogs)
- about_screen.dart (términos, política de privacidad, versión)
- assets/legal/privacy_policy.html (borrador básico)
- android/app/build.gradle actualizado
- Instrucciones de keystore y firma como comentarios en el archivo build.gradle
</structured_output_contract>
```

---

## Orden de ejecución

| # | Prompt | Dependencias | Prioridad |
|---|--------|-------------|-----------|
| 1 | Estructura base | — | MVP |
| 2 | Autenticación | 1 | MVP |
| 3 | Mapa principal | 1, 2 | MVP |
| 4 | Crear reporte | 1, 2, 3 | MVP |
| 5 | Modo campo | 1, 2, 4 | MVP |
| 6 | Detalle reporte | 1, 2, 4, 5 | MVP |
| 7 | Panel coordinador | 1, 2, 4 | MVP |
| 8 | Notificaciones | 1, 2 | Fase 2 |
| 9 | Play Store | todos | Antes de publicar |
