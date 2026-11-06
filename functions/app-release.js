'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { isCentralAdmin } = require('./management-access');

const REGION = 'southamerica-east1';
const RELEASE_DOCUMENT = 'appConfiguration/mobileRelease';
const ADMIN_ROLE = 'admin';
const ANDROID_PLAY_URL = 'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi';
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
    if (platform === 'android' && parsed.hostname !== 'play.google.com') return '';
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

async function requireAdmin(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const profile = await getFirestore().collection('users').doc(uid).get();
  if (!profile.exists || !isCentralAdmin(profile.data())) {
    throw new HttpsError('permission-denied', 'Solo la administración puede configurar actualizaciones.');
  }
}

async function getAppReleaseHandler() {
  const snapshot = await getFirestore().doc(RELEASE_DOCUMENT).get();
  return publicRelease(snapshot.exists ? snapshot.data() : {});
}

async function saveAppReleaseHandler(request) {
  await requireAdmin(request);
  const source = request.data || {};
  const release = publicRelease({
    minAndroidBuild: source.minAndroidBuild,
    androidStoreUrl: source.androidStoreUrl,
    minIosBuild: source.minIosBuild,
    iosStoreUrl: source.iosStoreUrl,
    androidMessage: source.androidMessage,
    iosMessage: source.iosMessage,
  });
  const data = {
    minAndroidBuild: release.android.minBuild,
    androidStoreUrl: release.android.storeUrl,
    minIosBuild: release.ios.minBuild,
    iosStoreUrl: release.ios.storeUrl,
    androidMessage: release.android.message,
    iosMessage: release.ios.message,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await getFirestore().doc(RELEASE_DOCUMENT).set(data, { merge: true });
  return { ok: true, ...publicRelease(data) };
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
  validBuild,
  validStoreUrl,
};
