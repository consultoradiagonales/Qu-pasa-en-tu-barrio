# ConDi — Registro de errores detectados

Sesión de pruebas del 2026-10-10. Build web servido desde `E:\condi` en `localhost:8090`.

Estado: `ABIERTO` = sin arreglar · `ARREGLADO` = corregido y verificado · `BLOQUEADO` = depende de acceso a Firebase

---

## Resumen

| # | Error | Gravedad | Estado |
|---|---|---|---|
| 01 | Reglas de Firestore nunca desplegadas: todo da permission-denied | Crítica | BLOQUEADO |
| 02 | Registro: excepción de Firestore sin capturar, pantalla congelada | Crítica | ARREGLADO |
| 03 | Login: mensaje de error genérico ocultaba la causa real | Alta | ARREGLADO |
| 04 | Recuperar contraseña roto en web: API key revocada | Alta | ARREGLADO |
| 05 | Faltaba permiso INTERNET: la app crasheaba al abrir | Crítica | ARREGLADO |
| 06 | Ícono por defecto de Flutter: Play Store lo rechaza | Media | ARREGLADO |
| 07 | Nombre viejo visible en splash y bienvenida | Media | ARREGLADO |
| 08 | Login con Google: no hay SHA-1 cargada en Firebase | Alta | BLOQUEADO |
| 09 | Panel de coordinador accesible por URL sin tener el rol | Alta | ARREGLADO |
| 10 | Error técnico de Firestore mostrado al usuario final | Media | ARREGLADO |
| 11 | Mensaje de contraseña inconsistente: pide 8, el error dice 6 | Baja | ABIERTO |
| 12 | Errores de validación persisten al volver a la pantalla | Baja | ABIERTO |
| 13 | Mapa roto en web: faltaba el SDK de Google Maps | Alta | ARREGLADO |
| 14 | `web/index.html` con los textos por defecto de Flutter | Baja | ARREGLADO |
| 15 | Sin cuenta de facturación: el mapa no funciona en ninguna plataforma | Crítica | BLOQUEADO |
| 16 | 13 pantallas mostraban el error técnico crudo al usuario | Media | ARREGLADO |
| 17 | No existían reglas de Storage: las fotos iban a fallar igual | Alta | ARREGLADO |
| 18 | La Cloud Function `assignReportTeam` nunca se escribió | Crítica | ARREGLADO |
| 19 | Mi script de reemplazo corrompió los acentos de 8 archivos | Alta | ARREGLADO |
| 20 | Todo usuario nuevo caía en el municipio `default`: sus reportes no los veía nadie | Crítica | ARREGLADO |
| 21 | El perfil creado por Google Sign-In no pasaba las reglas | Alta | ARREGLADO |
| 22 | Se podía pisar una foto ya subida y falsear la evidencia | Alta | ARREGLADO |

---

## 01 · Reglas de Firestore nunca desplegadas

**Gravedad:** Crítica — la app no funciona para ningún usuario.
**Estado:** BLOQUEADO (requiere acceso al proyecto Firebase)

El archivo `firestore.rules` existe en el repositorio pero nunca se desplegó. El
proyecto corre reglas de denegación total.

Comprobación hecha con una cuenta real (`qa.condi.test.2026@example.com`,
uid `omqIWAKXTGeB1kpS6IFVqnaBqS03`) y su idToken, contra la REST API de Firestore:

| Operación | Esperado con las reglas del repo | Obtenido |
|---|---|---|
| `GET users/{uid}` propio | `NOT_FOUND` | `PERMISSION_DENIED` |
| `PATCH users/{uid}` con role=citizen, disabled=false | `OK` | `PERMISSION_DENIED` |
| `GET reports` | `OK` | `PERMISSION_DENIED` |

Las reglas del repo permiten explícitamente las tres. Que las tres fallen prueba
que lo desplegado no es ese archivo.

**Arreglo:** `firebase deploy --only firestore:rules`

**Cómo verificar después:** repetir las tres llamadas. La primera debe dar
`NOT_FOUND` y la segunda `OK`.

---

## 02 · Registro: excepción sin capturar deja la pantalla congelada

**Gravedad:** Crítica
**Estado:** ARREGLADO
**Archivo:** `lib/features/auth/screens/register_screen.dart`

`_register()` solo capturaba `on FirebaseAuthException`. Pero `createUser()`
escribe en Firestore y lanza `FirebaseException`, que no es subclase de aquella.
La excepción escapaba, nunca se ejecutaba `context.go('/map')` y el usuario
quedaba parado en el formulario sin ningún mensaje.

Peor: la cuenta **sí** quedaba creada en Firebase Auth. Al reintentar, el usuario
recibía "ya existe una cuenta con ese correo" sobre una cuenta que, para él,
nunca se había creado. Esto es exactamente lo que reportó el usuario.

**Arreglo:** se agregaron `on FirebaseException catch` y un `catch` general, y un
helper `_showError()`. Ahora cualquier fallo se ve en pantalla.

---

## 03 · Login: mensaje genérico ocultaba la causa

**Gravedad:** Alta
**Estado:** ARREGLADO
**Archivos:** `lib/data/services/auth_service.dart`, `lib/features/auth/screens/login_screen.dart`

El proyecto tiene activada la protección contra enumeración de correos, así que
el backend responde siempre `INVALID_LOGIN_CREDENTIALS`, sin distinguir entre
correo inexistente y contraseña incorrecta. `errorMessage()` usaba un `switch`
sobre `e.code` que no contemplaba ese caso, y todo caía en el default:
*"Ocurrió un error. Intentá de nuevo."*

Dos intentos de arreglo no alcanzaron: ni agregando los códigos exactos al
`switch`, ni comparando por substring sobre `code` + `message`. En web el SDK
envuelve el error con un código que no refleja la causa.

**Arreglo definitivo:** se agregó `AuthService.loginErrorMessage()`, específica
para el flujo de correo y contraseña. Descarta primero lo que sí es
distinguible (red, demasiados intentos, cuenta deshabilitada, correo inválido,
método deshabilitado) y para todo lo demás dice *"Correo o contraseña
incorrectos. Si no te acordás, usá ¿Olvidaste tu contraseña?"*.

**Lección:** no decidir el mensaje por `FirebaseAuthException.code` en el login.
Decidirlo por el flujo.

---

## 04 · Recuperar contraseña roto en web

**Gravedad:** Alta (solo afectaba al build web)
**Estado:** ARREGLADO
**Archivo:** `lib/firebase_options.dart`

La `apiKey` de la plataforma web estaba revocada y devolvía
`api-key-not-valid.-please-pass-a-valid-api-key`.

| Plataforma | Clave | Estado |
|---|---|---|
| web | `AIzaSyD6ZSFUyC…` | Revocada |
| android | `AIzaSyDeBjOxDm…` | Válida |
| ios | `AIzaSyAkcmwvTv…` | Válida |

**Arreglo:** se usó la clave válida del proyecto para web. Android e iOS no se
tocaron. En Android este flujo siempre funcionó.

---

## 05 · Faltaba el permiso INTERNET

**Gravedad:** Crítica
**Estado:** ARREGLADO
**Archivo:** `android/app/src/main/AndroidManifest.xml`

El manifest no declaraba `android.permission.INTERNET`. `Firebase.initializeApp()`
lanzaba una `SecurityException` y la app se cerraba al abrir
("se detiene inesperadamente"). Se agregó junto con `ACCESS_NETWORK_STATE`,
`READ_MEDIA_IMAGES` y `READ_EXTERNAL_STORAGE` (maxSdk 32).

---

## 06 · Ícono por defecto de Flutter

**Gravedad:** Media — Play Store rechaza la ficha
**Estado:** ARREGLADO

La app usaba el logo de Flutter. Se generó el ícono ConDi (fondo `#0A1220`,
"Con" azul + "Di" verde) en las cinco densidades, más el ícono adaptativo para
Android 8+ y la versión 512×512 para la ficha.

---

## 07 · Nombre viejo visible en la app

**Gravedad:** Media
**Estado:** ARREGLADO

Splash y bienvenida seguían diciendo "¿Qué pasa en tu barrio?". Se creó el widget
`CondiLogo` y se aplicó en ambas, junto con el título de `MaterialApp`.

---

## 08 · Login con Google no funciona

**Gravedad:** Alta
**Estado:** BLOQUEADO (requiere acceso al proyecto Firebase)

Dos causas:

1. `GoogleSignIn.instance.initialize()` se llamaba sin `serverClientId`. En
   Android eso hace que `authenticate()` devuelva un `idToken` nulo y
   `signInWithCredential` falle. **Ya corregido.**
2. `google-services.json` no tiene ningún `oauth_client` de tipo 1 (Android), lo
   que confirma que no hay ninguna huella SHA-1 cargada en Firebase. Sin eso
   Google Play Services rechaza el intento con `DEVELOPER_ERROR` (código 10).
   **Esto no se puede arreglar sin entrar al proyecto.**

Huellas a cargar (están en `CONTINUAR_DESDE_ACA.json`): la de release, la de
debug y, después de publicar, la de Play App Signing.

---

## 09 · Panel de coordinador accesible por URL sin tener el rol

**Gravedad:** Alta
**Estado:** ARREGLADO
**Archivo:** `lib/core/router/app_router.dart`

El `redirect` del router solo distinguía entre usuario logueado y no logueado.
No miraba el rol. Cualquier cuenta autenticada podía escribir
`#/coordinator` o `#/field` en la barra de direcciones y entrar al panel de
gestión.

Verificado en la práctica: con una cuenta recién creada, sin perfil en Firestore
y sin rol asignado, el panel de coordinador se abrió con todos sus filtros.

Los datos no se filtraban, porque las reglas de Firestore los protegen por
separado con `staff()`. Pero la interfaz no debería ser alcanzable, y menos
cuando el panel se publique como tablero web.

**Arreglo:** se agregó un guard por rol en el `redirect`. `/coordinator` queda
para `coordinator`, `admin` y `moderator`; `/field` solo para `field_worker`.
Cualquier otro rol es devuelto a su home.

Mientras el rol todavía no se resolvió (`currentUserRoleProvider` devuelve null
porque la lectura de Firestore está en vuelo) no se redirige, para no expulsar a
un coordinador legítimo durante la carga.

---

## 10 · Error técnico mostrado al usuario final

**Gravedad:** Media
**Estado:** ARREGLADO
**Archivo:** `lib/features/coordinator/screens/coordinator_home_screen.dart`

El panel mostraba, en el medio de la pantalla:

> No se pudo cargar el perfil: [cloud_firestore/permission-denied] Missing or
> insufficient permissions.

Expone el motor de base de datos y el código interno del error. Lo mismo en el
estado de error del listado, con `Text('Error: $e')`.

**Arreglo:** se creó el widget `_PanelMessage` (ícono + texto) y se reemplazaron
ambos por mensajes en lenguaje llano con una vía de contacto.

---

## 11 · Mensaje de contraseña inconsistente

**Gravedad:** Baja
**Estado:** ABIERTO

El formulario de registro valida **mínimo 8 caracteres**, pero
`AuthService.errorMessage()` responde al código `weak-password` con *"La
contraseña debe tener al menos 6 caracteres"*. Seis es el mínimo de Firebase,
ocho es el de la app.

En la práctica el usuario no llega a ver la contradicción, porque la validación
local corta antes. Igual conviene unificar en 8.

---

## 12 · Errores de validación persisten al volver a la pantalla

**Gravedad:** Baja (cosmético)
**Estado:** ABIERTO

Si se envía el formulario de registro vacío, se navega a login y se vuelve a
registro, los campos aparecen vacíos pero con los mensajes rojos todavía
puestos. `go_router` reutiliza la instancia de la pantalla y el estado del
`Form` no se limpia.

**Arreglo propuesto:** resetear el `FormState` en `initState`, o darle una
`ValueKey` distinta a la ruta para forzar una instancia nueva.

---

## 13 · Mapa roto en web: faltaba el SDK de Google Maps

**Gravedad:** Alta (solo afecta al build web)
**Estado:** ARREGLADO
**Archivo:** `web/index.html`

Al entrar a `/map` en el navegador la pantalla quedaba en rojo con:

> TypeError: Cannot read properties of undefined (reading 'MapTypeId')

`google_maps_flutter_web` no inyecta el SDK de Google Maps por su cuenta: hay que
cargar el script a mano en `index.html`. No estaba.

En Android no se nota, porque ahí se usa el SDK nativo que toma la clave del
`meta-data` del AndroidManifest.

**Arreglo:** se agregó el `<script>` de `maps.googleapis.com` con una clave
**nueva y distinta** a la de Android/iOS. Una clave que viaja en el HTML es
pública, así que se restringió por dominio de origen en vez de por servicio:

- Clave web: `AIzaSyCRKeRO6eCDNHLmfq-kZXeEXNI79Mc4tU4`
- Proyecto: `condi-maps-2026`
- uid: `d068a3e6-e6b1-4e40-b750-e43287d49f86`
- API habilitada: `maps-backend.googleapis.com` (Maps JavaScript API)
- Orígenes permitidos: `https://consultoradiagonales.com.ar/*`,
  `https://*.consultoradiagonales.com.ar/*`, `http://localhost:8090/*`

Si el panel se publica en otro dominio hay que agregarlo a esa lista, si no el
mapa va a fallar por referrer no autorizado.

---

## 14 · `web/index.html` con los textos por defecto de Flutter

**Gravedad:** Baja
**Estado:** ARREGLADO

La pestaña del navegador decía `que_pasa_en_tu_barrio` y la descripción era
*"A new Flutter project."*. Se cambiaron el `<title>`, la `description` y el
`apple-mobile-web-app-title` a ConDi.

---

## 15 · Sin cuenta de facturación: el mapa no funciona

**Gravedad:** Crítica — el mapa es la función central de la app
**Estado:** BLOQUEADO (requiere una tarjeta, solo lo puede hacer el usuario)

Al cargar el mapa en web, la consola devuelve:

> Google Maps JavaScript API error: InvalidKeyMapError

No es un problema de la clave. Consultando la Cloud Billing API del proyecto
`condi-maps-2026`:

```
billingEnabled : False
billingAccount : (vacío)
cuentas de facturación disponibles: ninguna
```

Google Maps Platform exige una cuenta de facturación activa desde 2018. Sin
ella, **todas** las plataformas fallan: web devuelve `InvalidKeyMapError` y
Android muestra el mapa en gris. No alcanza con tener la clave creada y las
APIs habilitadas.

**Esto significa que publicar hoy en Play Store sería publicar una app cuyo
mapa no carga.**

**Arreglo:** crear una cuenta de facturación en
https://console.cloud.google.com/billing con `info.consultoradiagonales@gmail.com`,
asociarla al proyecto `condi-maps-2026` y vincularla también al proyecto de
Firebase que use la app.

**Sobre el costo:** Google da USD 200 de crédito mensual para Maps Platform. Con
el volumen de una app municipal chica no se llega ni cerca de ese tope, así que
en la práctica no se paga. Pero la tarjeta es obligatoria para que el servicio
responda. Conviene además fijar un límite de cuota diaria para que un pico de
uso no genere un cobro inesperado.

---

## 16 · Trece pantallas mostraban el error técnico crudo

**Gravedad:** Media
**Estado:** ARREGLADO

El error #10 no era un caso aislado. Buscando el patrón `Text('Error: $e')`
aparecieron 13 lugares que volcaban la excepción tal cual a la pantalla:
perfil, mis reportes, detalle de reporte, notificaciones, nuevo reporte,
panel de coordinador, vista de operario y la pantalla 404 del router.

Cualquiera de esos le habría mostrado a un vecino algo como
`[cloud_firestore/permission-denied] Missing or insufficient permissions`.

**Arreglo:** se creó `lib/core/utils/error_text.dart` con la función
`mensajeDeError(Object)`, que traduce la excepción a lenguaje llano
(sin permiso / sin conexión / no encontrado / servicio saturado / genérico).
Se reemplazaron los 13 usos.

---

## 17 · No existían reglas de Storage

**Gravedad:** Alta
**Estado:** ARREGLADO (falta desplegarlas)

El repositorio tenía `firestore.rules` pero **ningún** `storage.rules`, y
`firebase.json` no declaraba la sección `storage`. Las fotos se suben a
`reports/{reportId}/{fase}/...` desde `reports_repository.dart`.

Sin reglas, el bucket queda con la configuración por defecto y **toda subida de
fotos falla**, exactamente el mismo problema que tuvo Firestore. Se habría
descubierto recién al intentar cargar el primer reporte con foto.

**Arreglo:** se creó `storage.rules` y se agregó la sección al `firebase.json`:

- Lectura: cualquier usuario autenticado (los reportes son públicos en la app)
- Escritura: usuario autenticado, solo imágenes, máximo 8 MB
- Modificar o borrar: prohibido, las fotos son evidencia del estado del reclamo
- Todo lo demás: cerrado

Falta desplegarlas. El script `setup-firebase.ps1` ya las incluye.

---

## 18 · La Cloud Function `assignReportTeam` nunca se escribió

**Gravedad:** Crítica — era la mitad del panel de gestión
**Estado:** ARREGLADO

`reports_repository.assignTeam()` llama a una función `assignReportTeam`, y
`firestore.rules` dice en un comentario que la asignación "se ejecuta
exclusivamente en assignReportTeam (Admin SDK)".

Esa función **no existía**. La carpeta `functions/` contenía únicamente
`node_modules` y un `.gitignore`: ni `index.js`, ni `package.json`. El nombre
`assignReportTeam` aparecía en un solo lugar de todo el repositorio, que era la
llamada del cliente.

Resultado: el panel podía listar reportes pero no asignarlos a un equipo. La
recepción funcionaba, la gestión no.

**Arreglo:** se escribieron `functions/package.json` y `functions/index.js`. La
función valida, en este orden: sesión iniciada, perfil existente, rol de
gestión y no deshabilitado, que el reporte y el equipo existan, que el
coordinador sea del mismo municipio (el admin puede con todos), que el equipo
pertenezca al municipio y esté activo, y que el reporte no esté ya en curso o
cerrado. Recién ahí escribe `assignedTeamId`, pasa el estado a `assigned` y
crea la notificación para el vecino.

### Verificado contra el emulador

| Caso | Esperado | Obtenido |
|---|---|---|
| Coordinadora asigna un pendiente | se asigna | `{ok:true}`, el reporte quedó `assigned` con su equipo |
| Se le avisa al vecino | se crea la notificación | "Tu reporte fue asignado — Microbasural en la esquina pasó a Higiene Urbana" |
| Una vecina intenta asignar | rechazo | **403** permission-denied |
| Reasignar uno ya resuelto | rechazo | **400** failed-precondition |
| Equipo inexistente | rechazo | **404** not-found |

**Nota:** desplegar Cloud Functions exige el plan Blaze, o sea facturación
activa. Es el mismo trámite que pide Maps.

---

## 19 · El script de reemplazo corrompió los acentos

**Gravedad:** Alta
**Estado:** ARREGLADO

Al arreglar el error #16 usé un script de PowerShell con `Get-Content -Raw`.
En PowerShell 5.1 eso lee con el codepage ANSI, así que los bytes UTF-8 se
interpretaron como Latin-1 y al reescribir el archivo quedaron codificados dos
veces. Ocho archivos quedaron con "gestiÃ³n" en lugar de "gestión".

Se detectó al ver el panel en pantalla: decía "En gestiÃ³n" y "resoluciÃ³n
promedio".

**Arreglo:** se revirtió la doble codificación leyendo los bytes crudos,
decodificando como UTF-8 y reinterpretando esos caracteres como Latin-1.

**Para la próxima:** en PowerShell 5.1 siempre `Get-Content -Raw -Encoding utf8`,
o directamente `[IO.File]::ReadAllText($p, [Text.UTF8Encoding]::new($false))`.

---

## 20 · Todo usuario nuevo caía en el municipio `default`

**Gravedad:** Crítica — los reportes de usuarios reales no los habría visto nadie
**Estado:** ARREGLADO

`register_screen.dart` escribía `municipalityId: 'default'` con un
`// TODO: selección de municipio` al lado, y `auth_service.dart` hacía lo mismo
en el alta por Google. **No existía ninguna pantalla para elegir municipio.**

El problema es que las reglas atan el reporte al municipio del perfil:

```
allow create: if ... request.resource.data.municipalityId == profile().municipalityId
```

Y el panel solo consulta reportes de *su* municipio. Entonces: todo vecino real
quedaba en `default`, sus reportes se creaban en `default`, y ningún
coordinador (que pertenece a un municipio de verdad) los veía nunca. Los
reclamos caían en un pozo.

Verificado contra el emulador: una vecina de `la-plata` recibe **403** al
intentar crear un reporte en `default`, porque su perfil no coincide.

**Arreglo:**

- Nueva pantalla `select_municipality_screen.dart` en `/auth/municipio`, que
  lista los municipios activos desde Firestore.
- Nuevo `municipalities_repository.dart`.
- El alta por correo y la de Google ahora guardan el municipio **vacío**.
- Guard en el router: un `citizen` con municipio vacío va a `/auth/municipio`
  y no sale de ahí hasta elegir. Sirve igual para cuentas viejas.
- `new_report_screen` corta antes de subir las fotos si no hay municipio, en
  lugar de fallar al final.
- Hubo que excluir `/auth/municipio` del rebote de pantallas de auth: como
  cuelga de `/auth` pero es para alguien ya logueado, el redirect la devolvía
  al home y el guard la mandaba de vuelta, en bucle.

### Y había un segundo problema encima

La regla de `update` de `/users` no incluía `municipalityId` entre los campos
editables, así que guardar la elección habría sido rechazado igual.

Se agregó, pero **solo para vecinos**: el municipio de un coordinador define
qué reportes ve, así que dejarlo cambiárselo sería darle acceso a los datos de
otro municipio.

| Caso | Resultado |
|---|---|
| Vecino fija su municipio | PERMITIDO, queda guardado |
| Coordinadora intenta mudarse de municipio | **403**, sigue en el suyo |
| Vecino recién registrado crea un reporte | OK, aparece en el panel |

---

## 21 · El perfil creado por Google Sign-In no pasaba las reglas

**Gravedad:** Alta
**Estado:** ARREGLADO
**Archivo:** `lib/data/services/auth_service.dart`

El documento que se escribía al entrar por primera vez con Google no incluía
`disabled`, y la regla de create lo exige:

```
allow create: if own(userId) && request.resource.data.role == 'citizen' &&
  request.resource.data.disabled == false;
```

Sin ese campo la escritura se rechaza. Además guardaba la foto en `photoUrl`
mientras que `UserModel` lee `photoURL`, y faltaban `teamId`, `fcmToken`,
`lastReportAt` y `reportsCount`.

O sea que, aun con la SHA-1 cargada, el alta por Google habría fallado al
crear el perfil.

**Arreglo:** el documento ahora replica exactamente `UserModel.toFirestore()`.

---

## 22 · Se podía pisar una foto ya subida

**Gravedad:** Alta — permitía falsear la evidencia de un reclamo
**Estado:** ARREGLADO
**Archivo:** `storage.rules`

Las reglas de Storage decían `allow update, delete: if false;` con la intención
de que las fotos fueran inmutables. Al probarlas, borrar sí quedaba bloqueado,
pero **volver a subir sobre el mismo path funcionaba**.

El motivo: en las reglas de Cloud Storage, subir un objeto a una ruta que ya
existe se evalúa como `create`, no como `update`. `update` es solo para
metadatos. La condición de inmutabilidad nunca se ejecutaba.

Concretamente: un operario podía reemplazar la foto del "antes" después de
terminar el trabajo, y nadie se enteraba.

**Arreglo:** `allow create: if signedIn() && fotoValida() && resource == null;`
En Storage, `resource` es el objeto existente, o null si no hay nada en esa
ruta. Con eso la subida solo pasa si el archivo no existía.

### Reglas de Storage verificadas

| Caso | Resultado |
|---|---|
| Subir una foto al reporte | OK |
| Leerla de vuelta | OK |
| Pisar una foto ya subida | Rechazado |
| Borrar una foto | Rechazado |
| Subir algo que no es imagen | Rechazado |
| Escribir fuera de `reports/` | Rechazado |

---

## Circuito del operario verificado

| Caso | Resultado |
|---|---|
| Toma la tarea: `assigned` → `in_progress` con foto del antes | OK |
| Intentarlo sin foto del antes | Rechazado |
| Cierra: `in_progress` → `resolved` con foto del después | OK |
| Alguien de otro equipo intenta tomar la tarea | Rechazado |

## Apoyos a reportes verificados

Se probó con el SDK cliente, recorriendo el mismo batch que usa
`ReportsRepository.addSupportVote`: el voto y el contador van en un solo commit,
porque la regla exige que el voto no exista antes y sí exista después.

| Caso | Resultado |
|---|---|
| Un vecino apoya | 9 → 10 |
| El mismo vecino apoya otra vez | La app corta antes de escribir |
| Otro vecino intenta sumar 10 de una | Rechazado, queda en 10 |
| Ese vecino apoya bien | 10 → 11 |

---

## Verificación del panel contra el emulador

Antes de gastar un peso se levantó el **emulador de Firebase** (Auth, Firestore,
Storage y Functions) con las reglas reales del repositorio, y se sembraron datos
de prueba: el municipio de La Plata, tres cuadrillas, cinco usuarios con
distintos roles y siete reportes repartidos en todos los estados.

Es el mismo código que va a Play Store. Lo único distinto es dónde vive la base.

Qué se comprobó funcionando:

- Inicio de sesión con correo y contraseña
- Redirección automática según el rol: la coordinadora cae en `/coordinator`
- El panel **recibe los reportes**, con categoría, estado y antigüedad
- Tarjeta de estadísticas en vivo: 3 pendientes, 2 en gestión, 2 resueltos,
  7 reportes, 101 apoyos, resolución promedio 52 h
- Filtros por estado
- Selector de equipo que reconoce la categoría del reporte y marca cuál es
  "apto para esta categoría"
- Asignación completa, con persistencia y notificación al vecino
- Las reglas de seguridad rechazan lo que tienen que rechazar

Para reproducirlo:

```
firebase emulators:start --only auth,firestore,storage,functions --project que-pasa-en-tu-barrio
node scripts/sembrar-emulador.mjs
flutter run -d web-server --web-port 8091 --dart-define=USE_EMULATOR=true
```

Credenciales de prueba (solo existen en el emulador):

| Rol | Correo | Contraseña |
|---|---|---|
| Coordinadora | coordinador@condi.test | Coordinador2026 |
| Administrador | admin@condi.test | Administrador2026 |
| Operario | operario@condi.test | Operario2026 |
| Vecina | vecina@condi.test | Vecina20260101 |

---

## Pendiente de probar

Ya no se puede avanzar más sin los trámites pendientes:

- **Tiles del mapa** — necesita facturación activa. La pantalla ya no crashea
  y el SDK carga; lo que falta es que Google sirva las imágenes.
- **Cámara y galería reales** — el emulador valida las reglas de Storage, pero
  sacar una foto desde el teléfono hay que probarlo en un Android físico.
- **Notificaciones push** — FCM no tiene emulador. Hace falta el proyecto real
  y un dispositivo.
- **Comportamiento en Android físico** — todo lo verificado corrió sobre el
  build web contra el emulador. El código es el mismo, pero conviene una pasada
  en un teléfono antes de publicar.
