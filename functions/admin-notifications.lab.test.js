'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { state, makeMessaging, FakeDb } = require('./test-helpers/stub-firebase');
const { sendReportUpdateHandler } = require('./admin-notifications');

const REPORT_ID = 'rep-field-01';
const REQUEST_ID = 'req0123456789abcdef';

function seed(reportOverrides = {}, extraUsers = {}) {
  return {
    [`reports/${REPORT_ID}`]: {
      municipalityId: 'georef_06001', assignedTeamId: 'team-a', status: 'in_progress',
      userId: 'owner', photosProgress: ['https://storage.example/progress.jpg'], ...reportOverrides,
    },
    'users/owner': { role: 'citizen', fcmToken: 'tok-owner' },
    'users/worker': { role: 'field_worker', teamId: 'team-a', municipalityId: '06001' },
    'users/otherTeam': { role: 'field_worker', teamId: 'team-b', municipalityId: '06001' },
    'users/otherMuni': { role: 'field_worker', teamId: 'team-a', municipalityId: '06002' },
    'users/disabledWorker': { role: 'field_worker', teamId: 'team-a', municipalityId: '06001', disabled: true },
    'users/noTeam': { role: 'field_worker', municipalityId: '06001' },
    'users/citizen': { role: 'citizen', teamId: 'team-a', municipalityId: '06001' },
    ...extraUsers,
  };
}

const call = (uid, data = {}) => sendReportUpdateHandler({
  auth: uid ? { uid } : undefined,
  data: { reportId: REPORT_ID, message: 'La cuadrilla llegó al lugar.', requestId: REQUEST_ID, ...data },
});

function setup(reportOverrides, extraUsers, plan) {
  state.db = new FakeDb(seed(reportOverrides, extraUsers));
  state.messaging = makeMessaging(plan);
  return state.db;
}

test('field_worker del equipo asignado y mismo municipio (alias georef) envía la actualización', async () => {
  const db = setup();
  const result = await call('worker');
  assert.equal(result.ok, true);
  assert.equal(result.delivery, 'push');
  assert.equal(result.imageAttached, true);
  const doc = db.get(`notifications/${REPORT_ID}_manual_${REQUEST_ID}`);
  assert.equal(doc.userId, 'owner');
  assert.equal(doc.type, 'municipality_update');
  assert.equal(doc.delivery, 'push');
  assert.equal(state.messaging.sent.length, 1);
  assert.equal(state.messaging.sent[0].token, 'tok-owner');
});

for (const [uid, label] of [
  ['otherTeam', 'field_worker de otro equipo'],
  ['otherMuni', 'field_worker con el mismo teamId pero de otro municipio'],
  ['disabledWorker', 'field_worker deshabilitado'],
  ['noTeam', 'field_worker sin equipo'],
  ['citizen', 'ciudadano con teamId falso en su perfil'],
]) {
  test(`deniega: ${label}`, async () => {
    const db = setup();
    await assert.rejects(call(uid), { code: 'permission-denied' });
    assert.equal(db.get(`notifications/${REPORT_ID}_manual_${REQUEST_ID}`), undefined);
    assert.equal(state.messaging.sent.length, 0);
  });
}

test('deniega a la cuadrilla en reportes cerrados, pero la gestión municipal puede avisar', async () => {
  for (const status of ['resolved', 'closed', 'rejected']) {
    setup({ status });
    await assert.rejects(call('worker'), { code: 'permission-denied' }, status);
  }
  setup({ status: 'resolved' }, { 'users/coord': { role: 'coordinator', municipalityId: '06001' } });
  const result = await call('coord');
  assert.equal(result.ok, true);
});

test('deniega si el reporte no tiene municipio (la cuadrilla no puede probar pertenencia)', async () => {
  setup({ municipalityId: undefined });
  await assert.rejects(call('worker'), { code: 'permission-denied' });
});

test('deniega sin sesión, sin perfil y con reporte inexistente', async () => {
  setup();
  await assert.rejects(call(null), { code: 'unauthenticated' });
  await assert.rejects(call('ghost'), { code: 'permission-denied' });
  await assert.rejects(call('worker', { reportId: 'no-existe' }), { code: 'not-found' });
  await assert.rejects(call('worker', { reportId: 'a/b' }), { code: 'invalid-argument' });
});

test('valida mensaje y requestId antes de escribir', async () => {
  const db = setup();
  await assert.rejects(call('worker', { message: ' a ' }), { code: 'invalid-argument' });
  await assert.rejects(call('worker', { requestId: 'corto' }), { code: 'invalid-argument' });
  assert.equal([...db.data.keys()].some((k) => k.startsWith('notifications/')), false);
});

test('mismo requestId no reenvía el push (idempotente)', async () => {
  setup();
  await call('worker');
  const second = await call('worker');
  assert.equal(second.ok, true);
  assert.equal(state.messaging.sent.length, 1);
});

test('token inválido del vecino se borra y el aviso queda in_app', async () => {
  const invalid = Object.assign(new Error('x'), { code: 'messaging/invalid-registration-token' });
  const db = setup({}, {}, () => invalid);
  const result = await call('worker');
  assert.equal(result.delivery, 'in_app');
  assert.equal(db.get(`notifications/${REPORT_ID}_manual_${REQUEST_ID}`).pushError, 'invalid_token');
  assert.equal(db.get('users/owner').fcmToken?.constructor?.name, 'FakeFieldDelete');
});

test('el texto de la cuadrilla se sanea (sin enlaces)', async () => {
  const db = setup();
  await call('worker', { message: 'Mirá https://phishing.example/x ya está' });
  assert.equal(db.get(`notifications/${REPORT_ID}_manual_${REQUEST_ID}`).body, 'Mirá [enlace omitido] ya está');
});
