'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
require('./test-helpers/stub-firebase');
const { getManagementDashboardHandler, resolveDashboardScope } = require('./management-dashboard');
const { hasGlobalOperationsAccess } = require('./management-access');

// Doble mínimo con where(==, in), orderBy, select, limit, startAfter y runTransaction.
function makeDb(seed) {
  const data = new Map(Object.entries(seed).map(([k, v]) => [k, { ...v }]));
  const queries = [];
  const snapOf = (id, v) => ({ id, exists: v !== undefined, data: () => (v ? { ...v } : undefined), get: (f) => v?.[f] });
  function query(col, filters = [], lim = Infinity, after = null) {
    return {
      where: (f, op, val) => query(col, [...filters, [f, op, val]], lim, after),
      orderBy: () => query(col, filters, lim, after),
      select: () => query(col, filters, lim, after),
      limit: (n) => query(col, filters, n, after),
      startAfter: (s) => query(col, filters, lim, s.id),
      doc: (id) => ({ path: `${col}/${id}`, get: async () => snapOf(id, data.get(`${col}/${id}`)) }),
      async get() {
        queries.push({ col, filters });
        let docs = [...data.entries()]
          .filter(([k]) => k.startsWith(`${col}/`))
          .map(([k, v]) => [k.slice(col.length + 1), v])
          .filter(([, v]) => filters.every(([f, op, val]) => (op === 'in' ? val.includes(v[f]) : v[f] === val)))
          .sort(([a], [b]) => a.localeCompare(b));
        if (after) docs = docs.filter(([id]) => id > after);
        docs = docs.slice(0, lim).map(([id, v]) => snapOf(id, v));
        return { docs, size: docs.length };
      },
    };
  }
  return {
    data, queries,
    collection: (c) => query(c),
    async runTransaction(fn) {
      return fn({
        get: async (ref) => ref.get(),
        set: (ref, value, opts) => data.set(ref.path, opts?.merge ? { ...(data.get(ref.path) || {}), ...value } : { ...value }),
      });
    },
  };
}

const NOW = new Date('2026-11-17T12:00:00Z');
const USERS = {
  'users/centralAdmin': { role: 'admin', organizationId: 'diagonales' },
  'users/centralGm': { role: 'field_manager', organizationId: 'diagonales' },
  'users/localCoord': { role: 'coordinator', municipalityId: '06001' },
  'users/localAdmin': { role: 'admin', organizationId: 'muni', municipalityId: '06001' },
  'users/worker': { role: 'field_worker', organizationId: 'diagonales', municipalityId: '06001', teamId: 't' },
  'users/citizen': { role: 'citizen', municipalityId: '06001' },
  'users/offGm': { role: 'field_manager', organizationId: 'diagonales', disabled: true },
  'users/fakeOrgCitizen': { role: 'citizen', organizationId: 'diagonales' },
};
const REPORTS = {
  'reports/r1': { hidden: false, municipalityId: '06001', status: 'pending', category: 'lighting' },
  'reports/r2': { hidden: false, municipalityId: 'georef_06001', status: 'assigned', assignedTeamId: 't' },
  'reports/r3': { hidden: false, municipalityId: '14014', status: 'pending' },
  'reports/r4': { hidden: false, municipalityId: 'saladillo', status: 'resolved' },
  'reports/r5': { hidden: true, municipalityId: '06001', status: 'pending' },
};
const call = (db, uid, data) => getManagementDashboardHandler({ auth: uid ? { uid } : undefined, data }, { db, now: NOW });
const freshDb = () => makeDb({ ...USERS, ...REPORTS });

test('hasGlobalOperationsAccess sólo para admin/field_manager de diagonales habilitados', () => {
  assert.equal(hasGlobalOperationsAccess(USERS['users/centralAdmin']), true);
  assert.equal(hasGlobalOperationsAccess(USERS['users/centralGm']), true);
  for (const k of ['localCoord', 'localAdmin', 'worker', 'citizen', 'offGm', 'fakeOrgCitizen']) {
    assert.equal(hasGlobalOperationsAccess(USERS[`users/${k}`]), false, k);
  }
  assert.equal(hasGlobalOperationsAccess(undefined), false);
});

test('gerencia central obtiene el total global de todos los municipios (excluye ocultos)', async () => {
  for (const uid of ['centralAdmin', 'centralGm']) {
    const r = await call(freshDb(), uid, { scope: 'all' });
    assert.equal(r.totals.total, 4, uid);
    assert.deepEqual(r.scope, { municipalityId: null, provinceId: null });
    assert.equal(r.complete, true);
    assert.equal(r.cached, false);
  }
});

test('gerencia central filtra por provincia, incluyendo ids slug conocidos', async () => {
  const r = await call(freshDb(), 'centralGm', { provinceId: '06' });
  assert.equal(r.totals.total, 3); // r1, r2 (alias), r4 (saladillo)
  assert.ok(!r.municipalities.some((m) => m.municipalityId === '14014'));
});

test('coordinación local recibe sólo su municipio (con alias georef) aunque pida otro valor equivalente', async () => {
  const db = freshDb();
  const r = await call(db, 'localCoord', {});
  assert.equal(r.totals.total, 2);
  assert.deepEqual(r.municipalities.map((m) => m.municipalityId).sort(), ['06001', 'georef_06001']);
  const reportQuery = db.queries.find((q) => q.col === 'reports');
  assert.deepEqual(reportQuery.filters.find(([f]) => f === 'municipalityId'), ['municipalityId', 'in', ['06001', 'georef_06001']]);
});

for (const [uid, data] of [
  ['localCoord', { scope: 'all' }], ['localCoord', { provinceId: '06' }], ['localCoord', { municipalityId: '14014' }],
  ['localAdmin', { scope: 'all' }],
  ['worker', {}], ['worker', { scope: 'all' }],
  ['citizen', {}], ['citizen', { scope: 'all' }],
  ['offGm', { scope: 'all' }], ['fakeOrgCitizen', { scope: 'all' }],
  ['ghost', {}], ['ghost', { scope: 'all' }],
]) {
  test(`deniega datos de gestión a ${uid} con ${JSON.stringify(data)} sin consultar reportes`, async () => {
    const db = freshDb();
    await assert.rejects(call(db, uid, data), { code: 'permission-denied' });
    assert.equal(db.queries.filter((q) => q.col === 'reports').length, 0);
  });
}

test('deniega sin sesión y valida argumentos', async () => {
  const db = freshDb();
  await assert.rejects(call(db, null, {}), { code: 'unauthenticated' });
  await assert.rejects(call(db, 'centralGm', { provinceId: '6' }), { code: 'invalid-argument' });
  await assert.rejects(call(db, 'centralGm', { municipalityId: 'a/b' }), { code: 'invalid-argument' });
  await assert.rejects(call(db, 'centralGm', { municipalityId: '06001', provinceId: '06' }), { code: 'invalid-argument' });
});

test('el caché global no se sirve a un usuario local (clave distinta por ámbito)', async () => {
  const db = freshDb();
  const global = await call(db, 'centralGm', { scope: 'all' });
  assert.equal(global.totals.total, 4);
  const local = await call(db, 'localCoord', {});
  assert.equal(local.totals.total, 2);
  assert.equal(local.cached, false);
  const again = await call(db, 'centralGm', { scope: 'all' });
  assert.equal(again.cached, true);
  assert.equal(again.totals.total, 4);
});

test('resolveDashboardScope: request.data null no rompe y queda en el municipio propio', () => {
  assert.deepEqual(resolveDashboardScope(USERS['users/localCoord'], null), { municipalityId: '06001', provinceId: '' });
});
