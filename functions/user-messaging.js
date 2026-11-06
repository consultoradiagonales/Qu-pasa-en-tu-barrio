'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { deliverToUsers } = require('./push-delivery');
const { isCentralAdmin } = require('./management-access');

const REGION = 'southamerica-east1';
const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const CONSENT_VERSION = 2;
const MAX_SELECTED_RECIPIENTS = 100;
const MAX_MESSAGE_TITLE_LENGTH = 120;
const MAX_MESSAGE_BODY_LENGTH = 4000;
const OFFICIAL_UPDATE_URLS = new Set([
  'https://play.google.com/apps/internaltest/4701647237677047143',
  'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi',
]);

function cleanMessageUrl(value) {
  if (typeof value !== 'string') return '[enlace omitido]';
  const trailing = value.match(/[.,;:!?)]*$/)?.[0] || '';
  const candidate = value.slice(0, value.length - trailing.length);
  return OFFICIAL_UPDATE_URLS.has(candidate) ? candidate + trailing : '[enlace omitido]';
}

function cleanActionUrl(value) {
  if (typeof value !== 'string') return '';
  const candidate = value.trim();
  return OFFICIAL_UPDATE_URLS.has(candidate) ? candidate : '';
}

function actionUrlFromBody(body) {
  for (const url of OFFICIAL_UPDATE_URLS) {
    if (body.includes(url)) return url;
  }
  return '';
}

function cleanText(value, max) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    // El panel solo conserva los dos enlaces oficiales de actualización. Así
    // el municipio puede pedir una actualización sin abrir mensajes a URLs
    // externas o de suplantación.
    .replace(/https?:\/\/\S+/gi, cleanMessageUrl)
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function validId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,80}$/.test(value);
}

function validRecipientId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 &&
    value.trim() === value && !value.includes('/');
}

async function requireStaff(request, deps = {}) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const db = deps.db || getFirestore();
  const profile = await db.collection('users').doc(uid).get();
  const role = profile.get('role');
  if (!profile.exists || profile.get('disabled') === true || !MANAGEMENT_ROLES.has(role)) {
    throw new HttpsError('permission-denied', 'No tenés permiso para enviar mensajes.');
  }
  if (!isCentralAdmin(profile.data()) && !profile.get('municipalityId')) {
    throw new HttpsError('permission-denied', 'La cuenta no tiene municipio asignado.');
  }
  return { db, role, central: isCentralAdmin(profile.data()), municipalityId: profile.get('municipalityId') };
}

/**
 * Mensaje personalizado del municipio a la app de los vecinos.
 *  audience: { type: 'user', uid } | { type: 'users', uids } |
 *    { type: 'municipality', municipalityId? } | { type: 'all' }
 * El personal solo escribe a su propio municipio; 'all' y otros municipios son
 * exclusivos del administrador.
 */
async function sendCustomMessageHandler(request, deps = {}) {
  const { db, central, municipalityId: ownMunicipality } = await requireStaff(request, deps);
  const title = cleanText(request.data?.title, MAX_MESSAGE_TITLE_LENGTH);
  const body = cleanText(request.data?.body, MAX_MESSAGE_BODY_LENGTH);
  const actionUrl =
    cleanActionUrl(request.data?.actionUrl) || actionUrlFromBody(body);
  const requestId = request.data?.requestId;
  const audience = request.data?.audience || {};
  if (title.length < 3 || body.length < 3) {
    throw new HttpsError('invalid-argument', 'Escribí un título y un mensaje de al menos 3 caracteres.');
  }
  if (!validId(requestId)) {
    throw new HttpsError('invalid-argument', 'La solicitud no es válida.');
  }

  let query = db.collection('users').where('disabled', '==', false);
  if (audience.type === 'user') {
    if (typeof audience.uid !== 'string' || !audience.uid || audience.uid.includes('/')) {
      throw new HttpsError('invalid-argument', 'El destinatario no es válido.');
    }
    const target = await db.collection('users').doc(audience.uid).get();
    if (!target.exists || target.get('disabled') === true || target.get('role') !== 'citizen') {
      throw new HttpsError('not-found', 'El vecino no existe.');
    }
    if (!central && target.get('municipalityId') !== ownMunicipality) {
      throw new HttpsError('permission-denied', 'Ese usuario es de otro municipio.');
    }
    return finish(db, [{ uid: target.id, fcmToken: target.get('fcmToken') }], requestId, title, body, actionUrl, deps);
  }
  if (audience.type === 'users') {
    if (!Array.isArray(audience.uids) || audience.uids.length === 0 ||
        audience.uids.length > MAX_SELECTED_RECIPIENTS ||
        audience.uids.some((uid) => !validRecipientId(uid))) {
      throw new HttpsError('invalid-argument', 'Elegí entre 1 y 100 vecinos válidos.');
    }
    const uids = [...new Set(audience.uids)];
    const targets = await Promise.all(uids.map((uid) => db.collection('users').doc(uid).get()));
    for (const target of targets) {
      if (!target.exists || target.get('disabled') === true || target.get('role') !== 'citizen') {
        throw new HttpsError('not-found', 'Uno de los vecinos ya no está disponible.');
      }
      if (!central && target.get('municipalityId') !== ownMunicipality) {
        throw new HttpsError('permission-denied', 'Solo podés escribir a vecinos de tu municipio.');
      }
    }
    return finish(db, targets.map((target) => ({
      uid: target.id,
      fcmToken: target.get('fcmToken'),
    })), requestId, title, body, actionUrl, deps);
  }
  if (audience.type === 'municipality') {
    const target = central && audience.municipalityId ? audience.municipalityId : ownMunicipality;
    if (!central && audience.municipalityId && audience.municipalityId !== ownMunicipality) {
      throw new HttpsError('permission-denied', 'Solo podés escribir a tu municipio.');
    }
    if (!target) throw new HttpsError('failed-precondition', 'No hay municipio asignado.');
    query = query.where('municipalityId', '==', target).where('role', '==', 'citizen');
  } else if (audience.type === 'all') {
    if (!central) throw new HttpsError('permission-denied', 'Solo la consultora puede escribir a todos.');
    query = query.where('role', '==', 'citizen');
  } else {
    throw new HttpsError('invalid-argument', 'Elegí a quién enviar el mensaje.');
  }
  // "Todos" y "municipio" se dirigen exclusivamente a vecinos activos.
  const snapshot = await query.get();
  const recipients = snapshot.docs.map((doc) => ({ uid: doc.id, fcmToken: doc.get('fcmToken') }));
  return finish(db, recipients, requestId, title, body, actionUrl, deps);
}

async function finish(db, recipients, requestId, title, body, actionUrl, deps = {}) {
  if (!recipients.length) return { ok: true, total: 0, pushed: 0, inApp: 0 };
  const result = await deliverToUsers(db, recipients, {
    key: `custom_${requestId}`,
    type: 'municipality_message',
    title,
    body,
    data: actionUrl ? { actionUrl } : {},
  }, deps.messaging);
  return { ok: true, ...result };
}

/**
 * Guarda únicamente el consentimiento para la medición territorial. La
 * agregación se hace por ciudad/municipio declarado en el perfil: no se
 * conserva IP, ubicación exacta, cuenta, teléfono ni identidad del equipo.
 */
async function saveDeviceProfileHandler(request, deps = {}) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  if (request.data?.consent !== true) {
    throw new HttpsError('failed-precondition', 'Hace falta tu consentimiento para guardar estos datos.');
  }

  await (deps.db || getFirestore()).collection('userDevices').doc(uid).set({
    consent: { given: true, version: CONSENT_VERSION, at: FieldValue.serverTimestamp() },
    usageAnalytics: {
      enabled: true,
      source: 'profile_territory',
      rawIpStored: false,
      exactLocationStored: false,
    },
    // Limpia los campos invasivos de la versión anterior cuando la persona
    // actualiza su consentimiento a esta versión.
    account: FieldValue.delete(),
    device: FieldValue.delete(),
    network: FieldValue.delete(),
    location: FieldValue.delete(),
    phone: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, consentVersion: CONSENT_VERSION };
}

/** Derecho a retirar el consentimiento: borra todo lo guardado. */
async function deleteDeviceProfileHandler(request, deps = {}) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  await (deps.db || getFirestore()).collection('userDevices').doc(uid).delete();
  return { ok: true };
}

const sendCustomMessage = onCall({ region: REGION }, sendCustomMessageHandler);
const saveDeviceProfile = onCall({ region: REGION }, saveDeviceProfileHandler);
const deleteDeviceProfile = onCall({ region: REGION }, deleteDeviceProfileHandler);

module.exports = {
  sendCustomMessage,
  saveDeviceProfile,
  deleteDeviceProfile,
  sendCustomMessageHandler,
  saveDeviceProfileHandler,
  deleteDeviceProfileHandler,
  cleanText,
  cleanActionUrl,
  MAX_MESSAGE_TITLE_LENGTH,
  MAX_MESSAGE_BODY_LENGTH,
  CONSENT_VERSION,
  MAX_SELECTED_RECIPIENTS,
};
