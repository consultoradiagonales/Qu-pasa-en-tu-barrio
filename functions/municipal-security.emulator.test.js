'use strict';

// Sólo emuladores locales y proyecto demo: nunca usa credenciales productivas.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { assignReportTeamHandler } = require('./report-assignment');
const { notifyAssignedWorkers } = require('./report-notifications');
const { getManagementDashboardHandler } = require('./management-dashboard');

const projectId = 'demo-condi-audit';
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
const app = initializeApp({ projectId }, 'municipal-security-audit');
const db = getFirestore(app);
const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${projectId}/databases/(default)/documents`;
const actors = {};

function encode(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  if (typeof value === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)])) } };
  return { stringValue: value };
}

async function writeAs(actor, path, values, serverTime = false) {
  const serverTimeFields = serverTime === true ? ['createdAt'] :
    Array.isArray(serverTime) ? serverTime : [];
  const response = await fetch(`${base}:commit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors[actor].idToken}` },
    body: JSON.stringify({ writes: [{
      update: { name: `${base.split('/v1/')[1]}/${path}`, fields: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, encode(v)])) },
      updateMask: { fieldPaths: Object.keys(values) },
      ...(serverTimeFields.length ? { updateTransforms: serverTimeFields.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) } : {}),
    }] }),
  });
  return { status: response.status, body: await response.json() };
}

async function readAs(actor, path) {
  const response = await fetch(`${base}/${path}`, { headers: { Authorization: `Bearer ${actors[actor].idToken}` } });
  return response.status;
}

async function uploadAs(actor, path) {
  return fetch(
    `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${projectId}.appspot.com/o?uploadType=media&name=${encodeURIComponent(path)}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${actors[actor].idToken}`,
        'Content-Type': 'image/jpeg',
      },
      body: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    },
  );
}

function comment(overrides = {}) {
  return { reportId: 'case-a', userId: actors.citizenA.localId, displayName: 'Vecino de prueba', text: 'Sigue pendiente',
    isOfficialResponse: false, hidden: false, flaggedCount: 0, createdAt: new Date(), ...overrides };
}

test.before(async () => {
  for (const [name, role, municipalityId, disabled] of [
    ['citizenA', 'citizen', 'a', false], ['citizenB', 'citizen', 'b', false],
    ['coordinatorA', 'coordinator', 'a', false], ['coordinatorB', 'coordinator', 'b', false],
    ['disabled', 'citizen', 'a', true], ['admin', 'admin', 'b', false],
    ['fieldManager', 'field_manager', 'a', false],
    ['fieldWorkerA', 'field_worker', 'a', false],
    ['fakeFieldManager', 'field_manager', 'b', false],
    ['schema', 'citizen', 'a', false], ['quota', 'citizen', 'a', false],
    ['awayValidation', 'citizen', 'a', false],
    ['localAdminA', 'admin', 'a', false], ['localAdminB', 'admin', 'b', false],
    ['dashboardA', 'coordinator', 'analytics-a', false], ['dashboardB', 'admin', 'analytics-b', false],
  ]) {
    const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
    });
    assert.equal(response.status, 200);
    actors[name] = await response.json();
    await db.collection('users').doc(actors[name].localId).set({
      role,
      municipalityId,
      disabled,
      ...(name === 'fieldWorkerA' ? { teamId: 'team-a' } : {}),
      ...(['admin', 'fieldManager'].includes(name)
        ? { organizationId: 'diagonales' }
        : {}),
    });
  }
  await db.doc('reports/case-a').set({ municipalityId: 'a', userId: actors.citizenA.localId, hidden: false, status: 'pending' });
  await db.doc('reports/case-a-georef').set({ municipalityId: 'georef_a', userId: actors.citizenA.localId, hidden: false, status: 'pending', createdAt: new Date() });
  await db.doc('reports/field-task-a').set({ municipalityId: 'a', userId: actors.citizenA.localId, hidden: false, status: 'assigned', assignedTeamId: 'team-a', priority: 3 });
  await db.doc('reports/field-task-georef').set({ municipalityId: 'georef_a', userId: actors.citizenA.localId, hidden: false, status: 'assigned', assignedTeamId: 'team-a', priority: 2 });
  await db.doc('reports/private-a').set({ municipalityId: 'a', userId: actors.coordinatorA.localId, hidden: true, status: 'pending' });
  await db.doc('reports/case-b').set({ municipalityId:'b', userId:actors.citizenB.localId, hidden:false, status:'pending', flaggedCount:0 });
  await db.doc('reports/manager-case-b').set({
    municipalityId: 'b',
    userId: actors.citizenB.localId,
    hidden: false,
    status: 'pending',
    flaggedCount: 0,
    photosBefore: [],
    photosProgress: [],
    photosAfter: [],
    assignedWorkerId: null,
    workerArrivedAt: null,
    workStartedAt: null,
    workFinishedAt: null,
    resolvedAt: null,
    workerNotes: null,
  });
  await db.doc('reports/case-a/comments/existing').set(comment());
  for (const id of ['team-a', 'team-a2']) await db.doc(`teams/${id}`).set({ municipalityId: 'a', active: true });
  await db.doc('teams/team-b').set({ municipalityId: 'b', active: true });
  await db.doc('teams/team-inactive').set({ municipalityId: 'a', active: false });
  for (const municipalityId of ['a', 'b']) {
    await db.doc(`weatherAlerts/alert-${municipalityId}`).set({ municipalityId, createdAt: new Date() });
  }
});

test.after(async () => { await db.terminate(); await deleteApp(app); });

test('catálogo municipal: gerencia central puede listar; coordinación local no', async () => {
  await db.doc('municipalities/catalog-a').set({ name: 'Catálogo A' });
  await db.doc('municipalities/catalog-b').set({ name: 'Catálogo B' });
  async function listAs(actor) {
    const response = await fetch(`${base}/municipalities`, {
      headers: { Authorization: `Bearer ${actors[actor].idToken}` },
    });
    return response.status;
  }
  assert.equal(await listAs('fieldManager'), 200);
  assert.equal(await listAs('coordinatorA'), 403);
});

test('gerencia de cuadrillas: sólo Diagonales opera globalmente', async () => {
  assert.equal(await readAs('fieldManager', 'reports/case-a'), 200);
  assert.equal(await readAs('fieldManager', 'reports/case-b'), 200);
  assert.equal(await readAs('fakeFieldManager', 'reports/case-a'), 403);
  const request = (actor, reportId, teamId) => ({
    auth: { uid: actors[actor].localId },
    data: { reportId, teamId },
  });
  await assert.rejects(assignReportTeamHandler(
    request('fakeFieldManager', 'case-a', 'team-a'), db,
  ), {
    code: 'permission-denied',
  });
  const assigned = await assignReportTeamHandler(
    request('fieldManager', 'manager-case-b', 'team-b'), db,
  );
  assert.equal(assigned.teamId, 'team-b');
  assert.equal((await uploadAs(
    'fakeFieldManager',
    'reports/manager-case-b/before/denied.jpg',
  )).status, 403);
  assert.equal((await uploadAs(
    'fieldManager',
    'reports/manager-case-b/before/allowed.jpg',
  )).status, 200);
  const after = (await db.doc('reports/manager-case-b').get()).data();
  const delivery = await notifyAssignedWorkers({
    params: { reportId: 'manager-case-b' },
    data: {
      before: { data: () => ({ municipalityId: 'b', status: 'pending' }) },
      after: { data: () => after },
    },
  }, db);
  assert.equal(delivery.total, 1);
  const notifications = await db.collection('notifications')
    .where('userId', '==', actors.fieldManager.localId)
    .where('type', '==', 'field_assignment')
    .get();
  assert.equal(notifications.size, 1);
  assert.equal(notifications.docs[0].data().reportId, 'manager-case-b');

  const started = await writeAs('fieldManager', 'reports/manager-case-b', {
    status: 'in_progress',
    assignedWorkerId: actors.fieldManager.localId,
    photosBefore: ['https://storage.example/before.jpg'],
  }, ['workerArrivedAt', 'workStartedAt', 'updatedAt']);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  assert.equal((await uploadAs(
    'fieldManager',
    'reports/manager-case-b/progress/progress.jpg',
  )).status, 200);

  const progress = await writeAs('fieldManager', 'reports/manager-case-b', {
    photosProgress: ['https://storage.example/progress.jpg'],
  }, ['updatedAt']);
  assert.equal(progress.status, 200, JSON.stringify(progress.body));
  const replacedProgress = await writeAs('fieldManager', 'reports/manager-case-b', {
    photosProgress: ['https://storage.example/otra.jpg'],
  }, ['updatedAt']);
  assert.equal(replacedProgress.status, 403, JSON.stringify(replacedProgress.body));
  const clearedProgress = await writeAs('fieldManager', 'reports/manager-case-b', {
    photosProgress: [],
  }, ['updatedAt']);
  assert.equal(clearedProgress.status, 403, JSON.stringify(clearedProgress.body));
  const appendedProgress = await writeAs('fieldManager', 'reports/manager-case-b', {
    photosProgress: [
      'https://storage.example/progress.jpg',
      'https://storage.example/progress-2.jpg',
    ],
  }, ['updatedAt']);
  assert.equal(appendedProgress.status, 200, JSON.stringify(appendedProgress.body));
  assert.equal((await uploadAs(
    'fieldManager',
    'reports/manager-case-b/after/solution.jpg',
  )).status, 200);

  const resolved = await writeAs('fieldManager', 'reports/manager-case-b', {
    status: 'resolved',
    photosAfter: ['https://storage.example/after.jpg'],
    workerNotes: 'Luminaria reparada y verificada.',
  }, ['workFinishedAt', 'resolvedAt', 'updatedAt']);
  assert.equal(resolved.status, 200, JSON.stringify(resolved.body));

  const officialComment = comment({
    reportId: 'manager-case-b',
    userId: actors.fieldManager.localId,
    displayName: 'Fernando Genazzini',
    text: 'Trabajo finalizado.',
    isOfficialResponse: true,
  });
  assert.equal((await writeAs(
    'fieldManager',
    'reports/manager-case-b/comments/field-manager-update',
    officialComment,
  )).status, 200);
});

test('fotos de reporte: propietario puede cargar una vez; otro usuario y reemplazo se rechazan', async () => {
  // El vecino sólo carga la foto declarada por un alta pendiente
  // (photoStoragePath); un nombre libre sobre un caso existente se rechaza.
  const photo = 'reports/photo-pending-a/citizen/photo.jpg';
  await db.doc('reports/photo-pending-a').set({ municipalityId: 'a', userId: actors.citizenA.localId, hidden: false,
    status: 'pending', photoUploadStatus: 'pending', photoStoragePath: photo, photosReport: [] });
  assert.equal((await uploadAs('citizenA', 'reports/case-a/citizen/evidence.jpg')).status, 403);
  assert.equal((await uploadAs('citizenB', photo)).status, 403);
  assert.equal((await uploadAs('citizenA', photo)).status, 200);
  assert.equal((await uploadAs('citizenA', photo)).status, 403);
  assert.equal((await uploadAs('disabled', 'reports/case-a/citizen/disabled.jpg')).status, 403);
});

test('comentarios: acepta vecino del ámbito y rechaza otro municipio, padre ausente, caso privado y cuenta deshabilitada', async () => {
  assert.equal((await writeAs('citizenA', 'reports/case-a/comments/allowed', comment())).status, 200);
  for (const [actor, reportId] of [['citizenB', 'case-a'], ['citizenA', 'missing'], ['citizenA', 'private-a'], ['disabled', 'case-a']]) {
    assert.equal((await writeAs(actor, `reports/${reportId}/comments/denied-${actor}`, comment({ reportId, userId: actors[actor].localId }))).status, 403);
  }
});

test('municipio: el código histórico y su alias GeoRef comparten acceso y consulta', async () => {
  assert.equal(await readAs('coordinatorA', 'reports/case-a-georef'), 200);
  const structuredQuery = {
    from: [{ collectionId: 'reports' }],
    where: { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'IN',
      value: { arrayValue: { values: [{ stringValue: 'a' }, { stringValue: 'georef_a' }] } } } },
  };
  const response = await fetch(`${base}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors.coordinatorA.idToken}` },
    body: JSON.stringify({ structuredQuery }),
  });
  assert.equal(response.status, 200, await response.text());
});

test('operario: la lista acotada por municipio admite ambos alias y no abre otros ámbitos', async () => {
  assert.equal(await readAs('fieldWorkerA', 'reports/field-task-a'), 200);
  assert.equal(await readAs('fieldWorkerA', 'reports/case-b'), 403);
  const filters = [
    { fieldFilter: { field: { fieldPath: 'hidden' }, op: 'EQUAL', value: { booleanValue: false } } },
    { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'IN',
      value: { arrayValue: { values: [{ stringValue: 'a' }, { stringValue: 'georef_a' }] } } } },
  ];
  const query = async (where) => fetch(`${base}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors.fieldWorkerA.idToken}` },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'reports' }], where } }),
  });
  const unscoped = await query(filters[0]);
  assert.equal(unscoped.status, 403);
  const scoped = await query({ compositeFilter: { op: 'AND', filters } });
  const body = await scoped.text();
  assert.equal(scoped.status, 200, body);
  const rows = JSON.parse(body);
  const ids = rows.map((row) => row.document?.name.split('/').at(-1));
  assert.ok(ids.includes('field-task-a'));
  assert.ok(ids.includes('field-task-georef'));
  assert.ok(!ids.includes('case-b'));
});

test('comentarios: impide respuesta oficial falsa, texto excesivo y claves ajenas al esquema', async () => {
  for (const overrides of [{ isOfficialResponse: true }, { text: 'x'.repeat(4001) }, { internalNote: 'no' }, { userId: actors.citizenB.localId }]) {
    assert.equal((await writeAs('citizenA', 'reports/case-a/comments/invalid', comment(overrides))).status, 403);
  }
  assert.equal((await writeAs('coordinatorA', 'reports/case-a/comments/official', comment({ userId: actors.coordinatorA.localId, isOfficialResponse: true }))).status, 200);
});

test('moderación: sólo gestión del municipio o central puede ocultar; no puede reescribir autor/texto', async () => {
  const path = 'reports/case-a/comments/existing';
  assert.equal((await writeAs('coordinatorB', path, { hidden: true })).status, 403);
  assert.equal((await writeAs('coordinatorA', path, { text: 'reescrito' })).status, 403);
  assert.equal((await writeAs('coordinatorA', path, { hidden: true })).status, 200);
  assert.equal((await writeAs('admin', path, { hidden: false })).status, 200);
});

test('denuncias: exige padre accesible, destino real y permite revisar sólo dentro del municipio', async () => {
  const flag = { reportedBy: actors.citizenA.localId, targetType: 'report', targetId: 'case-a', reportId: 'case-a', reason: 'Revisión', status: 'pending' };
  assert.equal((await writeAs('citizenA', 'contentFlags/allowed', flag, true)).status, 200);
  assert.equal((await writeAs('citizenB', 'contentFlags/cross', { ...flag, reportedBy: actors.citizenB.localId }, true)).status, 403);
  assert.equal((await writeAs('citizenA', 'contentFlags/invalid-target', { ...flag, targetId: 'other' }, true)).status, 403);
  assert.equal((await writeAs('citizenA', 'contentFlags/missing-comment', { ...flag, targetType: 'comment', targetId: 'missing' }, true)).status, 403);
  assert.equal((await writeAs('citizenA', 'contentFlags/comment', { ...flag, targetType: 'comment', targetId: 'existing' }, true)).status, 200);
  assert.equal(await readAs('coordinatorB', 'contentFlags/allowed'), 403);
  assert.equal(await readAs('coordinatorA', 'contentFlags/allowed'), 200);
  assert.equal((await writeAs('coordinatorB', 'contentFlags/allowed', { status: 'reviewed' })).status, 403);
  assert.equal((await writeAs('coordinatorA', 'contentFlags/allowed', { reportId: 'other' })).status, 403);
  assert.equal((await writeAs('coordinatorA', 'contentFlags/allowed', { status: 'reviewed' })).status, 200);
});

test('alertas: consulta municipal del coordinador funciona y consulta global requiere administrador', async () => {
  async function alertsAs(actor, municipalityId) {
    const structuredQuery = { from: [{ collectionId: 'weatherAlerts' }], orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }], limit: 100 };
    if (municipalityId) structuredQuery.where = { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'EQUAL', value: { stringValue: municipalityId } } };
    const response = await fetch(`${base}:runQuery`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors[actor].idToken}` }, body: JSON.stringify({ structuredQuery }) });
    return { status: response.status, data: await response.json() };
  }
  const scoped = await alertsAs('coordinatorA', 'a');
  assert.equal(scoped.status, 200);
  assert.equal(scoped.data.filter((item) => item.document).length, 1);
  assert.equal(scoped.data[0].document.fields.municipalityId.stringValue, 'a');
  assert.equal((await alertsAs('coordinatorA')).status, 403);
  assert.equal((await alertsAs('coordinatorA', 'b')).status, 403);
  assert.equal((await alertsAs('admin')).status, 200);
});

test('dos asignaciones concurrentes desde la misma versión: una aceptación, un conflicto y un evento', async () => {
  const request = (teamId) => ({ auth: { uid: actors.coordinatorA.localId }, data: { reportId: 'case-a', teamId, expectedVersion: 0 } });
  const result = await Promise.allSettled([assignReportTeamHandler(request('team-a'), db), assignReportTeamHandler(request('team-a2'), db)]);
  assert.equal(result.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(result.find((r) => r.status === 'rejected').reason.code, 'aborted');
  const report = (await db.doc('reports/case-a').get()).data();
  assert.equal(report.assignmentVersion, 1);
  assert.equal(report.status, 'assigned');
  const events = await db.doc('reports/case-a').collection('assignmentEvents').get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].data().teamId, report.assignedTeamId);
  assert.equal(await readAs('citizenA', `reports/case-a/assignmentEvents/${events.docs[0].id}`), 403);
});

test('asignación: no cruza municipios, no acepta ciudadanos ni deshabilitados y no revierte trabajo iniciado', async () => {
  const request = (actor, teamId = 'team-a') => ({ auth: { uid: actors[actor].localId }, data: { reportId: 'case-a', teamId } });
  for (const actor of ['citizenA', 'disabled', 'coordinatorB']) {
    await assert.rejects(assignReportTeamHandler(request(actor), db), { code: 'permission-denied' });
  }
  await assert.rejects(assignReportTeamHandler(request('coordinatorA', 'team-b'), db), { code: 'failed-precondition' });
  await assert.rejects(assignReportTeamHandler(request('coordinatorA', 'team-inactive'), db), { code: 'failed-precondition' });
  await db.doc('reports/case-a').update({ status: 'in_progress' });
  await assert.rejects(assignReportTeamHandler(request('coordinatorA'), db), { code: 'failed-precondition' });
  assert.equal((await db.doc('reports/case-a').get()).data().status, 'in_progress');
});

test('asignación: rechaza entrada inválida y conserva compatibilidad de cliente sin versión', async () => {
  await assert.rejects(assignReportTeamHandler({}, db), { code: 'unauthenticated' });
  await assert.rejects(assignReportTeamHandler({ auth: { uid: actors.coordinatorA.localId }, data: { reportId: 'a/b', teamId: 'team-a' } }, db), { code: 'invalid-argument' });
  await db.doc('reports/legacy').set({ municipalityId: 'a', status: 'pending' });
  const result = await assignReportTeamHandler({ auth: { uid: actors.coordinatorA.localId }, data: { reportId: 'legacy', teamId: 'team-a' } }, db);
  assert.equal(result.assignmentVersion, 1);
});

function submission(actor, overrides = {}) {
  return {
    userId: actors[actor].localId, municipalityId: 'a', municipalityName: 'Municipio de prueba',
    homeMunicipalityId: 'a', reportedAwayFromHome: false,
    provinceId: null, province: null, departmentId: null, department: null, localityId: null, locality: null, settlementId: null, settlement: null,
    title: 'Luminaria apagada', description: 'No enciende', category: 'lighting',
    photosReport: ['https://example.test/synthetic-photo.jpg'], photosBefore: [], photosProgress: [], photosAfter: [],
    location: { lat: -34.6, lng: -58.4, geohash: '69y7', address: null, isManualAddress: false },
    status: 'pending', priority: 1, supportCount: 0, assignedTeamId: null, assignedWorkerId: null, assignedAt: null,
    workerArrivedAt: null, workStartedAt: null, workFinishedAt: null, workerNotes: null, resolvedAt: null, rejectionReason: null,
    hidden: false, flaggedCount: 0, commentsCount: 0, rating: null, ratingComment: null, aiRequested: false, aiConsentVersion: 0, submissionProtocol: 1,
    ...overrides,
  };
}

async function submitAs(actor, id, slot, overrides = {}, { includeQuota = true, resetSlots = false, clientTime = false, legacyClient = false } = {}) {
  const values = submission(actor, overrides);
  if (legacyClient) delete values.submissionProtocol;
  if (legacyClient) {
    delete values.homeMunicipalityId;
    delete values.reportedAwayFromHome;
  }
  if (clientTime) { values.createdAt = new Date('2020-01-01'); values.updatedAt = new Date('2020-01-01'); }
  const documentRoot = base.split('/v1/')[1];
  const writes = [{
    update: { name: `${documentRoot}/reports/${id}`, fields: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, encode(v)])) },
    ...(!clientTime ? { updateTransforms: ['createdAt', 'updatedAt'].map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) } : {}),
  }];
  if (includeQuota) {
    const quotaFields = { lastSlot: slot, lastReportId: id, ...(resetSlots ? { slots: {} } : {}) };
    writes.push({
      update: { name: `${documentRoot}/reportSubmissionQuotas/${actors[actor].localId}`, fields: Object.fromEntries(Object.entries(quotaFields).map(([k, v]) => [k, encode(v)])) },
      updateMask: { fieldPaths: Object.keys(quotaFields) },
      updateTransforms: [{ fieldPath: 'slots.`' + slot + '`', setToServerValue: 'REQUEST_TIME' }, { fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
    });
  }
  const response = await fetch(`${base}:commit`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors[actor].idToken}` }, body: JSON.stringify({ writes }) });
  return { status: response.status, body: await response.json() };
}

test('alta: confirma reporte y cuota atómicos, con estado inicial y reloj del servidor', async () => {
  // Lecturas que necesita la transacción Flutter antes de crear el UUID.
  assert.equal(await readAs('schema', 'reports/submission-valid'), 404);
  assert.equal(await readAs('schema', `reportSubmissionQuotas/${actors.schema.localId}`), 404);
  const result = await submitAs('schema', 'submission-valid', '0');
  assert.equal(result.status, 200, JSON.stringify(result.body));
  const report = (await db.doc('reports/submission-valid').get()).data();
  const quota = (await db.doc(`reportSubmissionQuotas/${actors.schema.localId}`).get()).data();
  assert.equal(report.status, 'pending');
  assert.equal(report.createdAt.toMillis(), quota.slots['0'].toMillis());
  assert.equal(quota.lastReportId, 'submission-valid');
});

test('alta ágil: el municipio recibe el reporte antes de que termine la foto', async () => {
  const id = 'submission-fast-intake';
  const storagePath = `reports/${id}/citizen/photo.jpg`;
  const result = await submitAs('schema', id, '2', {
    photosReport: [],
    photoUploadStatus: 'pending',
    photoStoragePath: storagePath,
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  const pending = (await db.doc(`reports/${id}`).get()).data();
  assert.equal(pending.photoUploadStatus, 'pending');
  assert.deepEqual(pending.photosReport, []);
  assert.equal(await readAs('coordinatorA', `reports/${id}`), 200);

  const url = 'https://firebasestorage.googleapis.com/v0/b/demo/o/photo.jpg';
  const completed = await writeAs('schema', `reports/${id}`, {
    photosReport: [url],
    photoUploadStatus: 'ready',
  }, ['photoUploadedAt', 'updatedAt']);
  assert.equal(completed.status, 200, JSON.stringify(completed.body));
  const ready = (await db.doc(`reports/${id}`).get()).data();
  assert.equal(ready.photoUploadStatus, 'ready');
  assert.deepEqual(ready.photosReport, [url]);
  assert.ok(ready.photoUploadedAt);

  assert.equal((await writeAs('schema', `reports/${id}`, {
    photosReport: ['https://example.test/replaced.jpg'],
  })).status, 403);
});

test('alta: permite reportar donde ocurrió sin cambiar el municipio habitual', async () => {
  const result = await submitAs('schema', 'submission-away', '1', {
    municipalityId: 'b',
    municipalityName: 'Municipio visitado',
    homeMunicipalityId: 'a',
    reportedAwayFromHome: true,
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  const report = (await db.doc('reports/submission-away').get()).data();
  assert.equal(report.municipalityId, 'b');
  assert.equal(report.homeMunicipalityId, 'a');
  assert.equal(report.reportedAwayFromHome, true);
  assert.equal((await db.doc(`users/${actors.schema.localId}`).get()).data().municipalityId, 'a');
  // El autor puede seguir su caso visitante, pero no adquiere acceso al resto
  // de los casos del destino. Tampoco lo adquiere el personal de su origen.
  assert.equal(await readAs('schema', 'reports/submission-away'), 200);
  assert.equal(await readAs('schema', 'reports/case-b'), 403);
  for (const actor of ['coordinatorA', 'localAdminA', 'citizenA']) {
    assert.equal(await readAs(actor, 'reports/submission-away'), 403, actor);
  }
  for (const actor of ['coordinatorB', 'localAdminB', 'admin']) {
    assert.equal(await readAs(actor, 'reports/submission-away'), 200, actor);
  }
  assert.equal((await writeAs('schema', 'reports/submission-away', { municipalityId: 'a' })).status, 403);
  assert.equal((await writeAs('coordinatorA', 'reports/submission-away', { flaggedCount: 1 })).status, 403);
});

test('alta visitante: origen y excepción deben ser coherentes; GeoRef no requiere cambiar perfil ni adhesión', async () => {
  const invalid = [
    { municipalityId: 'b', homeMunicipalityId: 'b', reportedAwayFromHome: false },
    { municipalityId: 'b', homeMunicipalityId: 'a', reportedAwayFromHome: false },
    { municipalityId: 'a', homeMunicipalityId: 'a', reportedAwayFromHome: true },
    { municipalityId: 'b', homeMunicipalityId: null, reportedAwayFromHome: true },
    { municipalityId: 'b', homeMunicipalityId: 'a', reportedAwayFromHome: null },
  ];
  const quotaRef = db.doc(`reportSubmissionQuotas/${actors.awayValidation.localId}`);
  for (const [index, overrides] of invalid.entries()) {
    const id = `away-inconsistent-${index}`;
    const result = await submitAs('awayValidation', id, '0', overrides);
    assert.equal(result.status, 403, `${index}: ${JSON.stringify(result.body)}`);
    assert.equal((await db.doc(`reports/${id}`).get()).exists, false);
    assert.equal((await quotaRef.get()).exists, false);
  }
  // Confirma que los rechazos anteriores no se debían a una cuota consumida
  // y conserva la selección nacional GeoRef, no sólo municipios adheridos.
  const destination = 'georef_060441';
  assert.equal((await db.doc(`municipalities/${destination}`).get()).exists, false);
  const accepted = await submitAs('awayValidation', 'away-georef-destination', '0', {
    municipalityId: destination,
    municipalityName: 'La Plata',
    provinceId: '06',
    province: 'Buenos Aires',
    homeMunicipalityId: 'a',
    reportedAwayFromHome: true,
  });
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
  assert.equal((await quotaRef.get()).data().lastReportId, 'away-georef-destination');
  assert.equal((await db.doc(`users/${actors.awayValidation.localId}`).get()).data().municipalityId, 'a');
  assert.equal(await readAs('awayValidation', 'reports/away-georef-destination'), 200);
  assert.equal(await readAs('localAdminA', 'reports/away-georef-destination'), 403);
});

test('alta: rechaza esquema inventado, metadatos operativos, campos excesivos y consentimiento inconsistente', async () => {
  const invalid = [
    { priority: 5 }, { status: 'resolved' }, { assignedTeamId: 'team-a' }, { assignmentVersion: 10 },
    { supportCount: 100 }, { flaggedCount: 1 }, { commentsCount: 1 }, { rating: 5 },
    { workerNotes: 'inventado' }, { photosBefore: ['https://example.test/other'] },
    { title: '' }, { title: 'x'.repeat(81) }, { description: 'x'.repeat(501) }, { category: 'invented' },
    { aiRequested: false, aiConsentVersion: 1 }, { photosReport: [] }, { photosReport: [42] },
    { location: { lat: 91, lng: -58, geohash: '69y', address: null, isManualAddress: false } },
    { location: { lat: -34, lng: -181, geohash: '69y', address: null, isManualAddress: false } },
    { internalNote: 'no' },
  ];
  for (const [index, overrides] of invalid.entries()) {
    const result = await submitAs('schema', `submission-invalid-${index}`, '1', overrides);
    assert.equal(result.status, 403, `Esquema ${index}: ${JSON.stringify(result.body)}`);
    assert.equal((await db.doc(`reports/submission-invalid-${index}`).get()).exists, false);
  }
});

test('alta: impide omitir cuota, adelantar el reloj, usar otra identidad/municipio o cuenta deshabilitada', async () => {
  assert.equal((await submitAs('schema', 'submission-no-quota', '1', {}, { includeQuota: false })).status, 403);
  assert.equal((await submitAs('schema', 'submission-client-time', '1', {}, { clientTime: true })).status, 403);
  assert.equal((await submitAs('schema', 'submission-cross-user', '1', { userId: actors.citizenB.localId })).status, 403);
  assert.equal((await submitAs('schema', 'submission-cross-town', '1', { municipalityId: 'b' })).status, 403);
  assert.equal((await submitAs('disabled', 'submission-disabled', '0')).status, 403);
  assert.equal(await readAs('schema', `reportSubmissionQuotas/${actors.quota.localId}`), 403);
});

test('cuota: diez altas concurrentes se admiten; la undécima no crea reporte ni altera la reserva', async () => {
  const results = await Promise.all(Array.from({ length: 10 }, (_, index) => submitAs('quota', `quota-report-${index}`, String(index))));
  for (const result of results) assert.equal(result.status, 200, JSON.stringify(result.body));
  const ref = db.doc(`reportSubmissionQuotas/${actors.quota.localId}`);
  const before = (await ref.get()).data();
  assert.equal(Object.keys(before.slots).length, 10);
  const blocked = await submitAs('quota', 'quota-report-eleventh', '0');
  assert.equal(blocked.status, 403);
  assert.equal((await db.doc('reports/quota-report-eleventh').get()).exists, false);
  assert.deepEqual((await ref.get()).data(), before);
  // No se puede borrar el historial de las otras nueve posiciones en un alta.
  assert.equal((await submitAs('quota', 'quota-report-reset', '0', {}, { resetSlots: true })).status, 403);
});

test('cuota: sólo se reutiliza una posición al vencer 24 horas; no se borra ni modifica fuera de un alta', async () => {
  const path = `reportSubmissionQuotas/${actors.quota.localId}`;
  const ref = db.doc(path);
  await ref.update({ 'slots.0': new Date(Date.now() - 24 * 3600000 - 1000) });
  assert.equal((await submitAs('quota', 'quota-report-after-expiry', '0')).status, 200);
  const data = (await ref.get()).data();
  assert.equal(Object.keys(data.slots).length, 10);
  assert.equal((await writeAs('quota', path, { lastReportId: 'not-created' })).status, 403);
  const response = await fetch(`${base}/${path}`, { method: 'DELETE', headers: { Authorization: `Bearer ${actors.quota.idToken}` } });
  assert.equal(response.status, 403);
});

test('transición: legado sólo con política explícita; protocolo nuevo sigue exigiendo cuota', async () => {
  const options = { includeQuota: false, clientTime: true, legacyClient: true };
  assert.equal((await submitAs('schema', 'legacy-policy-disabled', '1', {}, options)).status, 403);
  const policy = db.doc('reportSubmissionPolicy/current');
  await policy.set({ legacyEnabled: true });
  try {
    assert.equal((await submitAs('schema', 'legacy-policy-enabled', '1', {}, options)).status, 200);
    assert.equal((await submitAs('schema', 'new-protocol-no-quota', '1', {}, { includeQuota: false })).status, 403);
    assert.equal((await submitAs('schema', 'legacy-other-municipality', '1', { municipalityId: 'b' }, options)).status, 403);
    assert.equal((await submitAs('disabled', 'legacy-disabled-account', '1', {}, options)).status, 403);
    assert.equal((await writeAs('schema', 'reportSubmissionPolicy/current', { legacyEnabled: false })).status, 403);
  } finally {
    await policy.delete();
  }
  assert.equal((await submitAs('schema', 'legacy-policy-retired', '1', {}, options)).status, 403);
});

test('aislamiento: admin municipal sólo ve su ámbito; Diagonales puede consultar ambos', async () => {
  assert.equal(await readAs('localAdminA','reports/case-a'),200);
  assert.equal(await readAs('localAdminA','reports/case-b'),403);
  assert.equal(await readAs('localAdminB','reports/case-a'),403);
  assert.equal(await readAs('admin','reports/case-a'),200);
  assert.equal(await readAs('admin','reports/case-b'),200);
  assert.equal((await writeAs('localAdminA','reports/case-b',{flaggedCount:1})).status,403);
  assert.equal((await writeAs('localAdminA',`users/${actors.localAdminA.localId}`,{organizationId:'diagonales'})).status,403);
  assert.equal((await writeAs('citizenA',`users/${actors.citizenA.localId}`,{role:'admin',organizationId:'diagonales'})).status,403);
  await assert.rejects(assignReportTeamHandler({auth:{uid:actors.localAdminB.localId},data:{reportId:'case-a',teamId:'team-a'}},db),{code:'permission-denied'});
});

test('tablero: supera 2.000 casos, incluye pendiente histórico y aplica ámbito en servidor', async () => {
  const records=Array.from({length:2101},(_,index)=>({id:`dashboard-case-${String(index).padStart(5,'0')}`,data:{municipalityId:'analytics-a',municipalityName:'Municipio A',hidden:false,status:index===0?'pending':'resolved',category:'lighting',createdAt:new Date('2020-01-01T00:00:00Z'),resolvedAt:index===0?null:new Date('2020-01-02T00:00:00Z')}}));
  for(let index=0;index<records.length;index+=400){
    const batch=db.batch();
    for(const record of records.slice(index,index+400))batch.set(db.doc(`reports/${record.id}`),record.data);
    await batch.commit();
  }
  await db.doc('reports/dashboard-other-town').set({municipalityId:'analytics-b',hidden:false,status:'pending',createdAt:new Date()});
  const first=await getManagementDashboardHandler({auth:{uid:actors.dashboardA.localId},data:{}},{db});
  assert.equal(first.complete,true);
  assert.equal(first.totals.total,2101);
  assert.equal(first.totals.open,1);
  assert.equal(first.totals.over72h,1);
  assert.equal(first.totals.medianResolutionHours,24);
  assert.equal(first.municipalities.length,1);
  assert.equal(first.municipalities[0].municipalityId,'analytics-a');
  assert.equal((await getManagementDashboardHandler({auth:{uid:actors.dashboardA.localId},data:{}},{db})).cached,true);
  for(const data of [{scope:'all'},{municipalityId:'analytics-b'},{provinceId:'06'}])await assert.rejects(getManagementDashboardHandler({auth:{uid:actors.dashboardA.localId},data},{db}),{code:'permission-denied'});
  const other=await getManagementDashboardHandler({auth:{uid:actors.dashboardB.localId},data:{}},{db});
  assert.equal(other.totals.total,1);
  assert.equal(other.municipalities[0].municipalityId,'analytics-b');
  const central=await getManagementDashboardHandler({auth:{uid:actors.admin.localId},data:{scope:'all'}},{db});
  assert.ok(central.totals.total>=2102);
  assert.ok(central.municipalities.some(item=>item.municipalityId==='analytics-a'));
  assert.ok(central.municipalities.some(item=>item.municipalityId==='analytics-b'));
  assert.equal(await readAs('dashboardA','managementDashboardCache/any-id'),403);
});
