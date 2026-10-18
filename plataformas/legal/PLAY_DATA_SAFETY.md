# Google Play: formulario "Seguridad de los datos" (ConDi 1.0.13+14)

Respuestas derivadas del código. Deben coincidir con la Política de Privacidad. Los puntos [A CONFIRMAR] requieren decisión del titular.

## Preguntas generales

| Pregunta | Respuesta |
|---|---|
| ¿La app recopila o comparte alguno de los tipos de datos requeridos? | Sí |
| ¿Todos los datos se cifran en tránsito? | Sí (HTTPS/TLS con Firebase y APIs de Google) |
| ¿Ofrecés una forma de que los usuarios soliciten la eliminación de sus datos? | Sí: en la app (Mi perfil → Eliminar mi cuenta) y URL web https://consultoradiagonales.com.ar/app/eliminar-cuenta.html [A CONFIRMAR: la página debe estar publicada antes de enviar] |
| ¿Cumple la política de Familias? | No aplica (no está dirigida a niños) |
| Verificación independiente de seguridad | No |

Notas de criterio: en Play, los datos procesados por proveedores de servicio que actúan por cuenta del desarrollador (Firebase) **no cuentan como "compartidos"**. Por eso todo se declara como "no compartido", salvo lo indicado en Gemini.

## Por tipo de dato

| Categoría / tipo | ¿Recopilado? | ¿Compartido? | Obligatorio / opcional | Finalidad | Cifrado en tránsito | Borrado a pedido |
|---|---|---|---|---|---|---|
| Información personal: **Nombre** (nombre real y nombre público) | Sí | No | Obligatorio (nombre real al registrarse) [A CONFIRMAR si es obligatorio] | Funcionalidad de la app; gestión de la cuenta | Sí | Sí |
| Información personal: **Dirección de correo** | Sí | No | Obligatorio | Gestión de la cuenta; funcionalidad de la app | Sí | Sí |
| Información personal: **ID de usuario** (UID de Firebase) | Sí | No | Obligatorio | Funcionalidad de la app; gestión de la cuenta | Sí | Sí |
| Información personal: **Número de teléfono** | No | No | n/d | n/d (el código no lo recolecta) | n/d | n/d |
| Información personal: **Otros** (municipio, localidad y provincia elegidos en el perfil) | Sí | No | Obligatorio (para asignar reportes) | Funcionalidad de la app; analíticas agregadas (solo con consentimiento) | Sí | Sí |
| Ubicación: **Ubicación aproximada** | Sí | No | Opcional | Funcionalidad de la app (mapa, reportes) | Sí | Sí (se elimina al borrar la cuenta o el reporte) [A CONFIRMAR] |
| Ubicación: **Ubicación precisa** | Sí (coordenadas del reporte; el permiso es opcional) | No | Opcional | Funcionalidad de la app | Sí | Sí [A CONFIRMAR: ver retención de reportes] |
| Fotos y videos: **Fotos** | Sí | No | Opcional | Funcionalidad de la app (adjuntar a reportes) | Sí | Parcial: ver nota de retención [A CONFIRMAR] |
| Mensajes: **Otros mensajes dentro de la app** (descripción de reportes, comentarios) | Sí | No | Opcional (comentarios); obligatorio en reportes [A CONFIRMAR] | Funcionalidad de la app | Sí | Parcial [A CONFIRMAR] |
| Actividad en la app: **Interacciones en la app** (conteo diario de uso por municipio) | Sí, solo con consentimiento | No | Opcional | Analíticas (agregadas) | Sí | Sí (retirar consentimiento borra el registro personal; los conteos agregados no son identificables) |
| Actividad en la app: **Contenido generado por el usuario** (reportes, apoyos) | Sí | No | Opcional | Funcionalidad de la app | Sí | Parcial [A CONFIRMAR] |
| Identificadores de dispositivo u otros: **Token de notificaciones (FCM)** | Sí | No | Opcional (depende del permiso de notificaciones) | Funcionalidad de la app (notificaciones) | Sí | Sí |
| Información y rendimiento de la app: **Registros de fallos / diagnóstico** | [A CONFIRMAR]: en el código no hay Crashlytics; Google Cloud puede registrar logs de servidor | No | n/d | Seguridad / mantenimiento | Sí | n/d |
| Dirección IP | No se almacena en datos de ConDi. (Google/Firebase puede procesarla técnicamente; no se declara como dato recopilado por la app) [A CONFIRMAR con asesor] | No | n/d | n/d | Sí | n/d |
| Información financiera, salud, contactos, calendario, audio, archivos, SMS, historial de navegación, contenido web | No | No | n/d | n/d | n/d | n/d |

## Compartido: tratamiento de Gemini (IA)

El envío de la primera foto y la descripción del reporte a Google Gemini (Vertex AI) ocurre bajo el proyecto Google Cloud propio de ConDi, como proveedor de servicio. Google lo considera "tratamiento por proveedor de servicios", por lo que **no se declara como compartido**. [A CONFIRMAR: verificar en los términos de Vertex AI que los datos no se usan para entrenar modelos; si hubiera dudas, declarar como "compartido" Fotos, Mensajes y Ubicación aproximada con finalidad "Funcionalidad de la app".]

## Otras declaraciones de Play Console

- **Permisos declarados en el manifest:** INTERNET, ACCESS_NETWORK_STATE, CAMERA, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED. No hay permisos sensibles de segundo plano; no se necesita declaración especial de ubicación en segundo plano. (Verificado en `android/app/src/main/AndroidManifest.xml`.)
- **Anuncios:** la ficha existente declara "Sí, comunicaciones o promociones locales identificadas" (publicidad propia cargada por administrador). No hay SDK publicitario en `pubspec.yaml`. Coherente con política: no se usa el ID de publicidad. [A CONFIRMAR: ¿se declara "contiene anuncios"? Se mantiene "Sí" por prudencia.]
- **ID de publicidad:** no se usa.
- **Declaración de eliminación de cuenta:** nombre de la app + URL web de eliminación (ver arriba).
- **Función de IA / contenido generado por usuarios:** la app tiene contenido generado por usuarios (reportes y comentarios públicos entre usuarios con sesión) y herramienta de reporte (`contentFlags`). Verificar la política de UGC: debe haber mecanismo de denuncia y moderación (existe: marcado de contenido y moderadores).

## Notas de coherencia con documentos previos

`store_assets/FICHA_PLAY_STORE.md` declara además "Identificadores del dispositivo, obligatorio, notificaciones" y "Acciones en la app". Aquí se interpretan como token FCM (opcional, depende del permiso) y conteo de uso con consentimiento (opcional).
