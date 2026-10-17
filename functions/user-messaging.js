'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { deliverToUsers } = require('./push-delivery');

const REGION = 'southamerica-east1';
const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const CONSENT_VERSION = 2;

function cleanText(value, max) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    .replace(/https?:\/\/\S+/gi, '[enlace omitido]')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function validId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,80}$/.test(value);
}

async function requireStaff(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const db = getFirestore();
  const profile = await db.collection('users').doc(uid).get();
  const role = profile.get('role');
  if (!profile.exists || profile.get('disabled') === true || !MANAGEMENT_ROLES.has(role)) {
    throw new HttpsError('permission-denied', 'No tenés permiso para enviar mensajes.');
  }
  return { db, role, municipalityId: profile.get('municipalityId') };
}

/**
 * Mensaje personalizado del municipio a la app de los vecinos.
 *  audience: { type: 'user', uid } | { type: 'municipality', municipalityId? } | { type: 'all' }
 * El personal solo escribe a su propio municipio; 'all' y otros municipios son
 * exclusivos del administrador.
 */
async function sendCustomMessageHandler(request) {
  const { db, role, municipalityId: ownMunicipality } = await requireStaff(request);
  const title = cleanText(request.data?.title, 80);
  const body = cleanText(request.data?.body, 280);
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
    if (!target.exists) throw new HttpsError('not-found', 'El usuario no existe.');
    if (role !== 'admin' && target.get('municipalityId') !== ownMunicipality) {
      throw new HttpsError('permission-denied', 'Ese usuario es de otro municipio.');
    }
    return finish(db, [{ uid: target.id, fcmToken: target.get('fcmToken') }], requestId, title, body);
  }
  if (audience.type === 'municipality') {
    const target = role === 'admin' && audience.municipalityId ? audience.municipalityId : ownMunicipality;
    if (role !== 'admin' && audience.municipalityId && audience.municipalityId !== ownMunicipality) {
      throw new HttpsError('permission-denied', 'Solo podés escribir a tu municipio.');
    }
    if (!target) throw new HttpsError('failed-precondition', 'No hay municipio asignado.');
    query = query.where('municipalityId', '==', target);
  } else if (audience.type === 'all') {
    if (role !== 'admin') throw new HttpsError('permission-denied', 'Solo el administrador puede escribir a todos.');
  } else {
    throw new HttpsError('invalid-argument', 'Elegí a quién enviar el mensaje.');
  }
  query = query.where('role', '==', 'citizen');
  const snapshot = await query.get();
  const recipients = snapshot.docs.map((doc) => ({ uid: doc.id, fcmToken: doc.get('fcmToken') }));
  return finish(db, recipients, requestId, title, body);
}

async function finish(db, recipients, requestId, title, body) {
  if (!recipients.length) return { ok: true, total: 0, pushed: 0, inApp: 0 };
  const result = await deliverToUsers(db, recipients, {
    key: `custom_${requestId}`,
    type: 'municipality_message',
    title,
    body,
  });
  return { ok: true, ...result };
}

/**
 * Guarda únicamente el consentimiento para la medición territorial. La
 * agregación se hace por ciudad/municipio declarado en el perfil: no se
 * conserva IP, ubicación exacta, cuenta, teléfono ni identidad del equipo.
 */
async function saveDeviceProfileHandler(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  if (request.data?.consent !== true) {
    throw new HttpsError('failed-precondition', 'Hace falta tu consentimiento para guardar estos datos.');
  }

  await getFirestore().collection('userDevices').doc(uid).set({
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
async function deleteDeviceProfileHandler(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  await getFirestore().collection('userDevices').doc(uid).delete();
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
  cleanText,
  CONSENT_VERSION,
};
