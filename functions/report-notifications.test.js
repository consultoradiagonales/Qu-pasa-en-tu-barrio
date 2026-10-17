'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { notificationForChange, isInvalidToken } = require('./report-notifications');

test('notifica la resolución con la foto final', () => {
  const result = notificationForChange(
    { status: 'in_progress', photosAfter: [] },
    { userId: 'u', status: 'resolved', photosAfter: ['https://img/final.jpg'] },
  );
  assert.equal(result.type, 'report_resolved');
  assert.equal(result.imageUrl, 'https://img/final.jpg');
});

test('no vuelve a notificar una resolución sin cambios', () => {
  const result = notificationForChange(
    { status: 'resolved', photosAfter: ['https://img/final.jpg'] },
    { userId: 'u', status: 'resolved', photosAfter: ['https://img/final.jpg'] },
  );
  assert.equal(result, null);
});

test('notifica el progreso nuevo sin exponer texto del reporte', () => {
  const result = notificationForChange(
    { status: 'in_progress', photosProgress: [] },
    { userId: 'u', status: 'in_progress', photosProgress: ['https://img/progreso.jpg'] },
  );
  assert.equal(result.type, 'report_progress');
  assert.equal(result.body, 'La cuadrilla cargó una actualización del trabajo.');
});

test('reconoce tokens FCM inválidos', () => {
  assert.equal(isInvalidToken({ code: 'messaging/registration-token-not-registered' }), true);
  assert.equal(isInvalidToken({ code: 'network-error' }), false);
});
