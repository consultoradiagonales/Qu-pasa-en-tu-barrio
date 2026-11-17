'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { isCentralAdmin } = require('./management-access');

const REGION = 'southamerica-east1';
const RELEASE_DOCUMENT = 'appConfiguration/mobileRelease';
const ADMIN_ROLE = 'admin';
const ANDROID_PLAY_URL = 'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi';
const ANDROID_PACKAGE_ID = 'ar.com.consultoradiagonales.condi';
const MAX_BUILD = 2147483647;

const DEFAULT_RELEASE = Object.freeze({
  minAndroidBuild: 14,
  androidStoreUrl: ANDROID_PLAY_URL,
  minIosBuild: 0,
  iosStoreUrl: '',
  androidMessage: 'Hay una nueva versión de ConDi con mejoras importantes. Actualizá la app para continuar.',
  iosMessage: 'Hay una nueva versión de ConDi con mejoras importantes. Actualizá la app para continuar.',
});

function cleanText(value, max = 240) {
  if (typeof value !== 'string') return '';
  return value.replace(/[\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

function validStoreUrl(value, platform) {
  const url = cleanText(value, 2048);
  if (!url) return '';
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:') return '';
    if (platform === 'android') {
      if (parsed.hostname !== 'play.google.com' || parsed.pathname !== '/store/apps/details' ||
          parsed.searchParams.getAll('id').length !== 1 || parsed.searchParams.get('id') !== ANDROID_PACKAGE_ID) return '';
      return ANDROID_PLAY_URL;
    }
    if (platform === 'ios' && parsed.hostname !== 'apps.apple.com') return '';
    return parsed.toString();
  } catch (_) {
    return '';
  }
}

function validBuild(value, fallback) {
  const build = Number(value);
  return Number.isSafeInteger(build) && build >= 0 && build <= MAX_BUILD ? build : fallback;
}

function publicRelease(data = {}) {
  const minAndroidBuild = validBuild(data.minAndroidBuild, DEFAULT_RELEASE.minAndroidBuild);
  const minIosBuild = validBuild(data.minIosBuild, DEFAULT_RELEASE.minIosBuild);
  const androidStoreUrl = validStoreUrl(data.androidStoreUrl, 'android') || DEFAULT_RELEASE.androidStoreUrl;
  const iosStoreUrl = validStoreUrl(data.iosStoreUrl, 'ios');
  return {
    android: {
      minBuild: minAndroidBuild,
      storeUrl: androidStoreUrl,
      message: cleanText(data.androidMessage, 240) || DEFAULT_RELEASE.androidMessage,
    },
    ios: {
      minBuild: minIosBuild,
      storeUrl: iosStoreUrl,
      message: cleanText(data.iosMessage, 240) || DEFAULT_RELEASE.iosMessage,
    },
  };
}

async function requireAdmin(request, db = getFirestore()) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const profile = await db.collection('users').doc(uid).get();
  if (!profile.exists || !isCentralAdmin(profile.data())) {
    throw new HttpsError('permission-denied', 'Solo la administración puede configurar actualizaciones.');
  }
}

async function getAppReleaseHandler() {
  const snapshot = await getFirestore().doc(RELEASE_DOCUMENT).get();
  return publicRelease(snapshot.exists ? snapshot.data() : {});
}

const PLATFORM_FIELDS = Object.freeze({
  android: { build: 'minAndroidBuild', url: 'androidStoreUrl', message: 'androidMessage' },
  ios: { build: 'minIosBuild', url: 'iosStoreUrl', message: 'iosMessage' },
});

function requestedBuild(source, field) {
  const value = source[field];
  if (typeof value === 'number' || (typeof value === 'string' && value.trim() !== '')) {
    const build = Number(value);
    if (Number.isSafeInteger(build) && build >= 0 && build <= MAX_BUILD) return build;
  }
  throw new HttpsError('invalid-argument', `${field} debe ser un entero entre 0 y ${MAX_BUILD}.`);
}

// Sólo escribe los campos presentes en la solicitud: guardar una plataforma
// nunca pisa la configuración guardada de la otra.
function releaseUpdate(source) {
  const data = {};
  for (const [platform, fields] of Object.entries(PLATFORM_FIELDS)) {
    if (Object.hasOwn(source, fields.build) && source[fields.build] !== undefined) {
      data[fields.build] = requestedBuild(source, fields.build);
    }
    if (Object.hasOwn(source, fields.url) && source[fields.url] !== undefined) {
      const url = validStoreUrl(source[fields.url], platform);
      data[fields.url] = platform === 'android' ? (url || DEFAULT_RELEASE.androidStoreUrl) : url;
    }
    if (Object.hasOwn(source, fields.message) && source[fields.message] !== undefined) {
      data[fields.message] = cleanText(source[fields.message], 240) || DEFAULT_RELEASE[fields.message];
    }
  }
  return data;
}

async function saveAppReleaseHandler(request, deps = {}) {
  const db = deps.db || getFirestore();
  await requireAdmin(request, db);
  const source = request.data && typeof request.data === 'object' ? request.data : {};
  const data = releaseUpdate(source);
  if (!Object.keys(data).length) {
    throw new HttpsError('invalid-argument', 'No hay cambios de versión para guardar.');
  }
  data.updatedAt = FieldValue.serverTimestamp();
  const releaseRef = db.doc(RELEASE_DOCUMENT);
  await releaseRef.set(data, { merge: true });
  const saved = await releaseRef.get();
  return { ok: true, ...publicRelease(saved.exists === false ? {} : saved.data()) };
}

const getAppRelease = onCall({ region: REGION }, getAppReleaseHandler);
const saveAppRelease = onCall({ region: REGION }, saveAppReleaseHandler);

module.exports = {
  ANDROID_PLAY_URL,
  DEFAULT_RELEASE,
  getAppRelease,
  getAppReleaseHandler,
  publicRelease,
  saveAppRelease,
  saveAppReleaseHandler,
  releaseUpdate,
  validBuild,
  validStoreUrl,
};
