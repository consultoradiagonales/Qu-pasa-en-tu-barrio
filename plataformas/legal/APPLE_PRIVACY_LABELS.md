# Apple App Store Connect: Etiquetas de privacidad (ConDi 1.0.13+14)

Derivado del código. Debe coincidir con la política de privacidad y con el archivo `PrivacyInfo.xcprivacy` (ver pendiente al final).

**Pregunta inicial:** "¿Recopilan datos de esta app?" → **Sí**.
**Seguimiento (tracking):** **No**. ConDi no usa datos para seguimiento entre apps ni los comparte con data brokers, ni usa IDFA. Por eso no se necesita App Tracking Transparency.

En Apple, "datos vinculados a la identidad" = asociados a la cuenta del usuario. Ninguno de los datos siguientes se usa para seguimiento.

## Datos recopilados

| Tipo de dato (Apple) | ¿Recopilado? | Vinculado a la identidad | Para seguimiento | Finalidades |
|---|---|---|---|---|
| Información de contacto: **Nombre** | Sí | Sí | No | Funcionalidad de la app; gestión de cuenta |
| Información de contacto: **Dirección de correo** | Sí | Sí | No | Funcionalidad de la app |
| Información de contacto: **Número de teléfono** | No (no lo recolecta el código) | n/d | n/d | n/d |
| Información de contacto: Dirección física | No (la dirección de un reporte es del lugar del problema; ver Ubicación) | n/d | n/d | n/d |
| Ubicación: **Ubicación precisa** | Sí (opcional, solo si el usuario da permiso o fija el punto) | Sí (asociada al reporte) | No | Funcionalidad de la app |
| Ubicación: **Ubicación aproximada** | Sí (municipio/localidad del perfil) | Sí | No | Funcionalidad de la app; analíticas agregadas (solo con consentimiento) |
| Contenido del usuario: **Fotos o videos** | Sí | Sí | No | Funcionalidad de la app |
| Contenido del usuario: **Otro contenido del usuario** (descripción y comentarios) | Sí | Sí | No | Funcionalidad de la app |
| Identificadores: **ID de usuario** | Sí | Sí | No | Funcionalidad de la app |
| Identificadores: **ID de dispositivo** | Sí: token de notificaciones push (FCM/APNs) [A CONFIRMAR si se declara como ID de dispositivo; recomendado declarar por prudencia] | Sí | No | Funcionalidad de la app (notificaciones) |
| Datos de uso: **Interacción con el producto** | Sí, solo con consentimiento (conteo diario por municipio) | No vinculado: los conteos son agregados [A CONFIRMAR: se guarda además un registro de consentimiento por cuenta; para prudencia puede declararse como "vinculado"] | No | Analíticas |
| Diagnósticos (fallos, rendimiento) | [A CONFIRMAR]: no hay Crashlytics en `pubspec.yaml` | n/d | n/d | n/d |
| Compras, información financiera, salud y estado físico, contactos, búsquedas, historial de navegación, datos sensibles | No | n/d | n/d | n/d |

## Notas de criterio
- Apple solicita declarar los datos recopilados por SDK de terceros también (Firebase, Google Sign-In, Google Maps). Los tipos de arriba cubren esos casos. Google Maps puede procesar datos de uso del mapa y dirección IP; [A CONFIRMAR con el manifiesto de privacidad del SDK de Google Maps para iOS: puede requerir declarar "Datos de uso/Otros datos" y "Diagnósticos"].
- Envío de foto + texto a Google Gemini (solo con interruptor de IA activo): es tratamiento por proveedor de servicios de ConDi; se declara dentro de "Fotos o videos" y "Otro contenido del usuario" con finalidad "Funcionalidad de la app".
- Firebase Authentication con Google: Apple exige **Sign in with Apple** cuando se ofrecen inicios de sesión de terceros (Guideline 4.8), salvo excepciones (por ejemplo, un servicio propio de cuentas). Ver `CHECKLIST_PUBLICACION.md`.

## URL de política de privacidad (App Store Connect)
Propuesta: https://consultoradiagonales.com.ar/app/privacidad.html (a definir y publicar por el titular).

## Pendiente técnico (no se tocó el código)
No existe `ios/Runner/PrivacyInfo.xcprivacy`. Apple exige un manifiesto de privacidad con las "required reason APIs" que use la app (por ejemplo `UserDefaults`/shared_preferences y las de los SDK). Debe agregarse antes del envío a revisión (decisión y cambio de código del equipo de desarrollo).
