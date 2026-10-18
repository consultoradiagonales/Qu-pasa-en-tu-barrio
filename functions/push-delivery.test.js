'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { deliverToUsers } = require('./push-delivery');
const { FakeDb, fakeMessaging } = require('./test-helpers/fake-firestore');

const OPTS = { key: 'k1', type: 'municipality_message', title: 'Titulo', body: 'Cuerpo', data: { reportId: 42 } };

function notificationCount(db) {
  return [...db.data.keys()].filter((k) => k.startsWith('notifications/')).length;
}

test('usuario con token: se crea el aviso y queda delivery push', async () => {
  const db = new FakeDb({ 'users/u1': { fcmToken: 'tok1' } });
  const messaging = fakeMessaging();
  const result = await deliverToUsers(db, [{ uid: 'u1', fcmToken: 'tok1' }], OPTS, messaging);
  assert.deepEqual(result, { total: 1, pushed: 1, inApp: 0 });
  const doc = db.get('notifications/k1_u1');
  assert.equal(doc.delivery, 'push');
  assert.equal(doc.userId, 'u1');
  assert.equal(doc.read, false);
  assert.ok(doc.pushSentAt);
  const msg = messaging.impl.calls[0][0];
  assert.equal(msg.token, 'tok1');
  assert.equal(msg.data.notificationId, 'k1_u1');
  assert.equal(msg.data.reportId, '42'); // todo el data va como string
  assert.equal(msg.data.type, 'municipality_message');
});

test('idempotencia: segundo envio con el mismo key no duplica ni reenvia', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging();
  const users = [{ uid: 'u1', fcmToken: 'tok1' }, { uid: 'u2' }];
  const first = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(first, { total: 2, pushed: 1, inApp: 1 });
  const second = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(second, { total: 2, pushed: 0, inApp: 0 });
  assert.equal(messaging.impl.calls.length, 1);
  assert.equal(notificationCount(db), 2);
  // otro key sí genera avisos nuevos
  const third = await deliverToUsers(db, users, { ...OPTS, key: 'k2' }, messaging);
  assert.equal(third.pushed, 1);
});

test('usuarios sin token (ausente, vacio o no-string) quedan in_app sin llamar a FCM', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging();
  const users = [{ uid: 'a' }, { uid: 'b', fcmToken: '' }, { uid: 'c', fcmToken: 123 }, { uid: 'd', fcmToken: null }];
  const result = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(result, { total: 4, pushed: 0, inApp: 4 });
  assert.equal(messaging.impl.calls.length, 0);
  for (const uid of ['a', 'b', 'c', 'd']) assert.equal(db.get(`notifications/k1_${uid}`).delivery, 'in_app');
});

test('lista vacia no hace nada', async () => {
  const messaging = fakeMessaging();
  const result = await deliverToUsers(new FakeDb(), [], OPTS, messaging);
  assert.deepEqual(result, { total: 0, pushed: 0, inApp: 0 });
  assert.equal(messaging.impl.calls.length, 0);
});

test('token invalido: se limpia el token del usuario y el aviso queda in_app', async () => {
  const db = new FakeDb({ 'users/u1': { fcmToken: 'bad', role: 'citizen' }, 'users/u2': { fcmToken: 'bad2' } });
  const messaging = fakeMessaging((msgs) => ({
    responses: msgs.map((m) => ({
      success: false,
      error: { code: m.token === 'bad' ? 'messaging/registration-token-not-registered' : 'messaging/invalid-registration-token' },
    })),
  }));
  const result = await deliverToUsers(db, [{ uid: 'u1', fcmToken: 'bad' }, { uid: 'u2', fcmToken: 'bad2' }], OPTS, messaging);
  assert.deepEqual(result, { total: 2, pushed: 0, inApp: 2 });
  for (const uid of ['u1', 'u2']) {
    const n = db.get(`notifications/k1_${uid}`);
    assert.equal(n.delivery, 'in_app');
    assert.equal(n.pushError, 'invalid_token');
    assert.notEqual(typeof db.get(`users/${uid}`).fcmToken, 'string'); // sentinel de borrado
  }
  assert.equal(db.get('users/u1').role, 'citizen');
});

test('token invalido de un usuario inexistente no rompe la entrega', async () => {
  const db = new FakeDb(); // users/u1 no existe: update() falla y se ignora
  const messaging = fakeMessaging((msgs) => ({ responses: msgs.map(() => ({ success: false, error: { code: 'messaging/invalid-registration-token' } })) }));
  const result = await deliverToUsers(db, [{ uid: 'u1', fcmToken: 'x' }], OPTS, messaging);
  assert.equal(result.inApp, 1);
});

test('respuesta parcial de sendEach: exito, token invalido y error transitorio', async () => {
  const db = new FakeDb({ 'users/a': { fcmToken: 'ta' }, 'users/b': { fcmToken: 'tb' }, 'users/c': { fcmToken: 'tc' } });
  const messaging = fakeMessaging(() => ({
    responses: [
      { success: true },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
      { success: false, error: { code: 'messaging/internal-error' } },
    ],
  }));
  const users = [{ uid: 'a', fcmToken: 'ta' }, { uid: 'b', fcmToken: 'tb' }, { uid: 'c', fcmToken: 'tc' }];
  const result = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(result, { total: 3, pushed: 1, inApp: 2 });
  assert.equal(db.get('notifications/k1_a').delivery, 'push');
  assert.equal(db.get('notifications/k1_b').pushError, 'invalid_token');
  assert.equal(db.get('notifications/k1_c').pushError, 'unavailable');
  assert.equal(db.get('users/a').fcmToken, 'ta');
  assert.notEqual(typeof db.get('users/b').fcmToken, 'string');
  assert.equal(db.get('users/c').fcmToken, 'tc'); // error transitorio: el token se conserva
});

test('mezcla con y sin token en el mismo lote', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging();
  const users = [{ uid: 'a', fcmToken: 'ta' }, { uid: 'b' }, { uid: 'c', fcmToken: 'tc' }];
  const result = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(result, { total: 3, pushed: 2, inApp: 1 });
  assert.equal(messaging.impl.calls[0].length, 2);
});

test('lote mayor a 500: se envia en varias llamadas de a 500 como maximo', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging();
  const users = Array.from({ length: 1203 }, (_, i) => ({ uid: `u${i}`, fcmToken: `t${i}` }));
  const result = await deliverToUsers(db, users, OPTS, messaging);
  assert.deepEqual(result, { total: 1203, pushed: 1203, inApp: 0 });
  assert.deepEqual(messaging.impl.calls.map((c) => c.length), [500, 500, 203]);
  assert.equal(notificationCount(db), 1203);
});

test('falla total de sendEach: nada queda pending, todo in_app', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging(() => { throw new Error('FCM caido'); });
  const result = await deliverToUsers(db, [{ uid: 'a', fcmToken: 'ta' }, { uid: 'b' }], OPTS, messaging);
  assert.deepEqual(result, { total: 2, pushed: 0, inApp: 2 });
  assert.equal(db.get('notifications/k1_a').delivery, 'in_app');
  assert.equal(db.get('notifications/k1_a').pushError, 'unavailable');
  assert.equal(db.get('notifications/k1_b').delivery, 'in_app');
});

test('error inesperado al crear un aviso: se propaga pero los demas usuarios se procesan', async () => {
  const db = new FakeDb();
  db.failCreateFor.add('k1_bad');
  const messaging = fakeMessaging();
  await assert.rejects(
    deliverToUsers(db, [{ uid: 'bad', fcmToken: 'x' }, { uid: 'ok', fcmToken: 'y' }], OPTS, messaging),
    (e) => e.code === 'unavailable',
  );
  assert.equal(db.get('notifications/k1_ok').delivery, 'push');
  assert.equal(db.get('notifications/k1_bad'), undefined);
});

test('uid duplicado en la lista no duplica el aviso', async () => {
  const db = new FakeDb();
  const messaging = fakeMessaging();
  const result = await deliverToUsers(db, [{ uid: 'a', fcmToken: 't' }, { uid: 'a', fcmToken: 't' }], OPTS, messaging);
  assert.equal(result.pushed, 1);
  assert.equal(messaging.impl.calls[0].length, 1);
});
