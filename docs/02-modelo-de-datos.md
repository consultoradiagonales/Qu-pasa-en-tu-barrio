# Módulo 2 — Modelo de datos y seguridad
## Firestore + Firebase Storage

**Versión:** 1.0  
**Fecha:** Octubre 2026

---

## 1. Colecciones Firestore

### 1.1 `users/{userId}`

```json
{
  "uid": "string",                   // = Firebase Auth UID
  "displayName": "string",           // nombre público: "Usuario #XXXX"
  "realName": "string",              // solo visible para admin
  "email": "string",                 // solo visible para admin y el propio usuario
  "photoURL": "string | null",
  "role": "citizen | legislator | moderator | admin",
  "municipalityId": "string",        // FK a municipalities/{id}
  "createdAt": "timestamp",
  "disabled": false,
  "reportsCount": 0,                 // contador desnormalizado
  "lastReportAt": "timestamp | null" // para el rate-limiting
}
```

---

### 1.2 `municipalities/{municipalityId}`

```json
{
  "id": "string",
  "name": "string",                  // ej: "General Pueyrredón"
  "province": "string",
  "country": "AR",
  "boundingBox": {                   // para filtrar reportes por municipio
    "north": 0.0,
    "south": 0.0,
    "east": 0.0,
    "west": 0.0
  }
}
```

---

### 1.3 `reports/{reportId}`

```json
{
  "id": "string",
  "userId": "string",                // FK users/{userId}
  "municipalityId": "string",        // FK municipalities/{id}
  "title": "string",                 // máx. 80 chars
  "description": "string",          // máx. 500 chars
  "category": "infrastructure | lighting | garbage | security | health | transport | environment | other",
  "photos": ["url1", "url2"],        // URLs en Firebase Storage
  "location": {
    "lat": 0.0,
    "lng": 0.0,
    "address": "string | null"       // geocodificación inversa opcional
  },
  "status": "pending | in_review | resolved | rejected",
  "hidden": false,                   // moderación no destructiva
  "rejectionReason": "string | null",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "resolvedAt": "timestamp | null",
  "commentsCount": 0,                // contador desnormalizado
  "officialResponseCount": 0
}
```

> **Índices compuestos necesarios:**
> - `municipalityId` + `status` + `createdAt` (desc) — para el panel del legislador
> - `municipalityId` + `category` + `createdAt` (desc) — filtros por categoría
> - `userId` + `createdAt` (desc) — "Mis reportes"
> - `location` (GeoPoint) — para consultas geográficas (usar GeoFlutterFire o GeoHash)

---

### 1.4 `reports/{reportId}/comments/{commentId}`

```json
{
  "id": "string",
  "reportId": "string",
  "userId": "string",
  "displayName": "string",           // snapshot del nombre al momento de comentar
  "text": "string",                  // máx. 300 chars
  "isOfficialResponse": false,       // true solo si role = legislator/admin
  "hidden": false,
  "createdAt": "timestamp",
  "flaggedCount": 0                  // contador de reportes de abuso
}
```

---

### 1.5 `contentFlags/{flagId}`

```json
{
  "id": "string",
  "reportedBy": "string",            // userId del denunciante
  "targetType": "report | comment",
  "targetId": "string",
  "reportId": "string",              // siempre el reporte raíz
  "reason": "spam | offensive | fake | other",
  "status": "pending | reviewed",
  "createdAt": "timestamp"
}
```

> Play Store requiere que la app tenga mecanismo de denuncia de contenido generado por usuarios.

---

### 1.6 `notifications/{notificationId}`

```json
{
  "id": "string",
  "userId": "string",                // destinatario
  "type": "status_change | official_response | new_report_in_zone",
  "reportId": "string",
  "message": "string",
  "read": false,
  "createdAt": "timestamp"
}
```

---

## 2. Estructura de Firebase Storage

```
/reports/{reportId}/{filename}.jpg   // fotos de reportes
/users/{userId}/avatar.jpg          // foto de perfil (opcional)
```

- Las fotos de reportes son **públicas de lectura** pero solo el propietario puede escribir.
- Los avatares son **públicos de lectura**, solo el propietario puede escribir.

---

## 3. Reglas de seguridad Firestore

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helpers
    function isAuth() { return request.auth != null; }
    function isOwner(userId) { return request.auth.uid == userId; }
    function hasRole(role) {
      return isAuth() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == role;
    }
    function isAdmin() { return hasRole('admin') || hasRole('moderator'); }
    function isLegislator() { return hasRole('legislator') || isAdmin(); }

    // Users
    match /users/{userId} {
      allow read: if isAdmin() || isOwner(userId);
      allow create: if isAuth() && isOwner(userId);
      allow update: if isOwner(userId) || isAdmin();
      allow delete: if isAdmin();
    }

    // Municipalities — read-only para todos los autenticados
    match /municipalities/{mId} {
      allow read: if isAuth();
      allow write: if isAdmin();
    }

    // Reports
    match /reports/{reportId} {
      // Ciudadanos ven reportes no ocultos de su municipio
      allow read: if isAuth() &&
        (resource.data.hidden == false || isAdmin() || isOwner(resource.data.userId));
      // Ciudadano puede crear
      allow create: if isAuth();
      // Ciudadano puede editar su propio reporte solo si está pendiente
      allow update: if (isOwner(resource.data.userId) && resource.data.status == 'pending')
        || isLegislator();
      // Solo admin puede eliminar (soft-delete via hidden=true preferido)
      allow delete: if isAdmin();
    }

    // Comments
    match /reports/{reportId}/comments/{commentId} {
      allow read: if isAuth() && resource.data.hidden == false;
      allow create: if isAuth() && resource.data.status != 'resolved';
      allow update: if isOwner(resource.data.userId) || isAdmin();
      allow delete: if isAdmin();
    }

    // Content flags — cualquier usuario autenticado puede denunciar
    match /contentFlags/{flagId} {
      allow read: if isAdmin();
      allow create: if isAuth();
      allow update: if isAdmin();
    }

    // Notifications — solo el destinatario
    match /notifications/{notId} {
      allow read, update: if isAuth() && isOwner(resource.data.userId);
      allow create: if isAdmin(); // solo el backend (Cloud Functions) crea notificaciones
    }
  }
}
```

---

## 4. Reglas de seguridad Firebase Storage

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    match /reports/{reportId}/{file} {
      allow read: if request.auth != null;
      // Solo el creador del reporte puede subir fotos
      allow write: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024  // máx 5 MB por foto
        && request.resource.contentType.matches('image/.*');
    }

    match /users/{userId}/{file} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId
        && request.resource.size < 2 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }
  }
}
```

---

## 5. Cloud Functions requeridas

| Función | Trigger | Acción |
|---------|---------|--------|
| `onReportStatusChange` | Firestore: `reports` update | Envía push notification al ciudadano via FCM |
| `onOfficialComment` | Firestore: `comments` create, `isOfficialResponse = true` | Envía push notification al ciudadano |
| `onUserDelete` | Firebase Auth: user deleted | Elimina todos los datos del usuario (GDPR + Play Store) |
| `resizeReportPhoto` | Storage: `reports/` object created | Redimensiona la foto a máx. 1200px |
| `rateLimitReports` | Firestore: `reports` create | Rechaza si el usuario creó ≥ 10 reportes en las últimas 24h |

---

## 6. Consideraciones de privacidad (Data Safety Play Store)

| Dato | Propósito | Se comparte con terceros |
|------|-----------|-------------------------|
| Correo electrónico | Autenticación y notificaciones | No |
| Nombre | Perfil público anonimizado | No (se muestra como "Usuario #XXXX") |
| Fotos | Reportar problemas | No (solo se muestran en la app) |
| Ubicación precisa | Geolocalizar el reporte | No |
| FCM token | Notificaciones push | Solo con Google (Firebase) |

---

## 7. Checklist antes de pasar al módulo 3

- [ ] Confirmar si el panel del legislador es web o mobile con rol en la misma app.
- [ ] Confirmar si habrá soporte multi-municipio en el MVP o solo uno.
- [ ] Crear proyecto en Firebase Console y activar: Auth, Firestore, Storage, Cloud Messaging, Cloud Functions.
- [ ] Obtener `google-services.json` (Android) y `GoogleService-Info.plist` (iOS).
- [ ] Activar Google Maps SDK y obtener la API Key.
