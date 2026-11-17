'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { state, FakeDb } = require('./test-helpers/stub-firebase');
const {
  ANDROID_PLAY_URL, DEFAULT_RELEASE, getAppReleaseHandler, saveAppReleaseHandler, validStoreUrl,
} = require('./app-release');

// FakeDb del proyecto no tiene db.doc(path); se agrega sin tocar el helper.
function makeDb(seed) {
  const db = new FakeDb(seed);
  db.doc = (p) => { const [c, id] = p.split('/'); return db.collection(c).doc(id); };
  return db;
}

const IOS_URL = 'https://apps.apple.com/ar/app/condi/id123456789';
const STORED = {
  minAndroidBuild: 35, androidStoreUrl: ANDROID_PLAY_URL, androidMessage: 'Android anterior',
  minIosBuild: 40, iosStoreUrl: IOS_URL, iosMessage: 'iOS vigente',
};
const USERS = {
  'users/admin': { role: 'admin', organizationId: 'diagonales' },
  'users/localAdmin': { role: 'admin', organizationId: 'muni', municipalityId: '06001' },
  'users/offAdmin': { role: 'admin', organizationId: 'diagonales', disabled: true },
  'users/gm': { role: 'field_manager', organizationId: 'diagonales' },
  'users/citizen': { role: 'citizen' },
};
const seed = () => ({ ...USERS, 'appConfiguration/mobileRelease': { ...STORED } });

test('getAppRelease público: sin documento devuelve los valores por defecto', async () => {
  state.db = makeDb({});
  const r = await getAppReleaseHandler();
  assert.equal(r.android.minBuild, DEFAULT_RELEASE.minAndroidBuild);
  assert.equal(r.android.storeUrl, ANDROID_PLAY_URL);
  assert.equal(r.ios.storeUrl, '');
});

test('getAppRelease sanea un documento manipulado: Play ajeno vuelve al oficial, iOS fuera de apps.apple.com se descarta', async () => {
  state.db = makeDb({ 'appConfiguration/mobileRelease': {
    minAndroidBuild: 20, androidStoreUrl: 'https://play.google.com/store/apps/details?id=malicioso.app',
    iosStoreUrl: 'https://evil.example/ios', minIosBuild: 'x',
  } });
  const r = await getAppReleaseHandler();
  assert.equal(r.android.storeUrl, ANDROID_PLAY_URL);
  assert.equal(r.ios.storeUrl, '');
  assert.equal(r.ios.minBuild, 0);
});

for (const [uid, code] of [
  [null, 'unauthenticated'], ['localAdmin', 'permission-denied'], ['offAdmin', 'permission-denied'],
  ['gm', 'permission-denied'], ['citizen', 'permission-denied'], ['ghost', 'permission-denied'],
]) {
  test(`saveAppRelease deniega a ${uid ?? 'anónimo'} sin escribir`, async () => {
    const db = makeDb(seed());
    await assert.rejects(saveAppReleaseHandler({ auth: uid ? { uid } : undefined, data: { minAndroidBuild: 99 } }, { db }), { code });
    assert.deepEqual(db.get('appConfiguration/mobileRelease'), STORED);
  });
}

test('saveAppRelease: un enlace Play de otro paquete se reemplaza por la ficha oficial de ConDi', async () => {
  const db = makeDb(seed());
  const r = await saveAppReleaseHandler({ auth: { uid: 'admin' }, data: {
    minAndroidBuild: 36, androidStoreUrl: 'https://play.google.com/store/apps/details?id=otra.app', androidMessage: 'Nuevo',
  } }, { db });
  assert.equal(r.android.storeUrl, ANDROID_PLAY_URL);
  assert.equal(db.get('appConfiguration/mobileRelease').androidStoreUrl, ANDROID_PLAY_URL);
  for (const bad of [
    'http://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi',
    'https://play.google.com.evil.example/store/apps/details?id=ar.com.consultoradiagonales.condi',
    'https://evil.example/?u=https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi',
  ]) assert.equal(validStoreUrl(bad, 'android'), '', bad);
});

test('saveAppRelease conserva la configuración iOS si no se envía', async () => {
  const db = makeDb(seed());
  const r = await saveAppReleaseHandler({ auth: { uid: 'admin' }, data: {
    minAndroidBuild: 36, androidStoreUrl: ANDROID_PLAY_URL, androidMessage: 'Nuevo',
  } }, { db });
  assert.deepEqual(r.ios, { minBuild: 40, storeUrl: IOS_URL, message: 'iOS vigente' });
});

test('saveAppRelease: guardar sólo iOS conserva la configuración Android existente', async () => {
  const db = makeDb(seed());
  const r = await saveAppReleaseHandler({ auth: { uid: 'admin' }, data: { minIosBuild: 41 } }, { db });
  assert.equal(r.ios.minBuild, 41);
  assert.equal(r.android.minBuild, 35, 'no baja el mínimo Android al default');
  assert.equal(r.android.message, 'Android anterior');
});

test('saveAppRelease: un mínimo de compilación inválido se rechaza sin escribir', async () => {
  for (const bad of [{ minIosBuild: 'abc' }, { minIosBuild: -1 }, { minIosBuild: 1.5 }, { minAndroidBuild: '' },
    { minAndroidBuild: null }, { minAndroidBuild: 2147483648 }]) {
    const db = makeDb(seed());
    await assert.rejects(saveAppReleaseHandler({ auth: { uid: 'admin' }, data: {
      androidMessage: 'Nuevo', ...bad,
    } }, { db }), { code: 'invalid-argument' }, JSON.stringify(bad));
    assert.deepEqual(db.get('appConfiguration/mobileRelease'), STORED);
  }
});

test('saveAppRelease: guardar sólo iOS escribe únicamente campos iOS', async () => {
  const db = makeDb(seed());
  await saveAppReleaseHandler({ auth: { uid: 'admin' }, data: { minIosBuild: 41, iosMessage: 'iOS nuevo' } }, { db });
  const stored = db.get('appConfiguration/mobileRelease');
  assert.equal(stored.minAndroidBuild, 35);
  assert.equal(stored.androidMessage, 'Android anterior');
  assert.equal(stored.minIosBuild, 41);
  assert.equal(stored.iosMessage, 'iOS nuevo');
  assert.equal(stored.iosStoreUrl, IOS_URL);
});

test('saveAppRelease: una solicitud sin campos de versión se rechaza', async () => {
  const db = makeDb(seed());
  await assert.rejects(saveAppReleaseHandler({ auth: { uid: 'admin' }, data: {} }, { db }), { code: 'invalid-argument' });
  assert.deepEqual(db.get('appConfiguration/mobileRelease'), STORED);
});
