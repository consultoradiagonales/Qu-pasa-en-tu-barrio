'use strict';

// Sólo emuladores locales y proyecto demo: nunca usa credenciales productivas.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { assignReportTeamHandler } = require('./report-assignment');
const { getManagementDashboardHandler } = require('./management-dashboard');

const projectId = 'demo-condi-audit';
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
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
  const response = await fetch(`${base}:commit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actors[actor].idToken}` },
    body: JSON.stringify({ writes: [{
      update: { name: `${base.split('/v1/')[1]}/${path}`, fields: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, encode(v)])) },
      updateMask: { fieldPaths: Object.keys(values) },
      ...(serverTime ? { updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }] } : {}),
    }] }),
  });
  return { status: response.status, body: await response.json() };
}

async function readAs(actor, path) {
  const response = await fetch(`${base}/${path}`, { headers: { Authorization: `Bearer ${actors[actor].idToken}` } });
  return response.status;
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
    ['schema', 'citizen', 'a', false], ['quota', 'citizen', 'a', false],
    ['localAdminA', 'admin', 'a', false], ['localAdminB', 'admin', 'b', false],
    ['dashboardA', 'coordinator', 'analytics-a', false], ['dashboardB', 'admin', 'analytics-b', false],
  ]) {
    const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
    });
    assert.equal(response.status, 200);
    actors[name] = await response.json();
    await db.collection('users').doc(actors[name].localId).set({ role, municipalityId, disabled, ...(name==='admin'?{organizationId:'diagonales'}:{}) });
  }
  await db.doc('reports/case-a').set({ municipalityId: 'a', userId: actors.citizenA.localId, hidden: false, status: 'pending' });
  await db.doc('reports/private-a').set({ municipalityId: 'a', userId: actors.coordinatorA.localId, hidden: true, status: 'pending' });
  await db.doc('reports/case-b').set({ municipalityId:'b', userId:actors.citizenB.localId, hidden:false, status:'pending', flaggedCount:0 });
  await db.doc('reports/case-a/comments/existing').set(comment());
  for (const id of ['team-a', 'team-a2']) await db.doc(`teams/${id}`).set({ municipalityId: 'a', active: true });
  await db.doc('teams/team-b').set({ municipalityId: 'b', active: true });
  await db.doc('teams/team-inactive').set({ municipalityId: 'a', active: false });
  for (const municipalityId of ['a', 'b']) {
    await db.doc(`weatherAlerts/alert-${municipalityId}`).set({ municipalityId, createdAt: new Date() });
  }
});

test.after(async () => { await db.terminate(); await deleteApp(app); });

test('comentarios: acepta vecino del ámbito y rechaza otro municipio, padre ausente, caso privado y cuenta deshabilitada', async () => {
  assert.equal((await writeAs('citizenA', 'reports/case-a/comments/allowed', comment())).status, 200);
  for (const [actor, reportId] of [['citizenB', 'case-a'], ['citizenA', 'missing'], ['citizenA', 'private-a'], ['disabled', 'case-a']]) {
    assert.equal((await writeAs(actor, `reports/${reportId}/comments/denied-${actor}`, comment({ reportId, userId: actors[actor].localId }))).status, 403);
  }
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
