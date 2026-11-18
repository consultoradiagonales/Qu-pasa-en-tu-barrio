'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  sendWeatherAlertHandler,
  correctWeatherAlertHandler,
  deliveryKeysFor,
} = require('./weather-admin');
const { FakeDb, fakeMessaging } = require('./test-helpers/fake-firestore');

const MUNI = 'georef_060441';
const OTHER = 'georef_060357';
const NOW = new Date('2026-11-06T15:00:00Z');

function seed(extra = {}) {
  return new FakeDb({
    'users/central': { role: 'admin', organizationId: 'diagonales', disabled: false },
    'users/coord': { role: 'coordinator', municipalityId: MUNI, disabled: false },
    'users/mod': { role: 'moderator', municipalityId: MUNI, disabled: false },
    'users/v1': { role: 'citizen', municipalityId: MUNI, disabled: false, fcmToken: 'tok1' },
    'users/v2': { role: 'citizen', municipalityId: MUNI, disabled: false },
    'users/v3': { role: 'citizen', municipalityId: OTHER, disabled: false, fcmToken: 'tok3' },
    [`municipalities/${MUNI}`]: { name: 'La Plata' },
    ...extra,
  });
}

const ALERT = {
  municipalityId: MUNI,
  level: 2,
  hazard: 'tormenta',
  title: 'Alerta naranja por tormentas',
  message: 'Se esperan tormentas fuertes con ráfagas y caída de granizo.',
  onset: Date.parse('2026-11-06T18:00:00Z'),
  expires: Date.parse('2026-11-07T06:00:00Z'),
  requestId: 'req0000000001',
};

test('la coordinación envía una alerta a los vecinos de su municipio', async () => {
  const db = seed();
  const messaging = fakeMessaging();
  const result = await sendWeatherAlertHandler(
    { auth: { uid: 'coord' }, data: ALERT },
    { db, messaging, now: NOW },
  );
  assert.equal(result.total, 2);
  assert.equal(result.pushed, 1);
  assert.equal(result.inApp, 1);
  const stored = db.get(`weatherAlerts/${result.alertId}`);
  assert.equal(stored.source, 'manual');
  assert.equal(stored.status, 'active');
  assert.equal(stored.municipalityName, 'La Plata');
  assert.match(stored.body, /Vigencia estimada/);
  const inbox = db.get('notifications/weather_manual_req0000000001_v1');
  assert.equal(inbox.type, 'weather_alert');
  assert.equal(inbox.alertId, result.alertId);
  assert.equal(db.get('notifications/weather_manual_req0000000001_v3'), undefined);
});

test('no se puede emitir para otro municipio ni con rol moderador', async () => {
  const db = seed();
  await assert.rejects(
    sendWeatherAlertHandler({ auth: { uid: 'coord' }, data: { ...ALERT, municipalityId: OTHER } }, { db, messaging: fakeMessaging() }),
    (error) => error.code === 'permission-denied',
  );
  await assert.rejects(
    sendWeatherAlertHandler({ auth: { uid: 'mod' }, data: ALERT }, { db, messaging: fakeMessaging() }),
    (error) => error.code === 'permission-denied',
  );
  await assert.rejects(
    sendWeatherAlertHandler({ data: ALERT }, { db }),
    (error) => error.code === 'unauthenticated',
  );
});

test('la consultora puede emitir para cualquier municipio y no se duplica', async () => {
  const db = seed();
  const data = { ...ALERT, municipalityId: OTHER };
  const result = await sendWeatherAlertHandler({ auth: { uid: 'central' }, data }, { db, messaging: fakeMessaging(), now: NOW });
  assert.equal(result.total, 1);
  await assert.rejects(
    sendWeatherAlertHandler({ auth: { uid: 'central' }, data }, { db, messaging: fakeMessaging(), now: NOW }),
    (error) => error.code === 'already-exists',
  );
});

test('valida nivel, fenómeno, textos y vigencia', async () => {
  const db = seed();
  const call = (patch) => sendWeatherAlertHandler({ auth: { uid: 'coord' }, data: { ...ALERT, ...patch } }, { db, messaging: fakeMessaging() });
  for (const patch of [{ level: 5 }, { hazard: 'meteorito' }, { title: 'x' }, { message: 'corto' }, { expires: ALERT.onset - 1 }, { onset: 'mañana' }]) {
    await assert.rejects(call(patch), (error) => error.code === 'invalid-argument');
  }
});

test('corregir reescribe la bandeja y puede avisar de nuevo', async () => {
  const db = seed();
  const messaging = fakeMessaging();
  const sent = await sendWeatherAlertHandler({ auth: { uid: 'coord' }, data: ALERT }, { db, messaging, now: NOW });
  const result = await correctWeatherAlertHandler({
    auth: { uid: 'coord' },
    data: {
      ...ALERT,
      alertId: sent.alertId,
      action: 'correct',
      level: 1,
      title: 'Alerta amarilla por tormentas',
      reason: 'bajó la intensidad prevista',
      notify: true,
      requestId: 'fix0000000001',
    },
  }, { db, messaging, now: NOW });
  assert.equal(result.status, 'corrected');
  assert.equal(result.rewritten, 2);
  assert.equal(result.total, 2);
  const stored = db.get(`weatherAlerts/${sent.alertId}`);
  assert.equal(stored.level, 1);
  assert.equal(stored.adminEdited, true);
  assert.equal(stored.history.length, 1);
  assert.equal(stored.history[0].level, 2);
  const inbox = db.get('notifications/weather_manual_req0000000001_v1');
  assert.equal(inbox.title, 'Corregida: Alerta amarilla por tormentas');
  assert.match(inbox.body, /bajó la intensidad/);
  assert.ok(db.get('notifications/weatherfix_fix0000000001_v2'));

  // Reintentar la misma corrección no hace nada.
  const again = await correctWeatherAlertHandler({
    auth: { uid: 'coord' },
    data: { ...ALERT, alertId: sent.alertId, action: 'correct', requestId: 'fix0000000001' },
  }, { db, messaging });
  assert.equal(again.duplicate, true);
});

test('dejar sin efecto una alerta automática sin notificar de nuevo', async () => {
  const alertId = `${MUNI}_2026-11-06_smn_tormentas_1`;
  const db = seed({
    [`weatherAlerts/${alertId}`]: {
      municipalityId: MUNI,
      municipalityName: 'La Plata',
      title: 'SMN: Tormentas en La Plata',
      body: 'Ciudad: La Plata.',
      level: 1,
      versionKey: 'abc123',
    },
    [`notifications/weather_${alertId}_abc123_v1`]: { userId: 'v1', title: 'SMN: Tormentas en La Plata', body: 'x', read: true },
    [`notifications/weather_${alertId}_v2`]: { userId: 'v2', title: 'SMN: Tormentas en La Plata', body: 'x', read: false },
  });
  const messaging = fakeMessaging();
  const result = await correctWeatherAlertHandler({
    auth: { uid: 'central' },
    data: { alertId, action: 'cancel', reason: 'el SMN levantó el aviso', notify: false, requestId: 'cancel0000001' },
  }, { db, messaging });
  assert.equal(result.status, 'cancelled');
  assert.equal(result.rewritten, 2);
  assert.equal(result.total, 0);
  assert.equal(messaging.impl.calls.length, 0);
  assert.match(db.get(`notifications/weather_${alertId}_v2`).title, /^Sin efecto:/);
  assert.equal(db.get(`notifications/weather_${alertId}_abc123_v1`).read, true);
  await assert.rejects(
    correctWeatherAlertHandler({
      auth: { uid: 'central' },
      data: { alertId, action: 'cancel', requestId: 'cancel0000002' },
    }, { db, messaging }),
    (error) => error.code === 'failed-precondition',
  );
});

test('claves de entrega incluyen la versionada y la histórica', () => {
  assert.deepEqual(deliveryKeysFor('m_d_rain_1', { versionKey: 'daily' }), ['weather_m_d_rain_1_daily', 'weather_m_d_rain_1']);
  assert.deepEqual(deliveryKeysFor('x', { deliveryKey: 'weather_manual_r', versionKey: 'manual' })[0], 'weather_manual_r');
});
