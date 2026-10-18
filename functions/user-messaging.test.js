'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  saveDeviceProfileHandler,
  deleteDeviceProfileHandler,
  sendCustomMessageHandler,
  cleanText,
  CONSENT_VERSION,
} = require('./user-messaging');
const { FakeDb, fakeMessaging } = require('./test-helpers/fake-firestore');

const REQ_ID = 'req-abcdefghij12';

test('sin consentimiento no se guarda el perfil del dispositivo', async () => {
  await assert.rejects(
    saveDeviceProfileHandler({ auth: { uid: 'u1', token: {} }, data: { consent: false } }),
    (error) => error.code === 'failed-precondition',
  );
  await assert.rejects(
    saveDeviceProfileHandler({ data: { consent: true } }),
    (error) => error.code === 'unauthenticated',
  );
});

test('enviar mensajes exige sesion iniciada', async () => {
  await assert.rejects(
    sendCustomMessageHandler({ data: {} }),
    (error) => error.code === 'unauthenticated',
  );
});

test('cleanText quita enlaces y caracteres de control', () => {
  assert.equal(cleanText('Hola\n https://x.com/a  mundo', 50), 'Hola [enlace omitido] mundo');
  assert.equal(cleanText(5, 10), '');
  assert.equal(cleanText('abcdef', 3), 'abc');
});

// ---- saveDeviceProfile / deleteDeviceProfile ----

test('consentimiento invalido (string, 1, undefined) se rechaza sin escribir', async () => {
  for (const consent of ['true', 1, undefined, null]) {
    const db = new FakeDb();
    await assert.rejects(
      saveDeviceProfileHandler({ auth: { uid: 'u1' }, data: { consent } }, { db }),
      (e) => e.code === 'failed-precondition',
    );
    assert.equal(db.get('userDevices/u1'), undefined);
  }
});

test('con consentimiento guarda solo los campos esperados y no confia en el cliente', async () => {
  const db = new FakeDb();
  const res = await saveDeviceProfileHandler({
    auth: { uid: 'real-uid' },
    rawRequest: { ip: '9.9.9.9' },
    data: {
      consent: true,
      uid: 'otro-uid',
      account: { email: 'x@y.com' },
      ip: '1.2.3.4',
      location: { lat: 1, lng: 2 },
      phone: '+54911',
      device: { model: 'X' },
      network: { ssid: 'wifi' },
      extra: 'zzz',
    },
  }, { db });
  assert.deepEqual(res, { ok: true, consentVersion: CONSENT_VERSION });
  assert.equal(db.get('userDevices/otro-uid'), undefined);
  const doc = db.get('userDevices/real-uid');
  assert.deepEqual(Object.keys(doc).sort(), ['account', 'consent', 'device', 'location', 'network', 'phone', 'updatedAt', 'usageAnalytics']);
  assert.equal(doc.consent.given, true);
  assert.equal(doc.consent.version, CONSENT_VERSION);
  assert.deepEqual(
    { ...doc.usageAnalytics },
    { enabled: true, source: 'profile_territory', rawIpStored: false, exactLocationStored: false },
  );
  // los campos invasivos son sentinels de borrado, nunca datos del cliente
  for (const field of ['account', 'device', 'network', 'location', 'phone']) {
    assert.equal(typeof doc[field], 'object');
    assert.notDeepEqual(doc[field], { email: 'x@y.com' });
    assert.ok(!JSON.stringify(doc[field]).includes('1.2.3.4'));
  }
  assert.ok(!JSON.stringify(doc).includes('x@y.com'));
  assert.ok(!JSON.stringify(doc).includes('9.9.9.9'));
});

test('deleteDeviceProfile borra el documento propio y exige sesion', async () => {
  const db = new FakeDb({ 'userDevices/u1': { consent: {} }, 'userDevices/u2': { consent: {} } });
  await assert.rejects(deleteDeviceProfileHandler({ data: {} }, { db }), (e) => e.code === 'unauthenticated');
  assert.deepEqual(await deleteDeviceProfileHandler({ auth: { uid: 'u1' }, data: { uid: 'u2' } }, { db }), { ok: true });
  assert.equal(db.get('userDevices/u1'), undefined);
  assert.ok(db.get('userDevices/u2'));
});

// ---- sendCustomMessage ----

function world(extra = {}) {
  return new FakeDb({
    'users/admin1': { role: 'admin', disabled: false, municipalityId: 'm1', fcmToken: 'tAdmin' },
    'users/coord1': { role: 'coordinator', disabled: false, municipalityId: 'm1', fcmToken: 'tCoord' },
    'users/mod2': { role: 'moderator', disabled: false, municipalityId: 'm2' },
    'users/cit1': { role: 'citizen', disabled: false, municipalityId: 'm1', fcmToken: 'tCit1' },
    'users/cit2': { role: 'citizen', disabled: false, municipalityId: 'm1' },
    'users/cit3': { role: 'citizen', disabled: false, municipalityId: 'm2', fcmToken: 'tCit3' },
    'users/citOff': { role: 'citizen', disabled: true, municipalityId: 'm1', fcmToken: 'tOff' },
    'users/disabledStaff': { role: 'moderator', disabled: true, municipalityId: 'm1' },
    'users/plain': { role: 'citizen', disabled: false, municipalityId: 'm1' },
    ...extra,
  });
}

function call(uid, data, db, messaging = fakeMessaging()) {
  return sendCustomMessageHandler(
    { auth: { uid }, data: { title: 'Aviso', body: 'Mensaje de prueba', requestId: REQ_ID, ...data } },
    { db, messaging },
  );
}

function notified(db) {
  return [...db.data.keys()].filter((k) => k.startsWith('notifications/')).map((k) => k.split('_').slice(2).join('_')).sort();
}

test('rechaza a ciudadanos, usuarios inexistentes y personal deshabilitado', async () => {
  const db = world();
  for (const uid of ['cit1', 'nobody', 'disabledStaff']) {
    await assert.rejects(call(uid, { audience: { type: 'all' } }, db), (e) => e.code === 'permission-denied');
  }
  assert.deepEqual(notified(db), []);
});

test('validaciones: titulo/mensaje cortos y requestId invalido', async () => {
  const db = world();
  const aud = { audience: { type: 'municipality' } };
  await assert.rejects(call('coord1', { ...aud, title: 'ab' }, db), (e) => e.code === 'invalid-argument');
  await assert.rejects(call('coord1', { ...aud, body: '  x ' }, db), (e) => e.code === 'invalid-argument');
  await assert.rejects(call('coord1', { ...aud, title: 5 }, db), (e) => e.code === 'invalid-argument');
  for (const requestId of [undefined, 'corto', 'tiene espacios aqui', 'a/b/c/d/e/f/g/h/i', 'x'.repeat(81), 12345678901234]) {
    await assert.rejects(call('coord1', { ...aud, requestId }, db), (e) => e.code === 'invalid-argument');
  }
  await assert.rejects(call('coord1', { audience: { type: 'otra' } }, db), (e) => e.code === 'invalid-argument');
  await assert.rejects(call('coord1', { audience: undefined }, db), (e) => e.code === 'invalid-argument');
  assert.deepEqual(notified(db), []);
});

test('coordinador no puede enviar a todos', async () => {
  const db = world();
  await assert.rejects(call('coord1', { audience: { type: 'all' } }, db), (e) => e.code === 'permission-denied');
  assert.deepEqual(notified(db), []);
});

test('coordinador no puede escribir a otro municipio pero si al propio', async () => {
  const db = world();
  await assert.rejects(
    call('coord1', { audience: { type: 'municipality', municipalityId: 'm2' } }, db),
    (e) => e.code === 'permission-denied',
  );
  const own = await call('coord1', { audience: { type: 'municipality', municipalityId: 'm1' } }, db);
  assert.equal(own.total, 3); // cit1, cit2, plain (no staff, no disabled)
  assert.deepEqual(notified(db), ['cit1', 'cit2', 'plain']);
});

test('municipio sin municipalityId usa el propio; sin municipio asignado falla', async () => {
  const db = world({ 'users/coordNone': { role: 'coordinator', disabled: false } });
  const res = await call('coord1', { audience: { type: 'municipality' } }, db);
  assert.equal(res.total, 3);
  await assert.rejects(
    call('coordNone', { audience: { type: 'municipality' } }, db),
    (e) => e.code === 'failed-precondition',
  );
});

test('administrador puede elegir cualquier municipio', async () => {
  const db = world();
  const res = await call('admin1', { audience: { type: 'municipality', municipalityId: 'm2' } }, db);
  assert.equal(res.total, 1);
  assert.deepEqual(notified(db), ['cit3']);
});

test('"all" por admin incluye a cualquier rol activo y excluye a los deshabilitados', async () => {
  const db = world();
  const messaging = fakeMessaging();
  const res = await call('admin1', { audience: { type: 'all' } }, db, messaging);
  assert.deepEqual(notified(db), ['admin1', 'cit1', 'cit2', 'cit3', 'coord1', 'mod2', 'plain']);
  assert.equal(res.ok, true);
  assert.equal(res.total, 7);
  assert.equal(res.pushed, 4); // admin1, coord1, cit1, cit3 tienen token
  assert.equal(res.inApp, 3);
  const tokens = messaging.impl.calls.flat().map((m) => m.token).sort();
  assert.ok(!tokens.includes('tOff'));
});

test('usuario puntual: staff solo a su municipio, admin a cualquiera, deshabilitado/inexistente no', async () => {
  const db = world();
  await assert.rejects(call('coord1', { audience: { type: 'user', uid: 'cit3' } }, db), (e) => e.code === 'permission-denied');
  const ok = await call('coord1', { audience: { type: 'user', uid: 'cit1' } }, db);
  assert.deepEqual({ total: ok.total, pushed: ok.pushed }, { total: 1, pushed: 1 });
  const adm = await call('admin1', { audience: { type: 'user', uid: 'cit3' } }, db);
  assert.equal(adm.total, 1);
  await assert.rejects(call('admin1', { audience: { type: 'user', uid: 'nadie' } }, db), (e) => e.code === 'not-found');
  await assert.rejects(call('admin1', { audience: { type: 'user', uid: 'citOff' } }, db), (e) => e.code === 'not-found');
  for (const uid of [undefined, '', 'a/b', 5]) {
    await assert.rejects(call('admin1', { audience: { type: 'user', uid } }, db), (e) => e.code === 'invalid-argument');
  }
});

test('idempotencia por requestId: reenviar la misma solicitud no duplica', async () => {
  const db = world();
  const messaging = fakeMessaging();
  const first = await call('admin1', { audience: { type: 'all' } }, db, messaging);
  const second = await call('admin1', { audience: { type: 'all' } }, db, messaging);
  assert.equal(first.pushed, 4);
  assert.deepEqual({ pushed: second.pushed, inApp: second.inApp }, { pushed: 0, inApp: 0 });
  assert.equal(messaging.impl.calls.flat().length, 4);
  // un requestId distinto es un mensaje nuevo
  const third = await call('admin1', { audience: { type: 'all' }, requestId: 'req-otrodistinto1' }, db, messaging);
  assert.equal(third.pushed, 4);
});

test('audiencia vacia devuelve total 0 sin tocar FCM; titulo y cuerpo se sanean', async () => {
  const db = world();
  const messaging = fakeMessaging();
  const res = await call('admin1', { audience: { type: 'municipality', municipalityId: 'm-vacio' } }, db, messaging);
  assert.deepEqual(res, { ok: true, total: 0, pushed: 0, inApp: 0 });
  assert.equal(messaging.impl.calls.length, 0);

  await call('coord1', { audience: { type: 'user', uid: 'cit1' }, title: 'Hola https://malo.com', body: 'Ver\nhttp://x.y ya' }, db, messaging);
  const doc = db.get(`notifications/custom_${REQ_ID}_cit1`);
  assert.equal(doc.title, 'Hola [enlace omitido]');
  assert.equal(doc.body, 'Ver [enlace omitido] ya');
  assert.equal(doc.type, 'municipality_message');
});
