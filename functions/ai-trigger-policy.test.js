'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { shouldInterpret } = require('./ai-trigger-policy');

test('IA espera la evidencia y se activa una sola vez al quedar lista', () => {
  const pending = { userId: 'u', aiRequested: true, aiConsentVersion: 1,
    hidden: false, photoUploadStatus: 'pending', photosReport: [] };
  const ready = { ...pending, photoUploadStatus: 'ready',
    photosReport: ['https://example.test/photo.jpg'] };
  assert.equal(shouldInterpret(null, pending), false);
  assert.equal(shouldInterpret(pending, ready), true);
  assert.equal(shouldInterpret(ready, { ...ready, priority: 2 }), false);
  assert.equal(shouldInterpret(null, { ...ready, photoUploadStatus: undefined }), true);
});
