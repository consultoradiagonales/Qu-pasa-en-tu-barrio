'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { ANDROID_PLAY_URL, DEFAULT_RELEASE, publicRelease, validStoreUrl } = require('./app-release');

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

test('no permite mínimos de versión inválidos ni texto sin sanear', () => {
  const release = publicRelease({ minAndroidBuild: -2, androidMessage: 'Actualizá\u0000 ahora' });
  assert.equal(release.android.minBuild, DEFAULT_RELEASE.minAndroidBuild);
  assert.equal(release.android.message, 'Actualizá ahora');
});
