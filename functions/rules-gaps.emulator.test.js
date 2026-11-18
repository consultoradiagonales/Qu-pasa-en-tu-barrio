'use strict';

// QA de brechas en firestore.rules / storage.rules. Solo emuladores locales
// y proyecto demo. Cada caso afirma el comportamiento de las reglas
// corregidas (QA 2026-11-17) y lo etiqueta SEGURO o BRECHA. F1a/F1b:
// la lectura global de perfiles por la gerencia de Diagonales es
// intencional (decision del responsable, 2026-11-17), por eso se espera 200.
const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

const projectId = 'demo-condi-audit';
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST']) {
  assert.match(process.env[key] || '', /^(127\.0\.0\.1|localhost):\d+$/, key);
}
const app = initializeApp({ projectId }, 'rules-gaps-audit');
const db = getFirestore(app);
const fsBase = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${projectId}/databases/(default)/documents`;
const docRoot = fsBase.split('/v1/')[1];
const bucket = `${projectId}.appspot.com`;
const stBase = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${bucket}/o`;
const actors = {};
const findings = [];

function encode(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  if (typeof value === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)])) } };
  return { stringValue: value };
}
const auth = (actor) => ({ Authorization: `Bearer ${actors[actor].idToken}` });

async function getDoc(actor, path) {
  return (await fetch(`${fsBase}/${path}`, { headers: auth(actor) })).status;
}
async function listCol(actor, col) {
  return (await fetch(`${fsBase}/${col}`, { headers: auth(actor) })).status;
}
async function query(actor, collectionId, where) {
  const structuredQuery = { from: [{ collectionId }], ...(where ? { where } : {}) };
  const r = await fetch(`${fsBase}:runQuery`, { method: 'POST', headers: { ...auth(actor), 'Content-Type': 'application/json' }, body: JSON.stringify({ structuredQuery }) });
  return r.status;
}
async function patch(actor, path, values, serverTime = []) {
  const r = await fetch(`${fsBase}:commit`, {
    method: 'POST', headers: { ...auth(actor), 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes: [{
      update: { name: `${docRoot}/${path}`, fields: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, encode(v)])) },
      updateMask: { fieldPaths: Object.keys(values) },
      ...(serverTime.length ? { updateTransforms: serverTime.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) } : {}),
    }] }),
  });
  return r.status;
}
async function upload(actor, path, { contentType = 'image/jpeg', bytes = 4 } = {}) {
  const body = Buffer.alloc(bytes, 0);
  body[0] = 0xff; body[1] = 0xd8;
  const r = await fetch(`${stBase}?uploadType=media&name=${encodeURIComponent(path)}`, {
    method: 'POST', headers: { ...auth(actor), 'Content-Type': contentType }, body,
  });
  return r.status;
}
async function remove(actor, path) {
  return (await fetch(`${stBase}/${encodeURIComponent(path)}`, { method: 'DELETE', headers: auth(actor) })).status;
}
async function seedFile(path) {
  await getStorage(app).bucket(bucket).file(path).save(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), { contentType: 'image/jpeg' });
}
async function download(actor, path) {
  return (await fetch(`${stBase}/${encodeURIComponent(path)}?alt=media`, { headers: auth(actor) })).status;
}

// expectedSecure: codigo que deberia devolver una regla segura.
// actual: codigo observado con la instantanea actual de las reglas.
async function check(id, description, expectedSecure, actual, run, ref) {
  const observed = await run();
  const label = observed === expectedSecure ? 'SEGURO' : 'BRECHA';
  findings.push({ id, description, expectedSecure, observed, label, ref });
  assert.equal(observed, actual, `${id} ${description}: observado ${observed}, registrado ${actual}`);
}

test.before(async () => {
  const people = [
    ['fieldManager', { role: 'field_manager', municipalityId: 'a', organizationId: 'diagonales' }],
    ['fakeFieldManager', { role: 'field_manager', municipalityId: 'b' }],
    ['coordinatorA', { role: 'coordinator', municipalityId: 'a' }],
    ['citizenA', { role: 'citizen', municipalityId: 'a' }],
    ['citizenB', { role: 'citizen', municipalityId: 'b' }],
    ['citizenB2', { role: 'citizen', municipalityId: 'b' }],
    ['mover', { role: 'citizen', municipalityId: 'b', reportsCount: 0 }],
    ['disabledOwner', { role: 'citizen', municipalityId: 'a', disabled: true }],
    ['workerA', { role: 'field_worker', municipalityId: 'a', teamId: 'team-a' }],
    ['workerA2', { role: 'field_worker', municipalityId: 'a', teamId: 'team-a' }],
    ['workerB', { role: 'field_worker', municipalityId: 'b', teamId: 'team-b' }],
    ['workerEmpty', { role: 'field_worker', municipalityId: 'a', teamId: '' }],
  ];
  for (const [name, data] of people) {
    const r = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
    });
    assert.equal(r.status, 200);
    actors[name] = await r.json();
    await db.doc(`users/${actors[name].localId}`).set({ disabled: false, ...data });
  }
  const uid = (n) => actors[n].localId;
  const base = { municipalityId: 'a', userId: uid('citizenA'), hidden: false, photosBefore: [], photosProgress: [], photosAfter: [] };
  const reports = {
    'g-inprog-a': { ...base, status: 'in_progress', assignedTeamId: 'team-a', assignedWorkerId: uid('workerA'), photosBefore: ['https://x/b.jpg'] },
    'g-assigned-a': { ...base, status: 'assigned', assignedTeamId: 'team-a', assignedWorkerId: null },
    'g-resolved-a': { ...base, status: 'resolved', assignedTeamId: 'team-a', assignedWorkerId: uid('workerA') },
    'g-closed-a': { ...base, status: 'closed', assignedTeamId: 'team-a' },
    'g-emptyteam-a': { ...base, status: 'assigned', assignedTeamId: '' },
    'g-pending-a': { ...base, status: 'pending', assignedTeamId: null },
    'g-ready-a': { ...base, status: 'pending', photoUploadStatus: 'ready', photoStoragePath: 'reports/g-ready-a/citizen/photo.jpg', photosReport: ['https://x/p.jpg'] },
    'g-pendphoto-a': { ...base, status: 'pending', photoUploadStatus: 'pending', photoStoragePath: 'reports/g-pendphoto-a/citizen/photo.jpg', photosReport: [] },
    'g-hidden-a': { ...base, status: 'pending', hidden: true, photoUploadStatus: 'pending', photoStoragePath: 'reports/g-hidden-a/citizen/photo.jpg', photosReport: [] },
    'g-pendsize-a': { ...base, status: 'pending', photoUploadStatus: 'pending', photoStoragePath: 'reports/g-pendsize-a/citizen/photo.jpg', photosReport: [] },
    'g-hidden-b': { ...base, municipalityId: 'b', userId: uid('citizenB'), status: 'pending', hidden: true },
    'g-public-b': { ...base, municipalityId: 'b', userId: uid('citizenB'), status: 'pending' },
    'g-disabled-owner': { ...base, userId: uid('disabledOwner'), status: 'pending', photoUploadStatus: 'pending', photoStoragePath: 'reports/g-disabled-owner/citizen/x.jpg', photosReport: [] },
  };
  for (const [id, data] of Object.entries(reports)) await db.doc(`reports/${id}`).set(data);
  await db.doc('reports/g-public-b/comments/c1').set({ reportId: 'g-public-b', userId: uid('citizenB'), displayName: 'V', text: 't', isOfficialResponse: false, hidden: false, flaggedCount: 0, createdAt: new Date() });
  await db.doc('teams/team-b').set({ municipalityId: 'b', active: true });
});

test.after(async () => {
  console.log('\n=== MATRIZ DE CASOS (id | esperado seguro | observado | etiqueta | regla) ===');
  for (const f of findings) console.log(`${f.id} | ${f.expectedSecure} | ${f.observed} | ${f.label} | ${f.ref} | ${f.description}`);
  console.log(`BRECHAS: ${findings.filter((f) => f.label === 'BRECHA').length} / ${findings.length}`);
  await db.terminate();
  await deleteApp(app);
});

const uid = (n) => actors[n].localId;

test('F1 field_manager Diagonales y perfiles de otros municipios', async () => {
  await check('F1a', 'FM Diagonales (muni a) lee users/citizenB (muni b) [intencional]', 200, 200, () => getDoc('fieldManager', `users/${uid('citizenB')}`), 'firestore.rules:26-29,37-41,175');
  await check('F1b', 'FM Diagonales lista users sin filtro [intencional]', 200, 200, () => query('fieldManager', 'users'), 'firestore.rules:175');
  await check('F1c', 'FM Diagonales lee teams de otro municipio', 200, 200, () => getDoc('fieldManager', 'teams/team-b'), 'firestore.rules:199');
});

test('F2 field_manager sin organizationId ya no actua como coordinador local', async () => {
  await check('F2a', 'FM falso (muni b) lee users/citizenB (muni b)', 403, 403, () => getDoc('fakeFieldManager', `users/${uid('citizenB')}`), 'firestore.rules:18-20,37-41');
  await check('F2b', 'FM falso (muni b) lee users/citizenA (muni a)', 403, 403, () => getDoc('fakeFieldManager', `users/${uid('citizenA')}`), 'firestore.rules:37-41');
  await check('F2c', 'FM falso lee reporte oculto de muni b', 403, 403, () => getDoc('fakeFieldManager', 'reports/g-hidden-b'), 'firestore.rules:31-34,54');
  await check('F2d', 'FM falso lee reporte oculto de muni a', 403, 403, () => getDoc('fakeFieldManager', 'reports/g-hidden-a'), 'firestore.rules:31-34');
  await check('F2e', 'FM falso oculta comentario en muni b (moderacion)', 403, 403, () => patch('fakeFieldManager', 'reports/g-public-b/comments/c1', { hidden: true }), 'firestore.rules:63-66,331-333');
  await check('F2f', 'FM falso lista teams (staffFor) de muni b', 403, 403, () => getDoc('fakeFieldManager', 'teams/team-b'), 'firestore.rules:199');
  await check('F2g', 'FM falso (muni b) lee operario de su muni (funcional)', 200, 200, () => getDoc('fakeFieldManager', `users/${uid('workerB')}`), 'firestore.rules:localFieldManagerFor');
  await check('F2h', 'FM falso lista operarios de su muni (funcional)', 200, 200, () => query('fakeFieldManager', 'users', { compositeFilter: { op: 'AND', filters: [
    { fieldFilter: { field: { fieldPath: 'role' }, op: 'EQUAL', value: { stringValue: 'field_worker' } } },
    { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'EQUAL', value: { stringValue: 'b' } } },
  ] } }), 'firestore.rules:localFieldManagerFor');
  await check('F2i', 'FM falso lee operario de otro muni', 403, 403, () => getDoc('fakeFieldManager', `users/${uid('workerA')}`), 'firestore.rules:localFieldManagerFor');
  await check('F2j', 'FM falso lee reporte publico de su muni (funcional)', 200, 200, () => getDoc('fakeFieldManager', 'reports/g-public-b'), 'firestore.rules:canReadReport');
});

test('F3 workerFor: transiciones sobre reporte asignado a otro operario', async () => {
  await check('F3a', 'workerA2 (mismo equipo) resuelve reporte de workerA', 403, 403, () => patch('workerA2', 'reports/g-inprog-a', { status: 'resolved', photosAfter: ['https://x/a.jpg'] }, ['workFinishedAt', 'resolvedAt', 'updatedAt']), 'firestore.rules:271-278');
  await check('F3b', 'workerA2 agrega foto de avance al reporte de workerA', 403, 403, () => patch('workerA2', 'reports/g-inprog-a', { photosProgress: ['https://x/p.jpg'] }, ['updatedAt']), 'firestore.rules:279-289');
  await check('F3c', 'workerA2 inicia asignado poniendo assignedWorkerId=workerA', 403, 403, () => patch('workerA2', 'reports/g-assigned-a', { status: 'in_progress', assignedWorkerId: uid('workerA'), photosBefore: ['https://x/b.jpg'] }, ['workerArrivedAt', 'workStartedAt', 'updatedAt']), 'firestore.rules:263-270');
  await check('F3d', 'workerB (otro muni/equipo) inicia reporte de team-a', 403, 403, () => patch('workerB', 'reports/g-assigned-a', { status: 'in_progress', assignedWorkerId: uid('workerB'), photosBefore: ['https://x/b.jpg'] }, ['workerArrivedAt', 'workStartedAt', 'updatedAt']), 'firestore.rules:42-48');
  await check('F3e', 'workerA reabre reporte resuelto a in_progress', 403, 403, () => patch('workerA', 'reports/g-resolved-a', { status: 'in_progress' }, ['updatedAt']), 'firestore.rules:262-290');
  await check('F3f', 'workerEmpty (teamId vacio) inicia reporte con assignedTeamId vacio', 403, 403, () => patch('workerEmpty', 'reports/g-emptyteam-a', { status: 'in_progress', assignedWorkerId: uid('workerEmpty'), photosBefore: ['https://x/b.jpg'] }, ['workerArrivedAt', 'workStartedAt', 'updatedAt']), 'firestore.rules:45');
  await check('F3g', 'workerA inicia con photosBefore no-URL ([42]) (formato validado)', 403, 403, () => patch('workerA', 'reports/g-assigned-a', { status: 'in_progress', assignedWorkerId: uid('workerA'), photosBefore: [42] }, ['workerArrivedAt', 'workStartedAt', 'updatedAt']), 'firestore.rules:266');
});

test('F4 aislamiento de vecinos entre municipios', async () => {
  await check('F4a', 'citizenB lee reporte publico de muni a', 403, 403, () => getDoc('citizenB', 'reports/g-pending-a'), 'firestore.rules:49-55');
  await check('F4b', 'citizenB2 lee reporte oculto ajeno de su muni b', 403, 403, () => getDoc('citizenB2', 'reports/g-hidden-b'), 'firestore.rules:49-55');
  await check('F4c', 'citizenB consulta reports where municipalityId==a', 403, 403, () => query('citizenB', 'reports', { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'EQUAL', value: { stringValue: 'a' } } }), 'firestore.rules:222');
  await check('F4d', 'citizenB lee users/citizenA', 403, 403, () => getDoc('citizenB', `users/${uid('citizenA')}`), 'firestore.rules:175');
  await check('F4e', 'citizenB lista users de su muni', 403, 403, () => query('citizenB', 'users', { fieldFilter: { field: { fieldPath: 'municipalityId' }, op: 'EQUAL', value: { stringValue: 'b' } } }), 'firestore.rules:175');
  await check('F4f', 'citizenB lee teams/team-b', 403, 403, () => getDoc('citizenB', 'teams/team-b'), 'firestore.rules:199');
  // Por diseno el vecino puede mudarse; se documenta el efecto en el acceso.
  await check('F4g', 'mover (b) cambia su municipalityId a a', 200, 200, () => patch('mover', `users/${uid('mover')}`, { municipalityId: 'a' }), 'firestore.rules:191-192');
  await check('F4i', 'perfil sin reportsCount puede editar displayName (funcional)', 200, 200, () => patch('citizenB2', `users/${uid('citizenB2')}`, { displayName: 'Otro' }), 'firestore.rules:186');
  await check('F4h', 'mover tras mudarse lee reporte publico de muni a (por diseno)', 200, 200, () => getDoc('mover', 'reports/g-pending-a'), 'firestore.rules:51-52');
});

test('S1 Storage: operario sobre reportes cerrados/resueltos o sin equipo', async () => {
  await check('S1a', 'workerA sube "after" a reporte resuelto', 403, 403, () => upload('workerA', 'reports/g-resolved-a/after/late.jpg'), 'storage.rules:31-41,61-62');
  await check('S1b', 'workerA sube "before" a reporte cerrado', 403, 403, () => upload('workerA', 'reports/g-closed-a/before/late.jpg'), 'storage.rules:31-41,61-62');
  await check('S1c', 'workerA2 sube "progress" a reporte de workerA en curso', 403, 403, () => upload('workerA2', 'reports/g-inprog-a/progress/x.jpg'), 'storage.rules:31-37');
  await check('S1d', 'workerEmpty (teamId "") sube a reporte con assignedTeamId ""', 403, 403, () => upload('workerEmpty', 'reports/g-emptyteam-a/before/x.jpg'), 'storage.rules:34-35 (falta size()>0)');
  await check('S1e', 'workerEmpty sube a reporte sin equipo (null)', 403, 403, () => upload('workerEmpty', 'reports/g-pending-a/before/x.jpg'), 'storage.rules:35');
  await check('S1f', 'workerB sube a reporte de team-a', 403, 403, () => upload('workerB', 'reports/g-assigned-a/before/x.jpg'), 'storage.rules:35-36');
  await check('S1g', 'workerA sube "progress" a su reporte en curso (funcional)', 200, 200, () => upload('workerA', 'reports/g-inprog-a/progress/ok.jpg'), 'storage.rules:workerPhaseOpen');
  await check('S1h', 'workerA sube "before" a reporte asignado a su equipo (funcional)', 200, 200, () => upload('workerA', 'reports/g-assigned-a/before/ok.jpg'), 'storage.rules:workerPhaseOpen');
  await check('S1i', 'workerA2 sube "after" a reporte de workerA', 403, 403, () => upload('workerA2', 'reports/g-inprog-a/after/x.jpg'), 'storage.rules:workerPhaseOpen');
});

test('S2 Storage: fotos de vecino', async () => {
  await check('S2a', 'dueno sube foto extra con photoUploadStatus=ready', 403, 403, () => upload('citizenA', 'reports/g-ready-a/citizen/extra.jpg'), 'storage.rules:40');
  await check('S2b', 'dueno sube nombre distinto a photoStoragePath (pending)', 403, 403, () => upload('citizenA', 'reports/g-pendphoto-a/citizen/otra.jpg'), 'storage.rules:40');
  await check('S2c', 'dueno sube a su reporte resuelto', 403, 403, () => upload('citizenA', 'reports/g-resolved-a/citizen/late.jpg'), 'storage.rules:40');
  await check('S2d', 'citizenB sube a reporte de citizenA', 403, 403, () => upload('citizenB', 'reports/g-pending-a/citizen/x.jpg'), 'storage.rules:40');
  await check('S2e', 'dueno deshabilitado sube foto', 403, 403, () => upload('disabledOwner', 'reports/g-disabled-owner/citizen/x.jpg'), 'storage.rules:40 (sin disabled)');
  await check('S2f', 'dueno sube a fase inventada', 403, 403, () => upload('citizenA', 'reports/g-pending-a/otra/x.jpg'), 'storage.rules:39-42');
  await check('S2g', 'citizenB sube al photoStoragePath de citizenA', 403, 403, () => upload('citizenB', 'reports/g-pendphoto-a/citizen/photo.jpg'), 'storage.rules:citizenPhotoPending');
  await check('S2h', 'dueno sube exactamente photoStoragePath pendiente (funcional)', 200, 200, () => upload('citizenA', 'reports/g-pendphoto-a/citizen/photo.jpg'), 'storage.rules:citizenPhotoPending');
  await check('S2i', 'dueno reemplaza la foto ya subida', 403, 403, () => upload('citizenA', 'reports/g-pendphoto-a/citizen/photo.jpg'), 'storage.rules:resource == null');
});

test('S3 Storage: tipo y tamano', async () => {
  await check('S3a', 'text/plain rechazado', 403, 403, () => upload('citizenA', 'reports/g-pendsize-a/citizen/photo.jpg', { contentType: 'text/plain' }), 'storage.rules:45-48');
  await check('S3b', 'image/svg+xml rechazado (riesgo XSS)', 403, 403, () => upload('citizenA', 'reports/g-pendsize-a/citizen/photo.jpg', { contentType: 'image/svg+xml' }), 'storage.rules:47');
  await check('S3c', '8 MB exactos rechazado', 403, 403, () => upload('citizenA', 'reports/g-pendsize-a/citizen/photo.jpg', { bytes: 8 * 1024 * 1024 }), 'storage.rules:46');
  await check('S3d', '8 MB - 1 byte aceptado', 200, 200, () => upload('citizenA', 'reports/g-pendsize-a/citizen/photo.jpg', { bytes: 8 * 1024 * 1024 - 1 }), 'storage.rules:46');
});

test('S4 Storage: lectura de fotos entre municipios', async () => {
  assert.equal(await upload('citizenA', 'reports/g-hidden-a/citizen/photo.jpg'), 200);
  await check('S4a', 'citizenB (muni b) descarga foto de reporte oculto de muni a', 403, 403, () => download('citizenB', 'reports/g-hidden-a/citizen/photo.jpg'), 'storage.rules:read');
  await check('S4b', 'dueno descarga la foto de su reporte oculto (funcional)', 200, 200, () => download('citizenA', 'reports/g-hidden-a/citizen/photo.jpg'), 'storage.rules:read');
  await check('S4c', 'coordinador de muni a descarga foto de oculto (funcional)', 200, 200, () => download('coordinatorA', 'reports/g-hidden-a/citizen/photo.jpg'), 'storage.rules:read');
  await check('S4d', 'FM falso (muni b) descarga foto de oculto de muni a', 403, 403, () => download('fakeFieldManager', 'reports/g-hidden-a/citizen/photo.jpg'), 'storage.rules:read');
});

test('S5 Storage: retiro de evidencia recien subida si falla Firestore', async () => {
  await seedFile('reports/g-resolved-a/after/done.jpg');
  await seedFile('reports/g-inprog-a/before/arrival.jpg');
  await check('S5a', 'workerA2 borra progress de workerA', 403, 403, () => remove('workerA2', 'reports/g-inprog-a/progress/ok.jpg'), 'storage.rules:delete');
  await check('S5b', 'citizenA (dueno del reporte) borra progress', 403, 403, () => remove('citizenA', 'reports/g-inprog-a/progress/ok.jpg'), 'storage.rules:delete');
  await check('S5c', 'workerA borra su foto de llegada (before)', 403, 403, () => remove('workerA', 'reports/g-inprog-a/before/arrival.jpg'), 'storage.rules:delete');
  await check('S5d', 'workerA borra after de reporte resuelto', 403, 403, () => remove('workerA', 'reports/g-resolved-a/after/done.jpg'), 'storage.rules:delete');
  await check('S5e', 'dueno borra foto de vecino', 403, 403, () => remove('citizenA', 'reports/g-pendphoto-a/citizen/photo.jpg'), 'storage.rules:delete');
  await check('S5f', 'workerA (asignado, en curso) retira su progress recien subido', 204, 204, () => remove('workerA', 'reports/g-inprog-a/progress/ok.jpg'), 'storage.rules:delete');
});
