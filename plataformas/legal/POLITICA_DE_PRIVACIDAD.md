# Política de Privacidad de ConDi

**Versión:** borrador 1.0 para revisión del titular (basado en la app 1.0.13+14)
**Última actualización:** [A CONFIRMAR: fecha de publicación]
**URL de publicación propuesta:** https://consultoradiagonales.com.ar/app/privacidad.html
(es la URL que la app ya referencia en `lib/core/constants/app_constants.dart`; NO está publicada por este documento: la publicación queda pendiente de decisión del titular)
**URL de eliminación de cuenta propuesta:** https://consultoradiagonales.com.ar/app/eliminar-cuenta.html (también ya referenciada en la app)

> Nota interna (borrar antes de publicar): este texto describe lo que el código de la app y de las Cloud Functions hace realmente. Donde el código no permite confirmar un dato, figura como [A CONFIRMAR]. Se recomienda revisión final por un abogado matriculado.

---

## 1. Quiénes somos

ConDi es una aplicación ciudadana para reportar problemas urbanos (baches, luminarias, basura, etc.) y seguir su estado. Es un desarrollo de **Consultora Diagonales**, con base en La Plata, Provincia de Buenos Aires, Argentina.

- **Responsable del tratamiento de los datos:** Consultora Diagonales [A CONFIRMAR: razón social completa, CUIT y domicilio legal para consignar].
- **Contacto para temas de privacidad:** info.consultoradiagonales@gmail.com

Esta política se rige por la **Ley 25.326 de Protección de los Datos Personales** de la República Argentina y su normativa complementaria.

## 2. Qué datos tratamos y para qué

### 2.1 Cuenta de usuario (necesaria para usar la app)
- **Correo electrónico y contraseña**, o **cuenta de Google** (inicio de sesión con Google). La contraseña la gestiona Firebase Authentication; nosotros no la vemos.
- **Nombre real** que cargues al registrarte y, si usás Google, la foto de perfil asociada. [A CONFIRMAR: qué campos exactos se guardan al registrarse con Google (nombre y foto de Google) según `auth_service.dart`.]
- **Nombre público de usuario** generado por la app (del tipo "Usuario #XXXX"). Es el único nombre que ven los demás vecinos. Tu nombre real y tu correo no se muestran a otros vecinos.
- **Municipio, localidad y provincia que elegís** en tu perfil. Sirven para mostrarte los reportes de tu zona, dirigir tus reportes al municipio correspondiente y enviarte avisos de tu zona.
- **Rol de la cuenta** (vecino, personal municipal, etc.) y contador de reportes.

**Finalidad:** crear y gestionar tu cuenta, identificar tus reportes y darte acceso a las funciones de la app.

### 2.2 Reportes (lo que vos decidís publicar)
- **Fotos** que adjuntes.
- **Ubicación del problema**: coordenadas elegidas en el mapa o tomadas de tu ubicación si habilitás el permiso, y una dirección o referencia escrita por vos.
- **Texto** (descripción), categoría y comentarios.

**Importante:** los reportes son visibles para las demás personas que hayan iniciado sesión en la app (junto con tu nombre público de usuario), con su foto, ubicación y texto. No incluyas en las fotos ni en el texto datos personales de terceros (rostros, patentes, teléfonos, domicilios).

**Finalidad:** registrar el reclamo, mostrarlo en el mapa, que el municipio lo gestione y que puedas seguir su estado.

### 2.3 Ubicación del dispositivo
Solo si concedés el permiso de ubicación (precisa o aproximada), la app la usa para ubicar un reporte y centrar el mapa. **No** hacemos seguimiento de tu ubicación en segundo plano. Podés usar la app escribiendo una dirección o eligiendo un punto en el mapa sin otorgar el permiso.

### 2.4 Ayuda de inteligencia artificial en los reportes (opcional)
Al crear un reporte aparece la opción "Ayuda de IA de ConDi". Si la dejás activada, la **primera foto** y la **descripción** de tu reporte, junto con la categoría elegida, se envían al modelo **Google Gemini (servicio Vertex AI de Google Cloud)** para generar un resumen del problema, una sugerencia de categoría y una respuesta amable. Se registra la versión del consentimiento (`aiConsentVersion`) junto con el reporte.

- Es **opcional**: si la desactivás, tu reporte se envía igual.
- El resultado puede equivocarse; es orientativo y **no** implica que el municipio haya recibido o aceptado el reporte.
- La IA no modifica la categoría que elegiste ni el estado del reclamo.
- Se aplican límites diarios de uso por persona y globales.
- Para este tratamiento no se envía a la IA tu nombre, correo ni ubicación exacta. [A CONFIRMAR: condiciones contractuales de Google sobre uso de datos de Vertex AI para entrenamiento; confirmar con la documentación de la cuenta de Google Cloud.]
- Además, el panel de gestión municipal puede generar informes de IA a partir de **datos agregados y anonimizados** de reportes (por zona, sin coordenadas, direcciones ni textos).

### 2.5 Notificaciones
Si permitís las notificaciones, guardamos un **token de notificaciones push (Firebase Cloud Messaging)** asociado a tu cuenta para avisarte cuando tu reclamo avanza, enviarte mensajes del municipio y alertas. También guardamos tus notificaciones dentro de la app.

### 2.6 Alertas de clima
Para tu municipio, un proceso automático consulta pronósticos (Open-Meteo y MET Noruega) usando **las coordenadas del centro del municipio**, no tu ubicación personal. Si hay riesgo, enviamos una alerta a los vecinos de ese municipio. Para ello usamos el municipio que elegiste y tu token de notificaciones.

### 2.7 Medición territorial de uso (opcional)
Después de iniciar sesión te preguntamos si aceptás una medición mínima de uso. Si aceptás, se registra **como máximo un conteo por día** asociado a la ciudad o municipio de tu perfil y se guarda un registro de tu consentimiento (versión y fecha). El equipo de gestión solo ve resultados agregados, y las ciudades se detallan únicamente cuando hay al menos tres usuarios activos el mismo día.

Para esta medición **no** guardamos dirección IP, ubicación exacta, fotos, correo, nombre, teléfono ni identificadores del dispositivo. (Versiones anteriores del consentimiento podían guardar más datos; al actualizarlo, esos campos se eliminan.)

### 2.8 Datos técnicos
La infraestructura de Google (Firebase, Google Cloud) puede procesar datos técnicos de conexión (como dirección IP, tipo de dispositivo y versión de la app) para prestar el servicio, proteger la aplicación y registrar errores. ConDi no usa esos datos para perfilarte. [A CONFIRMAR: si se usan Firebase Analytics, Crashlytics u otras herramientas; en el código revisado no figuran como dependencias.]

**App Check:** la app utiliza Firebase App Check (Play Integrity en Android y DeviceCheck en iOS) para comprobar que las solicitudes provienen de la app auténtica y evitar abusos.

### 2.9 Teléfono
[A CONFIRMAR: el código revisado no solicita ni guarda un teléfono en la versión actual. Si en el futuro se agregara un teléfono opcional, deberá declararse aquí. Hasta entonces, no se recolecta.]

## 3. Base legal: tu consentimiento

Tratamos tus datos sobre la base de tu **consentimiento libre, expreso e informado** (art. 5 de la Ley 25.326), que das al crear tu cuenta, al aceptar esta política, al conceder los permisos del dispositivo y al activar las opciones de IA y de medición territorial. Las opciones de IA y de medición son separadas y podés rechazarlas sin perder acceso a la app.

## 4. Quién puede ver tus datos

| Dato | Quién lo ve |
|---|---|
| Reportes (foto, ubicación, texto, nombre público) | Personas con sesión iniciada en la app. Los reportes ocultos solo los ven su autor y el personal municipal autorizado. |
| Comentarios y apoyos a reportes | Personas con sesión iniciada. |
| Tu perfil completo (nombre real, correo, municipio, token de notificaciones) | Vos, el personal de gestión autorizado (coordinador, moderador, administrador) y los sistemas de ConDi. Los demás vecinos no. |
| Resultado de IA de un reporte | El autor del reporte y el personal del municipio correspondiente. |
| Notificaciones | Solo vos. |
| Registro de consentimiento de medición | Solo el administrador de ConDi. |
| Conteos de uso territorial | Solo en forma agregada, a personal de gestión. No son accesibles desde la app. |
| Cuadrillas de trabajo y fotos de trabajos | Personal autorizado; las fotos de los reportes son visibles para usuarios con sesión. |

El personal municipal solo accede a los datos de su propio municipio, salvo el administrador de ConDi.

## 5. Con quién compartimos o a quién encargamos datos

No vendemos tus datos. Usamos proveedores que tratan datos por cuenta nuestra:

- **Google Firebase / Google Cloud** (Authentication, Firestore, Storage, Cloud Functions, Cloud Messaging, App Check): alojamiento, cuenta, base de datos, fotos, notificaciones y seguridad.
- **Google Sign-In**: si elegís ingresar con Google.
- **Google Maps**: mapas dentro de la app (se comunica con Google para cargar el mapa).
- **Google Gemini (Vertex AI)**: interpretación de reportes con IA, solo si lo activás, y generación de informes agregados para gestión.
- **GeoRef (Gobierno argentino, apis.datos.gob.ar)**: búsqueda de municipios y localidades. [A CONFIRMAR: qué datos se envían (se espera solo el texto de búsqueda de municipio/localidad y no datos personales).]
- **Open-Meteo y MET Noruega (api.met.no)**: pronóstico del tiempo; reciben solo coordenadas del centro del municipio, sin datos personales.
- **Publicidad local:** la app puede mostrar comunicaciones o promociones locales identificadas, cargadas por el administrador. No se comparten tus datos personales con los anunciantes. [A CONFIRMAR: no hay SDK publicitario en el código; confirmar que se mantiene así.]
- **Municipios:** los reportes y su gestión son visibles para el personal del municipio al que corresponden, para que puedan atenderlos.

También podemos revelar datos cuando una autoridad competente lo exija legalmente.

## 6. Transferencia internacional de datos

Nuestros servidores están en Google Cloud, región **São Paulo, Brasil** (`southamerica-east1`) y algunos servicios de Google (por ejemplo, el modelo de IA Gemini, que se invoca en el punto de acceso global de Vertex AI) pueden procesar datos en otros países, incluidos Estados Unidos. Esto implica una transferencia internacional de datos. La realizamos con tu consentimiento (art. 12 de la Ley 25.326) y mediante proveedores con estándares de seguridad reconocidos. [A CONFIRMAR: revisión legal de las garantías contractuales aplicables (cláusulas modelo de la AAIP, Disposición 60-E/2016 o la que corresponda).]

## 7. Cuánto tiempo conservamos los datos

- **Cuenta y perfil:** mientras la cuenta esté activa; se eliminan al borrar la cuenta.
- **Reportes:** los reportes son un registro público de reclamos urbanos. Al eliminar tu cuenta, tus reportes dejan de mostrarse (se ocultan), pero los registros y las fotos pueden conservarse de forma interna [A CONFIRMAR: plazo de conservación y si se desea eliminar definitivamente reportes, fotos, comentarios y notificaciones al borrar la cuenta; hoy el código solo oculta los reportes y borra el perfil].
- **Resultados de IA:** se conservan junto al reporte. [A CONFIRMAR: plazo.]
- **Consentimiento de medición:** hasta que lo retires o borres la cuenta. Los conteos agregados históricos no identifican personas y se conservan.
- **Registros técnicos:** según las políticas de retención de Google Cloud. [A CONFIRMAR]

## 8. Tus derechos

Como titular de los datos tenés derecho a **acceder** a tus datos, **rectificarlos**, **actualizarlos** y **suprimirlos** (arts. 14 a 16 de la Ley 25.326), y a **retirar tu consentimiento** en cualquier momento. El acceso es gratuito a intervalos no inferiores a seis meses, salvo interés legítimo acreditado.

Para ejercerlos escribí a **info.consultoradiagonales@gmail.com** indicando el correo de tu cuenta. Responderemos en los plazos de la ley (10 días corridos para el acceso y 5 días hábiles para rectificación o supresión).

**Autoridad de control:** la **Agencia de Acceso a la Información Pública (AAIP)**, órgano de control de la Ley 25.326, tiene la atribución de atender denuncias y reclamos de quienes consideren vulnerados sus derechos de protección de datos personales. Sitio: www.argentina.gob.ar/aaip.

> Texto legal usual en Argentina (verificar que coincide con la versión vigente): "La AGENCIA DE ACCESO A LA INFORMACIÓN PÚBLICA, en su carácter de Órgano de Control de la Ley N° 25.326, tiene la atribución de atender las denuncias y reclamos que interpongan quienes resulten afectados en sus derechos por incumplimiento de las normas vigentes en materia de protección de datos personales." [A CONFIRMAR: inscripción de la base de datos en el Registro Nacional de Bases de Datos, si corresponde, y número de inscripción.]

## 9. Cómo eliminar tu cuenta y retirar consentimientos

- **Eliminar la cuenta:** en la app, **Mi perfil → Eliminar mi cuenta**. Se elimina tu perfil y tu acceso, y tus reportes dejan de ser visibles. Si hace mucho que iniciaste sesión, la app puede pedirte cerrar sesión y volver a entrar antes de eliminar. También podés pedirlo por correo a info.consultoradiagonales@gmail.com o desde la URL pública de eliminación de cuenta.
- **Retirar el consentimiento de medición territorial:** en la app, **Mi perfil → Medición territorial de uso**. Al retirarlo se borra el registro personal de consentimiento.
- **IA:** desactivá "Ayuda de IA de ConDi" en cada reporte nuevo. No se aplicará a futuros reportes. Para reportes ya enviados, pedinos la supresión por correo.
- **Permisos (cámara, fotos, ubicación, notificaciones):** podés revocarlos en los ajustes del sistema de tu teléfono en cualquier momento.

## 10. Menores de edad

ConDi no está dirigida a menores de 13 años y no recolectamos conscientemente datos de ellos. [A CONFIRMAR: edad mínima de uso que defina el titular (por ejemplo, 13 o 16 años o mayores de edad, con autorización de madres, padres o tutores para adolescentes) y si la app incorporará una verificación de edad; el código revisado no la tiene.] Si sos madre, padre o tutor y creés que un menor nos dio datos, escribinos para eliminarlos.

## 11. Seguridad

Las comunicaciones se cifran en tránsito (HTTPS/TLS). Los datos se guardan en Google Cloud con reglas de acceso por rol, controles de que cada persona solo modifique su propia información, App Check y límites de uso. Ningún sistema es infalible; ante un incidente que afecte tus datos te informaremos según la ley.

## 12. Cambios en esta política

Si cambiamos esta política de forma relevante, lo vamos a avisar en la app y, cuando el cambio requiera nuevo consentimiento, volveremos a pedirlo.

## 13. Contacto

Consultora Diagonales, La Plata, Buenos Aires, Argentina
info.consultoradiagonales@gmail.com
