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
