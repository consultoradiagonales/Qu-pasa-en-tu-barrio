'use strict';

// Alertas meteorológicas manuales desde el panel de gestión.
//
// - sendWeatherAlert: emite una alerta a todos los vecinos activos de un
//   municipio (queda en /weatherAlerts y en la bandeja de cada vecino).
// - correctWeatherAlert: corrige o deja sin efecto una alerta ya enviada
//   (manual o automática). Reescribe el aviso en la bandeja de quienes la
//   recibieron y, si se pide, manda una notificación nueva con la corrección.
//
// Sólo administración y coordinación. El personal municipal opera únicamente
// sobre su propio municipio; la consultora, sobre cualquiera.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { deliverToUsers } = require('./push-delivery');
const { isCentralAdmin } = require('./management-access');
const {
  argentinaDay,
  alertTimingText,
  canonicalMunicipalityId,
  stableHash,
} = require('./weather-alerts');

const REGION = 'southamerica-east1';
const ALERT_ROLES = new Set(['admin', 'coordinator']);
const MAX_TITLE = 120;
const MAX_MESSAGE = 3500;
const MAX_REASON = 300;
const MAX_HISTORY = 20;

const LEVEL_NAMES = { 1: 'amarilla', 2: 'naranja', 3: 'roja' };
const HAZARDS = {
  lluvia: 'lluvias intensas',
  tormenta: 'tormentas',
  viento: 'vientos fuertes',
  calor: 'calor extremo',
  frio: 'frío extremo',
  nieve: 'nevadas',
  niebla: 'niebla',
  crecida: 'crecida de ríos y arroyos',
  otro: 'fenómeno meteorológico',
};

function cleanText(value, max) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    // Las alertas no llevan enlaces: evita suplantación y phishing.
    .replace(/https?:\/\/\S+/gi, '[enlace omitido]')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function validRequestId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,64}$/.test(value);
}

function validAlertId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 200 && !value.includes('/');
}

function cleanLevel(value) {
  const level = Number(value);
  if (![1, 2, 3].includes(level)) throw new HttpsError('invalid-argument', 'Elegí el nivel: amarilla, naranja o roja.');
  return level;
}

function cleanHazard(value) {
  const hazard = String(value || '').toLowerCase();
  if (!HAZARDS[hazard]) throw new HttpsError('invalid-argument', 'Elegí el fenómeno de la alerta.');
  return hazard;
}

/** Milisegundos o null. Acepta números y textos ISO; rechaza fechas absurdas. */
function cleanTime(value) {
  if (value == null || value === '') return null;
  const ms = typeof value === 'number' ? value : Date.parse(String(value));
  if (!Number.isFinite(ms)) throw new HttpsError('invalid-argument', 'La fecha de vigencia no es válida.');
  const year = new Date(ms).getUTCFullYear();
  if (year < 2024 || year > 2100) throw new HttpsError('invalid-argument', 'La fecha de vigencia no es válida.');
  return ms;
}

function cleanContent(data = {}) {
  const level = cleanLevel(data.level);
  const hazard = cleanHazard(data.hazard);
  const title = cleanText(data.title, MAX_TITLE);
  const message = cleanText(data.message ?? data.body, MAX_MESSAGE);
  if (title.length < 5 || message.length < 10) {
    throw new HttpsError('invalid-argument', 'Escribí un título (5+ caracteres) y un mensaje (10+ caracteres).');
  }
  const onset = cleanTime(data.onset);
  const expires = cleanTime(data.expires);
  if (onset && expires && expires <= onset) {
    throw new HttpsError('invalid-argument', 'La vigencia debe terminar después de empezar.');
  }
  return { level, hazard, title, message, onset, expires };
}

/** Texto que lee el vecino: mensaje + vigencia, si se informó. */
function composeBody({ message, onset, expires }) {
  const timing = alertTimingText({ onset, expires });
  return `${message}${timing ? ` ${timing}` : ''}`.slice(0, 4000);
}

async function requireAlertStaff(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const snap = await db.collection('users').doc(uid).get();
  const profile = snap.exists ? snap.data() : null;
  if (!profile || profile.disabled === true || !ALERT_ROLES.has(profile.role)) {
    throw new HttpsError('permission-denied', 'Sólo administración o coordinación pueden emitir alertas.');
  }
  const central = isCentralAdmin(profile);
  if (!central && !profile.municipalityId) {
    throw new HttpsError('permission-denied', 'La cuenta no tiene municipio asignado.');
  }
  return { uid, central, municipalityId: canonicalMunicipalityId(profile.municipalityId) };
}

function assertMunicipality(staff, municipalityId) {
  if (!municipalityId) throw new HttpsError('invalid-argument', 'Elegí el municipio.');
  if (!staff.central && municipalityId !== staff.municipalityId) {
    throw new HttpsError('permission-denied', 'Sólo podés emitir alertas para tu municipio.');
  }
}

async function municipalityRecipients(db, municipalityId) {
  const snapshot = await db.collection('users')
    .where('role', '==', 'citizen')
    .where('disabled', '==', false)
    .where('municipalityId', '==', municipalityId)
    .get();
  return snapshot.docs.map((doc) => ({ uid: doc.id, fcmToken: doc.get('fcmToken') }));
}

async function municipalityName(db, municipalityId, fallback = '') {
  try {
    const snap = await db.collection('municipalities').doc(municipalityId).get();
    if (snap.exists) return cleanText(snap.get('name') || snap.get('displayName'), 120) || fallback || municipalityId;
  } catch (_) {
    // Sin catálogo: se usa el id.
  }
  return fallback || municipalityId;
}

async function sendWeatherAlertHandler(request, deps = {}) {
  const db = deps.db || getFirestore();
  const staff = await requireAlertStaff(request, db);
  const data = request.data || {};
  if (!validRequestId(data.requestId)) throw new HttpsError('invalid-argument', 'La solicitud no es válida.');
  const municipalityId = canonicalMunicipalityId(data.municipalityId);
  assertMunicipality(staff, municipalityId);
  const content = cleanContent(data);
  const name = await municipalityName(db, municipalityId, cleanText(data.municipalityName, 120));
  const now = deps.now || new Date();
  const day = argentinaDay(now);
  const alertId = `${municipalityId}_${day}_manual_${data.requestId}`;
  const deliveryKey = `weather_manual_${data.requestId}`;
  const body = composeBody(content);
  const alertRef = db.collection('weatherAlerts').doc(alertId);
  try {
    await alertRef.create({
      municipalityId,
      municipalityName: name,
      affectedZones: [name],
      affectedArea: name,
      source: 'manual',
      status: 'active',
      revision: 1,
      hazard: `manual_${content.hazard}`,
      hazardKind: content.hazard,
      level: content.level,
      day,
      title: content.title,
      message: content.message,
      body,
      onset: content.onset,
      expires: content.expires,
      versionKey: 'manual',
      deliveryKey,
      argwx: cleanArgwx(data.argwx),
      createdBy: staff.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (error?.code === 6 || error?.code === 'already-exists') {
      throw new HttpsError('already-exists', 'Esta alerta ya se envió.');
    }
    throw error;
  }
  const recipients = await municipalityRecipients(db, municipalityId);
  const delivered = recipients.length
    ? await deliverToUsers(db, recipients, {
      key: deliveryKey,
      type: 'weather_alert',
      title: content.title,
      body,
      data: alertData(alertId, municipalityId, name, content),
    }, deps.messaging)
    : { total: 0, pushed: 0, inApp: 0 };
  await alertRef.set({ delivered }, { merge: true });
  return { ok: true, alertId, ...delivered };
}

function alertData(alertId, municipalityId, name, content) {
  return {
    alertId,
    municipalityId,
    municipalityName: name,
    affectedZones: [name],
    affectedArea: name,
    onset: content.onset ?? '',
    expires: content.expires ?? '',
    versionKey: 'manual',
    level: content.level,
  };
}

/** Datos del motor ARGWX que motivaron la alerta (sólo referencia). */
function cleanArgwx(value) {
  if (!value || typeof value !== 'object') return null;
  const out = {
    id: cleanText(value.id, 60),
    level: cleanText(value.level, 12),
    window: cleanText(value.window, 4),
    generatedAt: cleanText(value.generatedAt, 40),
  };
  return out.id ? out : null;
}

/** Claves de entrega posibles de una alerta (manual o automática, actual o histórica). */
function deliveryKeysFor(alertId, alert) {
  const keys = new Set();
  if (typeof alert.deliveryKey === 'string' && alert.deliveryKey) keys.add(alert.deliveryKey);
  const versionKey = typeof alert.versionKey === 'string' && alert.versionKey ? alert.versionKey : 'daily';
  const versioned = `weather_${alertId}_${versionKey}`;
  keys.add(/^[A-Za-z0-9_-]{1,180}$/.test(versioned) ? versioned : `weather_${stableHash(alertId, 24)}_${versionKey}`);
  if (/^[A-Za-z0-9_-]{1,180}$/.test(`weather_${alertId}`)) keys.add(`weather_${alertId}`);
  return [...keys];
}

async function mapLimited(items, limit, fn) {
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const index = next++;
      await fn(items[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, worker));
}

/** Reescribe en la bandeja de cada vecino el aviso original. Devuelve cuántos cambió. */
async function rewriteInboxes(db, alertId, alert, recipients, { title, body, status }) {
  const keys = deliveryKeysFor(alertId, alert);
  const refs = [];
  recipients.forEach((user) => keys.forEach((key) => refs.push(db.collection('notifications').doc(`${key}_${user.uid}`))));
  let updated = 0;
  await mapLimited(refs, 25, async (ref) => {
    const snap = await ref.get();
    if (!snap.exists) return;
    await ref.update({ title, body, alertStatus: status, correctedAt: FieldValue.serverTimestamp() });
    updated += 1;
  });
  return updated;
}

async function correctWeatherAlertHandler(request, deps = {}) {
  const db = deps.db || getFirestore();
  const staff = await requireAlertStaff(request, db);
  const data = request.data || {};
  if (!validRequestId(data.requestId)) throw new HttpsError('invalid-argument', 'La solicitud no es válida.');
  if (!validAlertId(data.alertId)) throw new HttpsError('invalid-argument', 'La alerta no es válida.');
  const action = data.action === 'cancel' ? 'cancel' : data.action === 'correct' ? 'correct' : null;
  if (!action) throw new HttpsError('invalid-argument', 'Elegí corregir o dejar sin efecto.');

  const alertRef = db.collection('weatherAlerts').doc(data.alertId);
  const snap = await alertRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'La alerta ya no existe.');
  const alert = snap.data();
  const municipalityId = canonicalMunicipalityId(alert.municipalityId);
  assertMunicipality(staff, municipalityId);
  if (alert.status === 'cancelled') throw new HttpsError('failed-precondition', 'La alerta ya quedó sin efecto.');
  if (Array.isArray(alert.corrections) && alert.corrections.some((c) => c.requestId === data.requestId)) {
    return { ok: true, alertId: data.alertId, duplicate: true };
  }

  const reason = cleanText(data.reason, MAX_REASON);
  const notify = data.notify === true;
  const name = alert.municipalityName || municipalityId;
  let next;
  if (action === 'correct') {
    const content = cleanContent(data);
    const body = composeBody(content);
    next = {
      status: 'corrected',
      level: content.level,
      hazardKind: content.hazard,
      title: content.title,
      message: content.message,
      body,
      onset: content.onset,
      expires: content.expires,
      inboxTitle: `Corregida: ${content.title}`.slice(0, MAX_TITLE),
      inboxBody: `${reason ? `Corrección: ${reason}. ` : ''}${body}`.slice(0, 4000),
      notifyTitle: `Corrección: ${content.title}`.slice(0, MAX_TITLE),
    };
  } else {
    const title = cleanText(alert.title, MAX_TITLE) || 'Alerta meteorológica';
    const body = `La alerta "${title}" para ${name} quedó sin efecto.${reason ? ` Motivo: ${reason}.` : ''}`;
    next = {
      status: 'cancelled',
      inboxTitle: `Sin efecto: ${title}`.slice(0, MAX_TITLE),
      inboxBody: `${body} Mensaje original: ${cleanText(alert.body, 3000)}`.slice(0, 4000),
      notifyTitle: `Sin efecto: ${title}`.slice(0, MAX_TITLE),
      notifyBody: body,
    };
  }

  const revision = Number(alert.revision) > 0 ? Number(alert.revision) + 1 : 2;
  const previous = {
    revision: revision - 1,
    status: alert.status || 'active',
    level: alert.level ?? null,
    title: alert.title || '',
    body: alert.body || '',
    onset: alert.onset ?? null,
    expires: alert.expires ?? null,
  };
  const correction = {
    requestId: data.requestId,
    action,
    reason,
    notify,
    by: staff.uid,
    atMs: (deps.now || new Date()).getTime(),
  };
  const update = {
    status: next.status,
    revision,
    adminEdited: true,
    history: [...(Array.isArray(alert.history) ? alert.history : []), previous].slice(-MAX_HISTORY),
    corrections: [...(Array.isArray(alert.corrections) ? alert.corrections : []), correction].slice(-MAX_HISTORY),
    correctedBy: staff.uid,
    correctedAt: FieldValue.serverTimestamp(),
  };
  if (action === 'correct') {
    Object.assign(update, {
      level: next.level,
      hazardKind: next.hazardKind,
      title: next.title,
      message: next.message,
      body: next.body,
      onset: next.onset,
      expires: next.expires,
    });
  } else {
    update.cancelReason = reason;
  }
  await alertRef.set(update, { merge: true });

  const recipients = await municipalityRecipients(db, municipalityId);
  const rewritten = await rewriteInboxes(db, data.alertId, alert, recipients, {
    title: next.inboxTitle,
    body: next.inboxBody,
    status: next.status,
  });

  let delivered = { total: 0, pushed: 0, inApp: 0 };
  if (notify && recipients.length) {
    delivered = await deliverToUsers(db, recipients, {
      key: `weatherfix_${data.requestId}`,
      type: 'weather_alert',
      title: next.notifyTitle,
      body: action === 'correct' ? next.inboxBody : next.notifyBody,
      data: {
        alertId: data.alertId,
        municipalityId,
        municipalityName: name,
        alertStatus: next.status,
        versionKey: `rev${revision}`,
      },
    }, deps.messaging);
  }
  return { ok: true, alertId: data.alertId, status: next.status, revision, rewritten, ...delivered };
}

const sendWeatherAlert = onCall({ region: REGION }, (request) => sendWeatherAlertHandler(request));
const correctWeatherAlert = onCall({ region: REGION }, (request) => correctWeatherAlertHandler(request));

module.exports = {
  sendWeatherAlert,
  correctWeatherAlert,
  sendWeatherAlertHandler,
  correctWeatherAlertHandler,
  deliveryKeysFor,
  composeBody,
  cleanContent,
  HAZARDS,
  LEVEL_NAMES,
};
