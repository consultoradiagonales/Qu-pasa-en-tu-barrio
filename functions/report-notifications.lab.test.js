'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { state, makeMessaging, FakeDb } = require('./test-helpers/stub-firebase');
const { isDelete } = require('./test-helpers/fake-firestore');
const { notifyAssignedWorkers, notifyReportChange, assignmentKey } = require('./report-notifications');

const REPORT_ID = 'rep-0001';
const snap = (value) => ({ data: () => value });
const event = (before, after, reportId = REPORT_ID) => ({
  params: { reportId },
  data: { before: snap(before), after: snap(after) },
});

function seedUsers() {
  return {
    'users/w1': { role: 'field_worker', teamId: 'team-a', municipalityId: 'm1', fcmToken: 'tok-w1' },
    'users/w2': { role: 'field_worker', teamId: 'team-a', municipalityId: 'm1' }, // sin token
    'users/wOff': { role: 'field_worker', teamId: 'team-a', municipalityId: 'm1', disabled: true, fcmToken: 'tok-off' },
    'users/wB': { role: 'field_worker', teamId: 'team-b', municipalityId: 'm1', fcmToken: 'tok-wB' },
    'users/cit': { role: 'citizen', teamId: 'team-a', municipalityId: 'm1', fcmToken: 'tok-cit' },
    'users/gm': { role: 'field_manager', organizationId: 'diagonales', fcmToken: 'tok-gm' },
    'users/gmOff': { role: 'field_manager', organizationId: 'diagonales', disabled: true, fcmToken: 'tok-gmoff' },
    'users/lm': { role: 'field_manager', organizationId: 'muni', municipalityId: 'm1', fcmToken: 'tok-lm' },
  };
}

const pending = { status: 'pending', userId: 'owner' };
const assignedA = { status: 'assigned', assignedTeamId: 'team-a', assignmentVersion: 1, userId: 'owner' };
const notifIds = (db) => [...db.data.keys()].filter((k) => k.startsWith('notifications/')).sort();

test('notifyAssignedWorkers: entrega a la cuadrilla activa y a la gerencia central, excluye deshabilitados y ajenos', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  const result = await notifyAssignedWorkers(event(pending, assignedA), db);
  const key = assignmentKey(REPORT_ID, 1);
  assert.deepEqual(notifIds(db), [`notifications/${key}_gm`, `notifications/${key}_w1`, `notifications/${key}_w2`]);
  assert.deepEqual(result, { total: 3, pushed: 2, inApp: 1 });
  const tokens = state.messaging.sent.map((m) => m.token).sort();
  assert.deepEqual(tokens, ['tok-gm', 'tok-w1']);
  for (const forbidden of ['tok-off', 'tok-wB', 'tok-cit', 'tok-gmoff', 'tok-lm']) assert.ok(!tokens.includes(forbidden), forbidden);
  const doc = db.get(`notifications/${key}_w1`);
  assert.equal(doc.type, 'field_assignment');
  assert.equal(doc.actionUrl, `/field/task/${REPORT_ID}`);
  assert.equal(doc.teamId, 'team-a');
  assert.equal(doc.delivery, 'push');
  assert.equal(doc.userId, 'w1');
  assert.equal(db.get(`notifications/${key}_w2`).delivery, 'in_app');
});

test('notifyAssignedWorkers: un reintento del mismo evento no duplica avisos ni pushes', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  await notifyAssignedWorkers(event(pending, assignedA), db);
  const sentBefore = state.messaging.sent.length;
  const second = await notifyAssignedWorkers(event(pending, assignedA), db);
  assert.equal(second.pushed, 0);
  assert.equal(second.inApp, 0);
  assert.equal(state.messaging.sent.length, sentBefore);
  assert.equal(notifIds(db).length, 3);
});

test('notifyAssignedWorkers: cambios sin reasignación no notifican', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  assert.equal(await notifyAssignedWorkers(event(assignedA, { ...assignedA, priority: 5 }), db), null);
  assert.equal(await notifyAssignedWorkers(event(assignedA, { ...assignedA, status: 'in_progress' }), db), null);
  assert.equal(await notifyAssignedWorkers(event(pending, { ...assignedA, assignedTeamId: '' }), db), null);
  assert.equal(notifIds(db).length, 0);
});

test('notifyAssignedWorkers: reasignación con assignmentVersion nueva avisa al equipo destino y no al anterior', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  await notifyAssignedWorkers(event(pending, assignedA), db);
  const reassigned = { ...assignedA, assignedTeamId: 'team-b', assignmentVersion: 2 };
  const result = await notifyAssignedWorkers(event(assignedA, reassigned), db);
  const key2 = assignmentKey(REPORT_ID, 2);
  assert.deepEqual(result, { total: 2, pushed: 2, inApp: 0 });
  assert.ok(db.get(`notifications/${key2}_wB`));
  assert.ok(db.get(`notifications/${key2}_gm`), 'la gerencia central recibe la reasignación');
  assert.equal(db.get(`notifications/${key2}_w1`), undefined, 'el equipo anterior no recibe la nueva tarea');
});

test('notifyAssignedWorkers: re-despacho al mismo equipo con versión nueva vuelve a avisar', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  await notifyAssignedWorkers(event(pending, assignedA), db);
  const result = await notifyAssignedWorkers(event(assignedA, { ...assignedA, assignmentVersion: 2 }), db);
  assert.equal(result.total, 3);
  assert.equal(result.pushed, 2);
  assert.ok(db.get(`notifications/${assignmentKey(REPORT_ID, 2)}_w1`));
});

test('notifyAssignedWorkers: reasignación SIN assignmentVersion avisa al equipo nuevo y a la gerencia central', async () => {
  const db = new FakeDb(seedUsers());
  state.messaging = makeMessaging();
  const v0a = { status: 'assigned', assignedTeamId: 'team-a', userId: 'owner' };
  await notifyAssignedWorkers(event(pending, v0a), db);
  const sentBefore = state.messaging.sent.length;
  await notifyAssignedWorkers(event(v0a, { ...v0a, assignedTeamId: 'team-b' }), db);
  const newTokens = state.messaging.sent.slice(sentBefore).map((m) => m.token).sort();
  assert.deepEqual(newTokens, ['tok-gm', 'tok-wB']);
  // Un reintento del mismo evento sin versión sigue siendo idempotente.
  const sentAfter = state.messaging.sent.length;
  await notifyAssignedWorkers(event(v0a, { ...v0a, assignedTeamId: 'team-b' }), db);
  assert.equal(state.messaging.sent.length, sentAfter);
  assert.notEqual(assignmentKey(REPORT_ID, undefined, 'team-a'), assignmentKey(REPORT_ID, undefined, 'team-b'));
  assert.equal(assignmentKey(REPORT_ID, 3, 'team-a'), assignmentKey(REPORT_ID, 3, 'team-b'));
});

test('notifyAssignedWorkers: token inválido se borra y el aviso queda in_app', async () => {
  const db = new FakeDb(seedUsers());
  const invalid = Object.assign(new Error('gone'), { code: 'messaging/registration-token-not-registered' });
  state.messaging = makeMessaging((token) => (token === 'tok-w1' ? invalid : null));
  const result = await notifyAssignedWorkers(event(pending, assignedA), db);
  assert.deepEqual(result, { total: 3, pushed: 1, inApp: 2 });
  const key = assignmentKey(REPORT_ID, 1);
  assert.equal(db.get(`notifications/${key}_w1`).pushError, 'invalid_token');
  assert.ok(isDelete(db.get('users/w1').fcmToken), 'el token inválido se marca para borrar');
});

test('notifyAssignedWorkers: equipo sin integrantes activos devuelve total 0 sin escribir', async () => {
  const db = new FakeDb({ 'users/wOff': { role: 'field_worker', teamId: 'team-z', disabled: true } });
  state.messaging = makeMessaging();
  const result = await notifyAssignedWorkers(event(pending, { ...assignedA, assignedTeamId: 'team-z' }), db);
  assert.deepEqual(result, { total: 0, pushed: 0, inApp: 0 });
  assert.equal(notifIds(db).length, 0);
});

test('notifyReportChange: una asignación avisa al dueño y a la cuadrilla', async () => {
  const db = new FakeDb({ ...seedUsers(), 'users/owner': { role: 'citizen', fcmToken: 'tok-owner' } });
  state.db = db;
  state.messaging = makeMessaging();
  assert.equal(await notifyReportChange(event(pending, assignedA)), null);
  const ownerNotif = db.get(`notifications/${REPORT_ID}_assigned_team-a`);
  assert.equal(ownerNotif.userId, 'owner');
  assert.equal(ownerNotif.type, 'report_assigned');
  assert.equal(ownerNotif.delivery, 'push');
  assert.ok(db.get(`notifications/${assignmentKey(REPORT_ID, 1)}_w1`));
  const tokens = state.messaging.sent.map((m) => m.token).sort();
  assert.deepEqual(tokens, ['tok-gm', 'tok-owner', 'tok-w1']);
});

test('notifyReportChange: progreso sin reasignación sólo avisa al dueño (in_app si no tiene token)', async () => {
  const db = new FakeDb({ ...seedUsers(), 'users/owner': { role: 'citizen' } });
  state.db = db;
  state.messaging = makeMessaging();
  const before = { ...assignedA, status: 'in_progress', photosProgress: [] };
  const after = { ...before, photosProgress: ['https://storage.example/p.jpg'] };
  await notifyReportChange(event(before, after));
  assert.deepEqual(notifIds(db), [`notifications/${REPORT_ID}_progress_1`]);
  assert.equal(db.get(`notifications/${REPORT_ID}_progress_1`).delivery, 'in_app');
  assert.equal(state.messaging.sent.length, 0);
});

test('notifyReportChange: reintento del trigger no reenvía pushes', async () => {
  const db = new FakeDb({ ...seedUsers(), 'users/owner': { role: 'citizen', fcmToken: 'tok-owner' } });
  state.db = db;
  state.messaging = makeMessaging();
  await notifyReportChange(event(pending, assignedA));
  const count = state.messaging.sent.length;
  await notifyReportChange(event(pending, assignedA));
  assert.equal(state.messaging.sent.length, count);
});
