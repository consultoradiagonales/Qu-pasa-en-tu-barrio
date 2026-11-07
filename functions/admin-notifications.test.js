'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  cleanMessage,
  validId,
  evidenceFor,
  canManage,
} = require('./admin-notifications');

test('manual notification text is bounded and does not preserve links', () => {
  assert.equal(cleanMessage('  Novedad\nhttps://example.test/a  '), 'Novedad [enlace omitido]');
  assert.equal(cleanMessage('x'.repeat(4000)).length, 4000);
  assert.equal(cleanMessage('x'.repeat(4001)).length, 4000);
});

test('request ids require a safe opaque token', () => {
  assert.equal(validId('9b625ccb6d2e4e0d97812479'), true);
  assert.equal(validId('short'), false);
  assert.equal(validId('token/with/slash000'), false);
});

test('manual update only attaches trusted crew evidence', () => {
  assert.equal(evidenceFor({ photosProgress: ['https://storage.example/progress.jpg'] }), 'https://storage.example/progress.jpg');
  assert.equal(evidenceFor({ photosAfter: ['javascript:alert(1)'], photosProgress: [] }), null);
  assert.equal(evidenceFor({ photosAfter: ['https://storage.example/final.jpg'], photosProgress: ['https://storage.example/progress.jpg'] }), 'https://storage.example/final.jpg');
});

test('only enabled municipal staff can manage a report', () => {
  const report = { municipalityId: 'm1' };
  assert.equal(canManage({ role: 'coordinator', municipalityId: 'm1', disabled: false }, report), true);
  assert.equal(canManage({ role: 'coordinator', municipalityId: 'm2', disabled: false }, report), false);
  assert.equal(canManage({ role: 'admin', organizationId: 'diagonales', municipalityId: '', disabled: false }, report), true);
  assert.equal(canManage({ role: 'admin', municipalityId: 'm2', disabled: false }, report), false);
  assert.equal(canManage({ role: 'admin', municipalityId: 'm1', disabled: false }, report), true);
  assert.equal(canManage({ role: 'admin', municipalityId: 'm1', disabled: true }, report), false);
});
