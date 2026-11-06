'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { aggregate, normalize, promptFor, loadDashboardCohort } = require('./dashboard-ai');

test('La IA rechaza una cohorte truncada antes de generar un informe', async () => {
  const calls = [];
  let count = 1000;
  const query = {
    where(...args) { calls.push(args); return this; },
    limit(value) { calls.push(['limit', value]); return this; },
    async get() { return { docs: Array.from({ length: count }, () => doc({ status: 'pending' })) }; },
  };
  const database = { collection(name) { assert.equal(name, 'reports'); return query; } };
  const since = new Date('2026-10-01T00:00:00Z');
  assert.equal((await loadDashboardCohort(database, 'municipio-a', since)).length, 1000);
  assert.deepEqual(calls[0], ['municipalityId', '==', 'municipio-a']);
  assert.deepEqual(calls[2], ['limit', 1001]);
  count = 1001;
  await assert.rejects(loadDashboardCohort(database, 'municipio-a', since), { code: 'failed-precondition' });
});

function timestamp(value) {
  return { toDate: () => new Date(value) };
}

function doc(data) {
  return { data: () => data };
}

test('Dashboard aggregation supplies operational and spatial counts without personal data or coordinates', () => {
  const now = new Date('2026-10-14T12:00:00Z');
  const result = aggregate([
    doc({
      userId: 'private-user', title: 'Texto privado', description: 'No enviar',
      status: 'pending', category: 'garbage', priority: 5, supportCount: 4,
      createdAt: timestamp('2026-10-10T08:00:00Z'),
      location: { lat: -35.63841, lng: -59.77791 },
    }),
    doc({
      userId: 'another-user', status: 'in_progress', category: 'garbage', priority: 3, supportCount: 1,
      title: 'Bache',
      createdAt: timestamp('2026-10-13T10:00:00Z'),
      location: { lat: -35.63849, lng: -59.77799 },
    }),
    doc({
      status: 'resolved', category: 'lighting', priority: 2, supportCount: 0,
      title: 'Agua estancada',
      createdAt: timestamp('2026-10-08T10:00:00Z'),
      resolvedAt: timestamp('2026-10-09T10:00:00Z'),
      location: { lat: -35.651, lng: -59.78 },
    }),
  ], now);

  assert.equal(result.total, 3);
  assert.equal(result.operational.pendingWithoutTeam, 1);
  assert.equal(result.operational.activeInField, 1);
  assert.equal(result.operational.highPriorityOpen, 1);
  assert.equal(result.aging.over72h, 1);
  assert.equal(result.averageResolutionHours, 24);
  assert.equal(result.hotspots[0].reports, 2);
  assert.equal(result.hotspots[0].leadingCategory, 'garbage');
  assert.deepEqual(result.issueTypes, { pothole: 1, standing_water: 1 });
  const serialized = JSON.stringify(result);
  assert.ok(!serialized.includes('private-user'));
  assert.ok(!serialized.includes('Texto privado'));
  assert.ok(!serialized.includes('-35.638'));
});

test('Prompt retains aggregate safeguards and no exact location fields', () => {
  const data = aggregate([doc({
    status: 'pending', category: 'garbage', priority: 4, supportCount: 2,
    title: 'Venta de droga', userId: 'uid-secret', description: 'dato privado',
    createdAt: timestamp('2026-10-14T08:00:00Z'),
    location: { lat: -35.6, lng: -59.7 },
  })], new Date('2026-10-14T12:00:00Z'));
  const prompt = promptFor(data, 30);
  assert.ok(prompt.includes('sugerencias para una decisión humana'));
  assert.ok(prompt.includes('"drug_dealing":1'));
  assert.ok(!prompt.includes('Venta de droga'));
  assert.ok(!prompt.includes('uid-secret'));
  assert.ok(!prompt.includes('dato privado'));
  assert.ok(!prompt.includes('"lat"'));
  assert.ok(!prompt.includes('"lng"'));
});

test('Issue type aggregation only counts known preset titles, including new reports', () => {
  const titles = [
    'Bache',
    'Luminaria apagada',
    'Basura acumulada',
    'Vereda rota',
    'Árbol o espacio verde',
    'Semáforo o señal',
    'Agua estancada',
    'Plagas',
    '  Ruidos molestos  ',
    'Venta de droga',
    'Picada motos o autos',
    'Robos reiterados',
    'Calle anegada',
    'Disturbios',
    'Otro',
    'Texto libre privado que no debe agregarse',
  ];
  const result = aggregate(titles.map((title) => doc({
    title,
    status: 'pending',
    category: 'custom private category',
  })));

  assert.deepEqual(result.issueTypes, {
    disturbances: 1,
    drug_dealing: 1,
    flooded_street: 1,
    light: 1,
    noise: 1,
    other: 1,
    pests: 1,
    pothole: 1,
    repeated_theft: 1,
    sidewalk: 1,
    standing_water: 1,
    street_racing: 1,
    traffic: 1,
    trash: 1,
    tree: 1,
  });
  assert.deepEqual(result.categories, { other: titles.length });
  const serialized = JSON.stringify(result);
  assert.ok(!serialized.includes('Texto libre privado'));
  assert.ok(!serialized.includes('custom private category'));
});

test('AI normalization requires and sanitizes decision strategies', () => {
  const result = normalize({
    summary: 'Resumen operativo',
    priorities: [{ title: 'Prioridad', evidence: 'Dato', action: 'Acción' }],
    strategies: [{
      title: 'Reforzar guardia', objective: 'Bajar espera', action: 'Reasignar una cuadrilla', resourceImpact: 'Medio',
    }],
    risks: ['Acumulación'],
    questions: ['¿Hay disponibilidad?'],
  });
  assert.equal(result.strategies[0].resourceImpact, 'Medio');
  assert.throws(() => normalize({ summary: 'x', priorities: [], risks: [], questions: [] }), /invalid_response/);
});
