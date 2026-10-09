# Módulo 1 — Especificación funcional
## App "¿Qué pasa en tu barrio?"

**Versión:** 1.0  
**Fecha:** Octubre 2026  
**Alcance:** MVP ciudadano + panel del legislador (fase 2 incluida en spec para guiar el modelo de datos)

---

## 1. Actores del sistema

| Actor | Descripción |
|-------|-------------|
| **Ciudadano** | Vecino registrado que puede reportar problemas, ver reportes de otros y comentar. |
| **Legislador / Admin** | Usuario con rol elevado que accede al panel de gestión. Puede ver todos los reportes, cambiarles el estado y responder. |
| **Moderador** | Puede ocultar o eliminar contenido que viole las normas. Puede ser el mismo Admin en el MVP. |

---

## 2. Flujos de usuario

### 2.1 Registro y login

| Paso | Acción | Detalle |
|------|--------|---------|
| 1 | El usuario abre la app | Pantalla de bienvenida con logo y dos botones: "Registrarse" y "Iniciar sesión" |
| 2 | Registro con correo | Nombre, correo, contraseña (mínimo 8 caracteres). Verificación de correo obligatoria antes del primer uso. |
| 3 | Login con Google | OAuth 2.0 vía Firebase Auth. No requiere verificación adicional. |
| 4 | Recuperación de contraseña | Correo con enlace de restablecimiento. |
| 5 | Perfil | Nombre de usuario, foto opcional, municipio (selección de lista). |
| 6 | Eliminación de cuenta | El usuario puede borrar su cuenta y todos sus datos desde Configuración → Cuenta → Eliminar cuenta. Requiere confirmación. |

> **Play Store:** la eliminación de cuenta es obligatoria desde agosto 2023. Debe eliminar datos del usuario en Firebase Auth, Firestore y Storage.

---

### 2.2 Crear un reporte (ciudadano)

| Paso | Pantalla | Campos / Acciones |
|------|----------|-------------------|
| 1 | Botón "Reportar" (FAB en mapa) | Abre el formulario de nuevo reporte. |
| 2 | Formulario | **Título** (obligatorio, máx. 80 chars) |
| | | **Descripción** (obligatorio, máx. 500 chars) |
| | | **Categoría** (obligatorio, lista desplegable: Infraestructura, Alumbrado, Basura, Seguridad, Salud, Transporte, Medio Ambiente, Otro) |
| | | **Fotos** (opcional, hasta 5 imágenes, cámara o galería) |
| | | **Ubicación** (obligatorio): GPS automático con opción de ajuste manual en el mapa mini. |
| 3 | Vista previa | Resumen antes de enviar. Botón "Publicar" y "Editar". |
| 4 | Confirmación | Toast "Reporte enviado. Podés seguir su estado en Mis reportes." |

---

### 2.3 Ver reportes (mapa principal)

- Mapa centrado en la ubicación del usuario.
- Marcadores agrupados (clusters) cuando hay muchos reportes juntos.
- Colores por estado: **rojo** = pendiente, **amarillo** = en revisión, **verde** = resuelto.
- Filtros: categoría, estado, fecha (últimos 7 días / 30 días / todos).
- Tocar un marcador muestra la tarjeta de resumen del reporte.

---

### 2.4 Ver detalle de un reporte

- Título, descripción, categoría, fecha, estado.
- Fotos (galería deslizable).
- Ubicación exacta en mapa mini.
- Sección de comentarios:
  - Ciudadanos pueden agregar comentarios (máx. 300 chars).
  - Legisladores pueden agregar respuestas oficiales (se muestran destacadas).
  - Botón "Reportar" en cada comentario (moderación).
- Botón "Reportar como inapropiado" en el reporte completo.

---

### 2.5 Mis reportes (ciudadano)

- Lista de los reportes propios con estado y fecha.
- Posibilidad de editar reportes en estado "pendiente".
- Posibilidad de eliminar un reporte propio (pide confirmación).

---

### 2.6 Panel del legislador (fase 2 — se diseña en el MVP para no tener que migrar datos)

| Función | Detalle |
|---------|---------|
| Listado de reportes | Tabla con filtros: zona (radio geográfico), categoría, estado, fecha. |
| Cambiar estado | Pendiente → En revisión → Resuelto. Cada cambio dispara notificación push al ciudadano. |
| Respuesta oficial | El legislador puede agregar una respuesta que aparece destacada en el detalle. |
| Estadísticas | Conteo por categoría y estado. Mapa de calor de concentración de problemas. |
| Exportar | CSV con los reportes filtrados (nombre oculto del ciudadano, solo ID). |

---

### 2.7 Notificaciones push (fase 2)

| Evento | Destinatario |
|--------|-------------|
| Estado del reporte cambia | Ciudadano que lo creó |
| Nueva respuesta oficial en su reporte | Ciudadano que lo creó |
| Nuevo reporte en la zona del legislador | Legislador (configurable) |

---

## 3. Estados de un reporte

```
Pendiente → En revisión → Resuelto
Pendiente → Rechazado (solo moderador/admin, con motivo obligatorio)
```

Un reporte rechazado no se elimina; queda oculto para los ciudadanos pero visible para el admin.

---

## 4. Reglas de negocio

1. Un usuario no puede crear más de 10 reportes en 24 horas (anti-spam).
2. Las fotos se redimensionan a máximo 1200px antes de subirse (para limitar el costo de Storage).
3. Los comentarios de ciudadanos en un reporte resuelto quedan deshabilitados.
4. El nombre del ciudadano se muestra en el mapa solo como "Usuario #XXXX" (privacidad). El nombre real solo lo ve el admin.
5. Los reportes tienen un campo `hidden: true` que los oculta del mapa sin borrarlos (moderación no destructiva).
6. El legislador ve todos los reportes de su municipio, no de otros.

---

## 5. Pantallas del MVP

| Pantalla | Descripción |
|----------|-------------|
| `Splash` | Logo + animación de carga |
| `Bienvenida` | Registro / Login |
| `Registro` | Formulario de alta |
| `Login` | Correo + contraseña, botón Google |
| `Recuperar contraseña` | Envío de correo |
| `Mapa principal` | Mapa interactivo con FAB "Reportar" |
| `Nuevo reporte` | Formulario de creación |
| `Detalle de reporte` | Vista completa + comentarios |
| `Mis reportes` | Lista propia |
| `Perfil` | Datos del usuario, eliminar cuenta |
| `Configuración` | Notificaciones, idioma |
| `Panel legislador` | Lista + filtros (fase 2) |

---

## 6. Requisitos no funcionales

| Atributo | Requisito |
|----------|-----------|
| Idioma | Español (Argentina como locale por defecto) |
| Plataformas | Android 7.0+ (API 24), iOS 14+ |
| Rendimiento | Carga del mapa < 2 s en 4G |
| Privacidad | Sin datos personales expuestos en el mapa ni en la API pública |
| Moderación | Botón de reporte en cada ítem de contenido generado por usuarios (requisito Play Store) |
| Política de privacidad | URL pública enlazada en la ficha de Play Store y en la pantalla de registro |
| Data Safety | Declarar: correo, nombre, fotos, ubicación precisa (se usa en primer plano) |
| Permisos | `ACCESS_FINE_LOCATION` y `CAMERA` solo se piden cuando el usuario los necesita, con texto explicativo previo (rationale dialog) |
| SDK objetivo | targetSdkVersion ≥ 35 (requerido por Google Play desde agosto 2025) |

---

## 7. Pendiente de decisión antes del módulo 3 (código)

- [ ] Nombre final de la app
- [ ] Logo e identidad visual
- [ ] ¿El panel del legislador es web (Flutter Web o Next.js) o mobile con rol?
- [ ] ¿ASTRA se integra como IA de análisis de reportes o como chatbot en el panel?
- [ ] Municipio piloto: ¿único municipio o multi-municipio desde el MVP?
