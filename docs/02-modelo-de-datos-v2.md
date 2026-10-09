# Módulo 2 v2 — Modelo de datos con flujo de campo
## Firestore + Firebase Storage

**Versión:** 2.0 (actualizado con flujo equipo de campo + foto antes/después)  
**Fecha:** Octubre 2026

---

## 1. Colecciones Firestore

### 1.1 `users/{userId}`

```json
{
  "uid": "string",
  "displayName": "string",           // "Usuario #XXXX" en el mapa
  "realName": "string",              // solo visible para admin/coordinador
  "email": "string",
  "photoURL": "string | null",
  "role": "citizen | field_worker | coordinator | moderator | admin",
  "teamId": "string | null",         // FK teams/{id}, solo field_worker
  "municipalityId": "string",
  "fcmToken": "string | null",       // para push notifications
  "createdAt": "timestamp",
  "lastReportAt": "timestamp | null",
  "reportsCount": 0,
  "disabled": false
}
```

---

### 1.2 `teams/{teamId}`

```json
{
  "id": "string",
  "name": "string",                  // ej: "Equipo Norte", "Cuadrilla 3"
  "municipalityId": "string",
  "members": ["userId1", "userId2"], // FK users
  "categories": ["infrastructure", "lighting"],  // especialidades
  "active": true,
  "createdAt": "timestamp"
}
```

---

### 1.3 `municipalities/{municipalityId}`

```json
{
  "id": "string",
  "name": "string",
  "province": "string",
  "country": "AR",
  "boundingBox": {
    "north": 0.0, "south": 0.0, "east": 0.0, "west": 0.0
  }
}
```

---

### 1.4 `reports/{reportId}` ← NÚCLEO DE LA APP

```json
{
  "id": "string",
  "userId": "string",                // ciudadano que lo creó
  "municipalityId": "string",

  // DATOS DEL PROBLEMA
  "title": "string",                 // máx. 80 chars
  "description": "string",          // máx. 500 chars
  "category": "infrastructure | lighting | garbage | security | health | transport | environment | other",

  // FOTOS — separadas por etapa
  "photosReport": ["url1", "url2"], // fotos del CIUDADANO al reportar (antes)
  "photosBefore": ["url1"],         // fotos del EQUIPO al llegar (confirma el antes in situ)
  "photosProgress": ["url1"],       // fotos opcionales durante el trabajo
  "photosAfter": ["url1"],          // fotos del EQUIPO al terminar (el después)

  // UBICACIÓN
  "location": {
    "lat": 0.0,
    "lng": 0.0,
    "geohash": "string",            // para consultas GeoHash eficientes
    "address": "string | null"      // geocodificación inversa
  },

  // ESTADO Y ASIGNACIÓN
  "status": "pending | assigned | in_progress | resolved | rejected | closed",
  "priority": 1,                    // 1-5, calculado por votos + tiempo
  "supportCount": 0,                // votos de otros vecinos (priorización)

  "assignedTeamId": "string | null",
  "assignedWorkerId": "string | null",
  "assignedAt": "timestamp | null",

  // CAMPO
  "workerArrivedAt": "timestamp | null",   // cuando el equipo llegó al sitio
  "workStartedAt": "timestamp | null",
  "workFinishedAt": "timestamp | null",
  "workerNotes": "string | null",          // notas del equipo de campo

  // RESOLUCIÓN
  "resolvedAt": "timestamp | null",
  "rejectionReason": "string | null",

  // MODERACIÓN
  "hidden": false,
  "flaggedCount": 0,

  // METADATOS
  "commentsCount": 0,
  "createdAt": "timestamp",
  "updatedAt": "timestamp",

  // CALIFICACIÓN (ciudadano califica después de resolución)
  "rating": null,                    // 1-5 estrellas, null si no calificó
  "ratingComment": "string | null"
}
```

**Transiciones de estado:**
```
pending → assigned (coordinador asigna)
assigned → in_progress (equipo llega al sitio, sube foto del antes)
in_progress → resolved (equipo sube foto del después, marca resuelto)
pending/assigned → rejected (coordinador rechaza, con motivo)
resolved → closed (ciudadano califica o pasan 30 días sin calificación)
```

**Índices compuestos Firestore:**
- `municipalityId` + `status` + `createdAt desc` → panel coordinador
- `municipalityId` + `category` + `status` → filtros del mapa
- `assignedTeamId` + `status` → mis tareas del equipo de campo
- `userId` + `createdAt desc` → mis reportes del ciudadano
- `location.geohash` → consultas geográficas

---

### 1.5 `reports/{reportId}/supportVotes/{userId}`

```json
{
  "userId": "string",
  "createdAt": "timestamp"
}
```

> Subcolección para evitar duplicados. Un usuario = un voto por reporte.

---

### 1.6 `reports/{reportId}/comments/{commentId}`

```json
{
  "id": "string",
  "userId": "string",
  "displayName": "string",
  "text": "string",                  // máx. 300 chars
  "isOfficialResponse": false,       // true si role = coordinator/admin
  "hidden": false,
  "flaggedCount": 0,
  "createdAt": "timestamp"
}
```

---

### 1.7 `contentFlags/{flagId}`

```json
{
  "id": "string",
  "reportedBy": "string",
  "targetType": "report | comment",
  "targetId": "string",
  "reportId": "string",
  "reason": "spam | offensive | fake | other",
  "status": "pending | reviewed",
  "createdAt": "timestamp"
}
```

---

### 1.8 `notifications/{notificationId}`

```json
{
  "id": "string",
  "userId": "string",                // destinatario
  "type": "new_report | report_assigned | worker_arrived | report_resolved | official_comment | new_support",
  "reportId": "string",
  "title": "string",
  "body": "string",
  "read": false,
  "createdAt": "timestamp"
}
```

---

## 2. Estructura Firebase Storage

```
/reports/{reportId}/citizen/{filename}.jpg     → fotos del ciudadano (al reportar)
/reports/{reportId}/before/{filename}.jpg      → fotos del equipo (al llegar)
/reports/{reportId}/progress/{filename}.jpg    → fotos del equipo durante el trabajo
/reports/{reportId}/after/{filename}.jpg       → fotos del equipo (al resolver)
/users/{userId}/avatar.jpg
```

---

## 3. Reglas de seguridad Firestore

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuth() { return request.auth != null; }
    function uid() { return request.auth.uid; }
    function userData() {
      return get(/databases/$(database)/documents/users/$(uid())).data;
    }
    function role() { return userData().role; }
    function isAdmin()       { return role() == 'admin' || role() == 'moderator'; }
    function isCoordinator() { return role() == 'coordinator' || isAdmin(); }
    function isFieldWorker() { return role() == 'field_worker'; }
    function isOwner(id)     { return uid() == id; }
    function sameTeam(teamId) {
      return userData().teamId == teamId;
    }

    match /users/{userId} {
      allow read:   if isAdmin() || isOwner(userId);
      allow create: if isAuth() && isOwner(userId);
      allow update: if isOwner(userId) || isAdmin();
      allow delete: if isAdmin();
    }

    match /municipalities/{mId} {
      allow read:  if isAuth();
      allow write: if isAdmin();
    }

    match /teams/{teamId} {
      allow read:  if isAuth();
      allow write: if isCoordinator();
    }

    match /reports/{reportId} {
      // Lectura: ciudadanos ven lo no oculto; coordinador y campo ven todo
      allow read: if isAuth() && (
        resource.data.hidden == false ||
        isAdmin() ||
        isCoordinator() ||
        isOwner(resource.data.userId) ||
        (isFieldWorker() && sameTeam(resource.data.assignedTeamId))
      );

      // Crear: cualquier ciudadano autenticado
      allow create: if isAuth();

      // Actualizar:
      // - Ciudadano: solo sus reportes en pending (editar)
      // - Coordinador: puede asignar, cambiar estado, rechazar
      // - Equipo de campo: puede subir fotos before/after y cambiar estado a in_progress/resolved
      allow update: if isAuth() && (
        (isOwner(resource.data.userId) && resource.data.status == 'pending') ||
        isCoordinator() ||
        (isFieldWorker() && sameTeam(resource.data.assignedTeamId))
      );

      allow delete: if isAdmin();

      match /comments/{commentId} {
        allow read:   if isAuth() && resource.data.hidden == false;
        allow create: if isAuth();
        allow update: if isOwner(resource.data.userId) || isAdmin();
        allow delete: if isAdmin();
      }

      match /supportVotes/{voteUserId} {
        allow read:   if isAuth();
        allow create: if isAuth() && isOwner(voteUserId);
        allow delete: if isOwner(voteUserId);
      }
    }

    match /contentFlags/{flagId} {
      allow read:   if isAdmin();
      allow create: if isAuth();
      allow update: if isAdmin();
    }

    match /notifications/{notId} {
      allow read, update: if isAuth() && isOwner(resource.data.userId);
      allow create:       if isAdmin();
    }
  }
}
```

---

## 4. Reglas Firebase Storage

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    match /reports/{reportId}/citizen/{file} {
      allow read:  if request.auth != null;
      allow write: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }

    match /reports/{reportId}/before/{file} {
      allow read:  if request.auth != null;
      // Solo field_worker asignado puede subir
      allow write: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }

    match /reports/{reportId}/after/{file} {
      allow read:  if request.auth != null;
      allow write: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }

    match /users/{userId}/{file} {
      allow read:  if request.auth != null;
      allow write: if request.auth.uid == userId
        && request.resource.size < 2 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }
  }
}
```

---

## 5. Cloud Functions

| Función | Trigger | Acción |
|---------|---------|--------|
| `onReportCreated` | Firestore: reports create | Notifica a coordinadores del municipio |
| `onReportAssigned` | Firestore: reports update (status: assigned) | Push al equipo de campo asignado |
| `onWorkerArrived` | Firestore: reports update (status: in_progress) | Push al ciudadano "El equipo ya está en el lugar" |
| `onReportResolved` | Firestore: reports update (status: resolved) | Push al ciudadano + envía link al antes/después |
| `onSupportVote` | Firestore: supportVotes create | Recalcula `priority` del reporte |
| `onUserDelete` | Auth: user deleted | Borra todos los datos del usuario (GDPR) |
| `resizePhoto` | Storage: any /reports/ upload | Redimensiona a máx. 1200px |
| `rateLimitReports` | Firestore: reports create | Rechaza si > 10 reportes en 24h |
| `autoCloseResolved` | Cron diario | Marca como `closed` reportes resueltos hace > 30 días sin calificación |

---

## 6. Fórmula de prioridad

```
priority = (supportCount * 0.4) + (hoursSinceCreation * 0.3) + (categoryWeight * 0.3)

categoryWeight:
  security → 5
  health   → 5
  lighting → 4
  infrastructure → 3
  garbage  → 2
  other    → 1
```

La Cloud Function `onSupportVote` recalcula el campo `priority` en cada voto.

---

## 7. Data Safety Play Store

| Dato | Propósito | Vinculado a identidad |
|------|-----------|----------------------|
| Correo | Autenticación | Sí |
| Nombre | Perfil público anonimizado | No (se muestra como #XXXX) |
| Fotos | Reportar y resolver problemas | Sí |
| Ubicación precisa | Geolocalizar el reporte | Sí |
| FCM token | Notificaciones push | No |

---

## 8. Checklist antes del módulo 5 (código Flutter)

- [ ] Crear proyecto Firebase Console
- [ ] Activar: Auth, Firestore, Storage, Cloud Messaging, Cloud Functions
- [ ] Crear proyecto en Google Cloud → activar Maps SDK (Android + iOS) y Geocoding API
- [ ] Obtener google-services.json y GoogleService-Info.plist
- [ ] Definir nombre final de la app (afecta bundle ID y ficha Play Store)
- [ ] Decidir: ¿coordinador usa la misma app con rol o panel web separado?
