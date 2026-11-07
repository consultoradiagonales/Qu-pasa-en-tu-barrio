# Subir ConDi al App Store sin tener una Mac

Todo el código de iOS ya está listo (bundle id, íconos, permisos, Firebase,
Google Maps, Google Sign-In). Lo único que falta es **compilar y firmar**, que
Apple solo permite desde macOS. Se resuelve con Codemagic, un servicio que
presta la Mac en la nube.

## 0. Confirmar que el pago se hizo

La captura que mandaste es la pantalla de revisión, con "Place Order" todavía
sin presionar. Para saber si se cobró:

- Buscá en `info.consultoradiagonales@gmail.com` el mail de Apple
  "Welcome to the Apple Developer Program" o el recibo.
- O entrá a https://developer.apple.com/account : si ves "Certificates,
  Identifiers & Profiles" habilitado, la membresía está activa. Si dice
  "Enrollment pending" o te pide pagar, falta.

La matrícula es **MY483Q9FNY**. Son USD 99 por año.

## 1. El nombre: qué se puede y qué no

Apple separa cuatro lugares donde aparece un nombre. Tres se controlan; uno no.

| Dónde | Qué muestra | ¿Se puede poner ConDi? |
|---|---|---|
| Debajo del ícono en el iPhone | `CFBundleDisplayName` | **Sí, ya está: "ConDi"** |
| Título en la ficha del App Store | Nombre de la app (máx. 30 caracteres) | **Sí**, si no está tomado |
| Subtítulo en la ficha | Máx. 30 caracteres | **Sí**: "Reportá lo que pasa en tu barrio" |
| Línea "Vendedor" / "Seller" | Nombre legal de la cuenta | **No** con cuenta individual |

El **vendedor** sale del nombre legal inscripto en la cuenta, o sea
*Fernando Juan Genazzini*. Apple no acepta nombres comerciales ni de fantasía
en cuentas individuales. Para que figure "Consultora Diagonales" habría que ser
una entidad legal inscripta y enrolarse como organización (pide número D-U-N-S).

**Cómo mostrar la marca igual:**

- **Copyright** (campo libre de la ficha): `© 2026 Consultora Diagonales`
- **URL de soporte** y **URL de marketing**: `https://consultoradiagonales.com.ar`
- **Descripción**: la ficha ya redactada menciona a la consultora
- Si el nombre "ConDi" estuviera tomado en el App Store, usar
  `ConDi: reportes de tu barrio`. El nombre bajo el ícono sigue siendo ConDi.

## 2. Una sola vez en el sitio de Apple (navegador)

### 2.1 Registrar el identificador de la app
https://developer.apple.com/account/resources/identifiers/list

1. `+` → **App IDs** → **App**
2. Description: `ConDi`
3. Bundle ID, opción **Explicit**: `ar.com.consultoradiagonales.condi`
4. Capabilities: dejá las que vienen marcadas (más abajo, Sign in with Apple,
   si decidís agregarlo)
5. Continue → Register

### 2.2 Crear la ficha de la app
https://appstoreconnect.apple.com → **Apps** → `+` → **Nueva app**

- Plataformas: iOS
- Nombre: `ConDi`
- Idioma principal: Español (Latinoamérica)
- Bundle ID: el de arriba (aparece en la lista si hiciste 2.1)
- SKU: `condi-ios-001` (interno, nadie lo ve)
- Acceso: Completo

Cuando se cree, andá a **Información de la app** y copiá el **ID de Apple**
(un número de 10 dígitos). Va en `codemagic.yaml`, en `APP_STORE_APPLE_ID`.

### 2.3 Crear la llave de API para Codemagic
https://appstoreconnect.apple.com/access/integrations/api

1. **Generar clave de API** → nombre `Codemagic` → acceso **Administrador**
   (alcanza con "App Manager")
2. Descargá el archivo `.p8` **ahora**: Apple solo lo deja bajar una vez
3. Anotá el **Issuer ID** (arriba de la página) y el **Key ID**

## 3. En Codemagic

1. Entrá a https://codemagic.io con tu cuenta de GitHub
   (`consultoradiagonales`)
2. **Add application** → elegí el repositorio `Qu-pasa-en-tu-barrio`
   → tipo de proyecto **Flutter App**
3. **Teams → Personal account → Integrations → App Store Connect → Connect**
   - Nombre: `condi_asc` (tiene que ser exactamente este)
   - Issuer ID, Key ID y el archivo `.p8` del paso 2.3
4. Abrí la app → **Start new build** → workflow `ios-testflight`

El plan gratuito da 500 minutos mensuales de macOS, de sobra para esto.

Un build tarda unos 15 a 25 minutos. Si sale bien, aparece solo en TestFlight.

## 4. Lo que Apple te va a pedir al revisar

Estos son los puntos donde más rechazan apps como esta:

### Cuenta de prueba (obligatoria)
La app exige iniciar sesión, así que Apple necesita un usuario para entrar.
En **App Review → Información de inicio de sesión** cargá un correo y
contraseña de una cuenta real **ya creada, con municipio elegido**.
Sin esto rechazan directamente.

### Política de privacidad
`https://consultoradiagonales.com.ar/app/privacidad.html` (ya publicada).

### Eliminación de cuenta
La app tiene "Eliminar cuenta" dentro del Perfil, que es lo que exige Apple
(guideline 5.1.1(v)). La página web `eliminar-cuenta.html` está creada pero **sin publicar** (decisión
tomada: no se publica nada en el sitio hasta testear). Apple no la necesita;
la pide Play Store.

### Etiquetas de privacidad (App Privacy)
Declarar que se recopila, vinculado al usuario, sin rastreo:

| Dato | Para qué |
|---|---|
| Correo electrónico | Funcionalidad de la app |
| Nombre | Funcionalidad de la app |
| Ubicación precisa | Funcionalidad de la app |
| Fotos | Funcionalidad de la app |
| ID de usuario | Funcionalidad de la app |
| ID de dispositivo (token de notificaciones) | Funcionalidad de la app |

La lista completa y los textos para pegar están en la sección 8. El archivo
`ios/Runner/PrivacyInfo.xcprivacy` declara lo mismo dentro de la app: tiene que
coincidir con lo que se carga en App Store Connect.

"¿Se usa para rastrearte?" → **No** en todos. ConDi no usa el identificador de
publicidad, así que no hace falta el aviso de transparencia de seguimiento.

### Contenido generado por usuarios (guideline 1.2)
Los reportes con fotos son contenido de usuarios. Apple pide que haya forma
de denunciar contenido, de bloquear usuarios abusivos, y un contacto visible.
La app ya cuenta contenido denunciado (`flaggedCount`), pero conviene
verificar que el botón "Denunciar" sea visible en cada reporte.

## 5. Iniciar sesión con Google (guideline 4.8) — RESUELTO

**Decisión tomada:** el botón de Google está oculto en iPhone (salida B). Quedan
las notas de abajo por si más adelante se quiere reponer.

Si una app ofrece "Continuar con Google" **y además** su propio registro con
correo, Apple exige ofrecer también **Iniciar sesión con Apple**, o un servicio
equivalente que no recolecte datos extra. ConDi tiene las dos cosas, así que
es un rechazo muy probable.

Hay dos salidas:

- **A. Agregar "Iniciar sesión con Apple"** a la pantalla de login. Mantiene
  Google. Requiere activar la capability en el App ID (paso 2.1), activar el
  proveedor en Firebase Authentication, y un paquete nuevo en la app.
- **B. Ocultar el botón de Google solo en iPhone.** Rápido y sin riesgo; los
  usuarios de iPhone entran con correo y contraseña.

## 6. Orden recomendado

1. Confirmar el pago (paso 0)
2. Pasos 2.1, 2.2 y 2.3 en el sitio de Apple
3. Decidir la salida del punto 5
4. Subir los cambios al repositorio de GitHub
5. Paso 3 en Codemagic
6. Primer build → TestFlight → probar en un iPhone real
7. Completar la ficha y enviar a revisión desde App Store Connect


## 7. Notificaciones push (APNs)

La app ya tiene en el código: el permiso `aps-environment` en
`ios/Runner/Runner.entitlements` (desarrollo en Debug, producción en
Release/Profile), el modo en segundo plano `remote-notification` en
`Info.plist` y Firebase Messaging. Falta lo que solo se puede hacer en los
sitios de Apple y Firebase:

1. **Activar Push en el App ID.** developer.apple.com > Certificates,
   Identifiers & Profiles > Identifiers > `ar.com.consultoradiagonales.condi`
   > marcar **Push Notifications** > Save. (Si Codemagic ya había creado el
   perfil, se regenera solo en el próximo build.)
2. **Crear la clave APNs.** Keys > `+` > nombre `ConDi APNs` > marcar
   **Apple Push Notifications service (APNs)** > Continue > Register.
   Descargar el `.p8` (Apple lo entrega **una sola vez**) y anotar el
   **Key ID**. El **Team ID** (`MY483Q9FNY`) está arriba a la derecha en la cuenta.
3. **Subir la clave a Firebase.** console.firebase.google.com > proyecto de
   ConDi > engranaje > Configuración del proyecto > **Cloud Messaging** >
   sección *Configuración de la app de Apple* > app iOS
   `ar.com.consultoradiagonales.condi` > **Clave de autenticación de APNs** >
   Subir: elegir el `.p8`, cargar Key ID y Team ID. Una sola clave sirve para
   desarrollo y producción. **No va en Codemagic ni en el repositorio**:
   guardar el `.p8` en un lugar privado (gestor de contraseñas).
4. **Compilar y subir a TestFlight** (paso 3 de esta guía). Los builds de
   TestFlight y App Store usan el entorno `production` de APNs, que es el que
   está configurado en Release.
5. **Probar en un iPhone real** (el simulador no recibe push remotas): instalar
   desde TestFlight, iniciar sesión, aceptar el permiso de notificaciones y
   mandar un mensaje de prueba desde Firebase Console > Messaging > *Nuevo
   mensaje de prueba* con el token FCM del dispositivo.
6. Si no llega: revisar que el `.p8` esté cargado en Firebase, que Push esté
   activo en el App ID, que el perfil sea nuevo (build posterior al paso 1) y
   que el iPhone no esté en modo Concentración.

## 8. Textos para App Store Connect

### Privacidad de la app (App Privacy)
Todos los datos: **vinculados al usuario**, **no se usan para rastrearlo**.
Finalidad: **Funcionalidad de la app**.

| Categoría | Dato | Para qué se usa |
|---|---|---|
| Ubicación | Ubicación precisa y aproximada | Marcar dónde está el problema reportado y mostrar lo que pasa cerca del usuario |
| Información de contacto | Nombre y correo electrónico | Crear y identificar la cuenta, y avisar sobre el estado de sus reportes |
| Contenido del usuario | Fotos y contenido de los reportes | Documentar los reportes que el vecino envía |
| Identificadores | ID de usuario e ID de dispositivo (token de notificaciones) | Mantener la sesión y enviar avisos al dispositivo |

Además, para operar el servicio se procesan el **modelo del dispositivo** y la
**dirección IP** (seguridad y prevención de abusos). Si Apple los pide en el
formulario, declararlos como *Datos de diagnóstico / Identificadores* con la
misma finalidad.

"¿Alguno de estos datos se usa para rastrear?" > **No**.
No hay identificador de publicidad, así que no se muestra el aviso de
transparencia de seguimiento (ATT).

### Texto breve para la ficha / notas de revisión
> ConDi permite a los vecinos reportar problemas de su barrio y seguir su
> resolución. Recopilamos ubicación, nombre, correo, fotos del reporte, modelo
> del dispositivo y dirección IP únicamente para que la app funcione. La
> persona da su consentimiento al registrarse y al aceptar los permisos, y
> puede retirarlo en cualquier momento desde **Mi cuenta** (incluida la
> opción de eliminar la cuenta y sus datos). No vendemos datos ni se usan
> para publicidad ni seguimiento.

### Notas para el equipo de revisión (App Review)
> Las notificaciones push se usan solo para avisar al usuario el estado de sus
> reportes. El permiso se solicita dentro de la app y puede rechazarse sin
> perder funciones. Usuario de prueba: cargar en el campo de credenciales.

### Cumplimiento de exportación
`ITSAppUsesNonExemptEncryption = false` ya está en `Info.plist` (la app solo
usa el cifrado estándar HTTPS del sistema), por lo que App Store Connect no
vuelve a preguntar por el cumplimiento de exportación en cada build.

### Antes de enviar a revisión (checklist rápida)
- [ ] Push activo en el App ID y `.p8` cargado en Firebase (sección 7)
- [ ] `APP_STORE_APPLE_ID` completado en `codemagic.yaml`
- [ ] Etiquetas de privacidad iguales a `PrivacyInfo.xcprivacy`
- [ ] Cuenta de prueba con municipio elegido
- [ ] URL de política de privacidad publicada y accesible
- [ ] Clave de Google Maps iOS restringida al bundle id en Google Cloud Console
