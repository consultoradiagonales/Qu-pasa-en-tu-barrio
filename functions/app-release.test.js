'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { ANDROID_PLAY_URL, DEFAULT_RELEASE, publicRelease, saveAppReleaseHandler, validStoreUrl } = require('./app-release');

test('la publicación usa un mínimo Android y un enlace oficial de Play', () => {
  const release = publicRelease({ minAndroidBuild: 19, androidStoreUrl: ANDROID_PLAY_URL });
  assert.equal(release.android.minBuild, 19);
  assert.equal(release.android.storeUrl, ANDROID_PLAY_URL);
});

test('rechaza enlaces externos y vuelve al enlace oficial de Play', () => {
  assert.equal(validStoreUrl('https://example.com/update', 'android'), '');
  const release = publicRelease({ androidStoreUrl: 'https://example.com/update' });
  assert.equal(release.android.storeUrl, DEFAULT_RELEASE.androidStoreUrl);
});

test('sólo acepta la ficha de ConDi en Google Play', () => {
  assert.equal(validStoreUrl('https://play.google.com/store/apps/details?id=otra.app', 'android'), '');
  assert.equal(validStoreUrl('https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi&id=otra.app', 'android'), '');
  assert.equal(validStoreUrl('https://play.google.com/store/apps/search?id=ar.com.consultoradiagonales.condi', 'android'), '');
  assert.equal(validStoreUrl(`${ANDROID_PLAY_URL}&hl=es_AR`, 'android'), ANDROID_PLAY_URL);
});

test('guardar Android conserva el mínimo, enlace y mensaje iOS existentes', async () => {
  const stored = {
    minAndroidBuild: 35,
    androidStoreUrl: ANDROID_PLAY_URL,
    androidMessage: 'Android anterior',
    minIosBuild: 40,
    iosStoreUrl: 'https://apps.apple.com/ar/app/condi/id123456789',
    iosMessage: 'iOS vigente',
  };
  const db = {
    collection(name) {
      assert.equal(name, 'users');
      return { doc(uid) {
        assert.equal(uid, 'admin');
        return { async get() { return { exists: true, data: () => ({ role: 'admin', organizationId: 'diagonales', disabled: false }) }; } };
      } };
    },
    doc(path) {
      assert.equal(path, 'appConfiguration/mobileRelease');
      return {
        async get() { return { exists: true, data: () => ({ ...stored }) }; },
        async set(data, options) {
          assert.deepEqual(options, { merge: true });
          assert.equal(Object.hasOwn(data, 'minIosBuild'), false);
          assert.equal(Object.hasOwn(data, 'iosStoreUrl'), false);
          assert.equal(Object.hasOwn(data, 'iosMessage'), false);
          Object.assign(stored, data);
        },
      };
    },
  };
  const result = await saveAppReleaseHandler({
    auth: { uid: 'admin' },
    data: { minAndroidBuild: 36, androidStoreUrl: ANDROID_PLAY_URL, androidMessage: 'Android nuevo' },
  }, { db });
  assert.equal(result.android.minBuild, 36);
  assert.deepEqual(result.ios, {
    minBuild: 40,
    storeUrl: 'https://apps.apple.com/ar/app/condi/id123456789',
    message: 'iOS vigente',
  });
  assert.equal(stored.minIosBuild, 40);
  assert.equal(stored.iosStoreUrl, 'https://apps.apple.com/ar/app/condi/id123456789');
  assert.equal(stored.iosMessage, 'iOS vigente');
});

test('no permite mínimos de versión inválidos ni texto sin sanear', () => {
  const release = publicRelease({ minAndroidBuild: -2, androidMessage: 'Actualizá\u0000 ahora' });
  assert.equal(release.android.minBuild, DEFAULT_RELEASE.minAndroidBuild);
  assert.equal(release.android.message, 'Actualizá ahora');
});
