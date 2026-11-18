'use strict';

// Directorio de vecinos para Mensajería: completa el correo y el nombre desde
// Firebase Auth cuando el perfil de Firestore no los tiene, para que el
// personal pueda identificar a quién le escribe. Sólo devuelve datos de
// vecinos activos del municipio que la cuenta puede gestionar (la consultora,
// de cualquiera). No expone teléfono, proveedor ni metadatos de la cuenta.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { isCentralAdmin } = require('./management-access');

const REGION = 'southamerica-east1';
const STAFF_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const MAX_RESIDENTS = 2000;
const AUTH_BATCH = 100;

async function residentDirectoryHandler(request, deps = {}) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const db = deps.db || getFirestore();
  const auth = deps.auth || getAuth();
  const snap = await db.collection('users').doc(uid).get();
  const profile = snap.exists ? snap.data() : null;
  if (!profile || profile.disabled === true || !STAFF_ROLES.has(profile.role)) {
    throw new HttpsError('permission-denied', 'No tenés permiso para ver vecinos.');
  }
  const central = isCentralAdmin(profile);
  const requested = typeof request.data?.municipalityId === 'string' ? request.data.municipalityId.trim() : '';
  const municipalityId = central ? requested : profile.municipalityId;
  if (!central && requested && requested !== profile.municipalityId) {
    throw new HttpsError('permission-denied', 'Sólo podés ver vecinos de tu municipio.');
  }
  if (!municipalityId && !central) throw new HttpsError('failed-precondition', 'La cuenta no tiene municipio asignado.');

  let query = db.collection('users').where('role', '==', 'citizen').where('disabled', '==', false);
  if (municipalityId) query = query.where('municipalityId', '==', municipalityId);
  const residents = (await query.get()).docs.slice(0, MAX_RESIDENTS);

  // Sólo se consulta Auth por quienes no tienen correo o nombre en el perfil.
  const missing = residents.filter((doc) => !doc.get('email') || !(doc.get('realName') || doc.get('displayName')));
  const fromAuth = new Map();
  for (let i = 0; i < missing.length; i += AUTH_BATCH) {
    const chunk = missing.slice(i, i + AUTH_BATCH).map((doc) => ({ uid: doc.id }));
    try {
      const result = await auth.getUsers(chunk);
      result.users.forEach((user) => fromAuth.set(user.uid, { email: user.email || '', displayName: user.displayName || '' }));
    } catch (_) {
      // Si Auth no responde, se devuelve lo que haya en Firestore.
    }
  }

  return {
    residents: residents.map((doc) => {
      const extra = fromAuth.get(doc.id) || {};
      return {
        uid: doc.id,
        email: doc.get('email') || extra.email || '',
        name: doc.get('realName') || doc.get('displayName') || extra.displayName || '',
      };
    }),
  };
}

const residentDirectory = onCall({ region: REGION }, (request) => residentDirectoryHandler(request));

module.exports = { residentDirectory, residentDirectoryHandler };
