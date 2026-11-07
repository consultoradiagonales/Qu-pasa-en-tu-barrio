# Checklist de publicación ConDi (Google Play y App Store)

Estado según el repo, versión 1.0.13+14 (`pubspec.yaml`). Leyenda: [x] cumplido en el repo, [ ] pendiente, [?] a confirmar por el titular.

## Google Play

### Cuenta y pruebas
- [?] Cuenta de desarrollador de Play Console creada y verificada (pago único USD 25). La ficha lo lista como pendiente.
- [?] Tipo de cuenta: **personal** (si es cuenta personal creada después de noviembre de 2023).
- [ ] **Prueba cerrada con al menos 12 testers durante 14 días continuos** (requisito para cuentas personales antes de pedir acceso a producción). El repo registra solo una prueba interna: https://play.google.com/apps/internaltest/4701647237677047143 (`plataformas/Android/README.md`). Los testers deben aceptar la invitación y mantenerse inscriptos los 14 días.
- [ ] Solicitar acceso a producción en Play Console una vez cumplidos los 14 días y completar el cuestionario de la prueba.

### Binario
- [x] Paquete `ar.com.consultoradiagonales.condi`.
- [x] AAB generado (`build/app/outputs/bundle/release/app-release.aab`; hay AAB de 1.0.9 y 1.0.10 en `plataformas/Android`). [?] Confirmar que el AAB 1.0.13+14 esté subido.
- [?] Nivel de API objetivo vigente exigido por Google (verificar en `android/app/build.gradle` y en el aviso de Play Console).
- [ ] Agregar la huella **SHA-1 de Play App Signing** en Firebase (si no, falla el inicio de sesión con Google en la versión descargada). Ver `store_assets/FICHA_PLAY_STORE.md`.
- [x] App Check con Play Integrity en release (`lib/main.dart`).

### Ficha de la tienda
- [x] Nombre, descripciones corta y larga redactadas (`store_assets/FICHA_PLAY_STORE.md`).
- [x] Ícono 512x512 (`store_assets/icon_512.png`).
- [x] Gráfico destacado 1024x500 (`store_assets/feature_graphic_1024x500.png`).
- [ ] Capturas de teléfono: hay 3 en `store_assets/screenshots` (bienvenida, iniciar sesión, crear cuenta). Play pide mínimo 2 (se cumple el mínimo), pero conviene sumar capturas de mapa, reporte y seguimiento. Tablet 7"/10" opcionales.
- [x] Correo de contacto: info.consultoradiagonales@gmail.com.
- [x] Categoría definida (Estilo de vida; alternativa Noticias y revistas).
- [x] Países de distribución: Argentina.

### Política y datos
- [ ] **URL de política de privacidad pública y funcional.** La app y la ficha apuntan a https://consultoradiagonales.com.ar/app/privacidad.html. Borrador listo en `POLITICA_DE_PRIVACIDAD.md`; falta aprobar y publicar (no publicado por este trabajo). Debe ser una página web (no PDF) accesible sin login y coherente con el formulario.
- [x] Enlace a la política dentro de la app (Mi perfil y pantalla de bienvenida).
- [ ] **Formulario "Seguridad de los datos"**: respuestas listas en `PLAY_DATA_SAFETY.md`; falta cargarlas en Play Console tras resolver los [A CONFIRMAR].

### Eliminación de cuenta (política de Play)
- [x] Eliminación dentro de la app (Mi perfil → Eliminar mi cuenta).
- [ ] **URL web de eliminación de cuenta** (https://consultoradiagonales.com.ar/app/eliminar-cuenta.html está referenciada en el código pero hay que publicarla y declararla en Play Console).
- [ ] Revisar el alcance del borrado: hoy `deleteUserData` oculta los reportes y borra el perfil de Firestore, y luego se elimina la cuenta de Auth. No se eliminan fotos de Storage, comentarios, notificaciones ni el registro `userDevices`. Play y la política exigen decir con claridad qué se elimina y qué se conserva. Decisión del titular.

### Permisos declarados (`AndroidManifest.xml`)
- [x] INTERNET, ACCESS_NETWORK_STATE.
- [x] CAMERA (fotos de reportes).
- [x] ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION (primer plano, ubicación del reporte).
- [x] POST_NOTIFICATIONS (Android 13+).
- [x] RECEIVE_BOOT_COMPLETED (notificaciones locales programadas).
- [x] Sin ubicación en segundo plano ni permisos de SMS/contactos/archivos amplios.
- [ ] Si Play pide justificación de algún permiso, usar los textos del apartado de permisos del formulario.

### Clasificación y declaraciones
- [ ] **Cuestionario de clasificación de contenido (IARC)** pendiente de completar. Guía en la ficha (UGC: sí; resto: no). Resultado esperado: todo público.
- [?] Declaración de anuncios: la ficha dice "Sí, comunicaciones locales identificadas".
- [ ] Declaración de público objetivo y contenido (no dirigida a niños). Definir edad mínima [A CONFIRMAR].
- [ ] Declaración de app gubernamental/servicios: ConDi es de una consultora privada, no de un organismo; si Play lo consulta, declarar que no representa a un gobierno. [A CONFIRMAR]
- [x] Moderación de contenido generado por usuarios: existe denuncia (`contentFlags`) y roles de moderación en las reglas de Firestore.

## Apple App Store

### Cuenta
- [?] Cuenta de Apple Developer Program (hay capturas de la membresía en el repo; confirmar estado).
- [x] Bundle ID registrado `ar.com.consultoradiagonales.condi`.

### Build
- [x] Firebase plist incluido, Google Sign-In con URL scheme, Google Maps inicializado, deployment target iOS 15 (`plataformas/iOS/IOS_RELEASE_CHECKLIST.md`).
- [ ] `pod install` y `flutter build ipa --release` en Mac (pendiente según el checklist de iOS).
- [ ] Probar en un iPhone físico y distribuir por TestFlight.
- [x] Textos de uso declarados en `Info.plist`: cámara, ubicación mientras se usa, fotos y agregar fotos. (Hay un problema de codificación de tildes en esos textos: aparecen como "Ã¡" en el archivo; revisar la codificación UTF-8 antes de enviar.)
- [x] UIBackgroundModes `remote-notification` para push.
- [?] Capability de Push Notifications y clave APNs cargada en Firebase.
- [ ] **PrivacyInfo.xcprivacy** inexistente en `ios/Runner/`: agregar (Apple lo exige).
- [x] App Check con DeviceCheck en release.

### Ficha y datos
- [ ] Capturas por tamaño de pantalla requerido (iPhone 6,9"/6,7" y 6,5"; iPad si se soporta iPad).
- [ ] Descripción, palabras clave, URL de soporte, categoría. Se puede reutilizar texto de Play.
- [ ] URL de política de privacidad (propuesta arriba, a publicar).
- [ ] **Etiquetas de privacidad**: respuestas listas en `APPLE_PRIVACY_LABELS.md`.
- [ ] Clasificación por edad (cuestionario de App Store Connect).
- [x] Eliminación de cuenta dentro de la app (exigida por Apple, guideline 5.1.1(v)).
- [ ] **Sign in with Apple**: la app ofrece inicio con Google; Apple exige ofrecer una opción equivalente que limite la recolección (Sign in with Apple) salvo que aplique una excepción. No está implementado (`auth_service.dart` solo usa correo y Google). Decisión del titular.
- [ ] Datos de acceso de prueba para el revisor (cuenta demo con municipio asignado).
- [ ] Contenido generado por usuarios: Apple (1.2) pide filtro, mecanismo de denuncia, bloqueo y contacto. Existe denuncia y moderación; [?] confirmar disponibilidad de bloqueo de usuarios.

## Documentación pendiente de decisión del titular
1. Razón social, CUIT y domicilio para la política.
2. Publicar privacidad y eliminación de cuenta en consultoradiagonales.com.ar/app/.
3. Edad mínima.
4. Alcance de eliminación al borrar la cuenta (fotos, comentarios, notificaciones, `userDevices`).
5. Plazos de conservación.
6. Inscripción de la base de datos ante la AAIP.
7. Sign in with Apple.
8. Confirmar si hay teléfono, analítica o crash reporting no visibles en el código.
