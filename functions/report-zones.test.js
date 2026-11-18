'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildZones, cellFor, levelFor, reportWeight } = require('./report-zones');

const NOW = Date.parse('2026-11-06T12:00:00Z');
const at = (lat, lng) => ({ lat, lng });

function report(overrides = {}) {
  return {
    status: 'pending',
    category: 'lighting',
    priority: 2,
    location: at(-34.9214, -57.9544),
    createdAt: new Date(NOW - 86400000),
    userId: 'u1',
    localityId: 'centro',
    ...overrides,
  };
}

test('cellFor agrupa puntos cercanos en la misma celda de ~500 m', () => {
  const a = cellFor(at(-34.9214, -57.9544));
  const b = cellFor(at(-34.9212, -57.9541));
  const far = cellFor(at(-34.93, -57.96));
  assert.equal(a.id, b.id);
  assert.notEqual(a.id, far.id);
  const [s, w, n, e] = a.bounds;
  assert.ok(n - s > 0.004 && n - s < 0.005);
  assert.ok(e - w > 0.005 && e - w < 0.006);
});

test('niveles por puntaje y peso por prioridad y antigüedad', () => {
  assert.equal(levelFor(0), 'GREEN');
  assert.equal(levelFor(3), 'YELLOW');
  assert.equal(levelFor(6), 'ORANGE');
  assert.equal(levelFor(10), 'RED');
  const fresh = reportWeight(report({ priority: 5, createdAt: new Date(NOW) }), NOW);
  const old = reportWeight(report({ priority: 5, createdAt: new Date(NOW - 89 * 86400000) }), NOW);
  const low = reportWeight(report({ priority: 1, createdAt: new Date(NOW) }), NOW);
  assert.equal(fresh, 2);
  assert.ok(old < fresh && old >= 1);
  assert.equal(low, 1);
});

test('una celda con muchos reportes urgentes queda roja; los cerrados no suman color', () => {
  const reports = [
    ...Array.from({ length: 6 }, (_, i) => report({ priority: 5, userId: `u${i}`, createdAt: new Date(NOW) })),
    report({ status: 'resolved', location: at(-34.95, -57.98) }),
  ];
  const zones = buildZones(reports, { nowMs: NOW });
  const red = zones.cells.find((c) => c.level === 'RED');
  assert.ok(red);
  assert.equal(red.open, 6);
  assert.equal(red.high, 6);
  assert.equal(red.topCategory, 'lighting');
  const closed = zones.cells.find((c) => c.open === 0);
  assert.equal(closed.level, 'GREEN');
  assert.equal(zones.summary.resolved, 1);
  assert.equal(zones.priorities[0].category, 'lighting');
});

test('análisis de sesgo: localidades silenciosas, reportes sin mapa y fuente única', () => {
  const reports = [
    report({ userId: 'u1' }), report({ userId: 'u1' }), report({ userId: 'u1' }),
    report({ location: { isManualAddress: true, address: 'Calle 1' }, userId: 'u2' }),
  ];
  const residents = [
    { localityId: 'centro', locality: 'Centro' },
    { localityId: 'tolosa', locality: 'Tolosa' },
    { localityId: 'tolosa', locality: 'Tolosa' },
  ];
  const { analysis, cells, summary } = buildZones(reports, { nowMs: NOW, residents });
  assert.equal(summary.manualAddress, 1);
  assert.equal(cells[0].singleSource, true);
  assert.deepEqual(analysis.flags.silentLocalities, [{ name: 'Tolosa', count: 2 }]);
  assert.match(analysis.absent, /Tolosa/);
  assert.equal(analysis.risk, 'Alto');
  assert.match(analysis.assumption, /^Supuesto:/);
  assert.doesNotMatch(analysis.conclusion, /Supuesto/);
  for (const key of ['observed', 'absent', 'filter', 'distortion', 'missing', 'risk', 'riskReason', 'conclusion']) {
    assert.ok(analysis[key], key);
  }
});

test('sin reportes no se afirma que no haya problemas', () => {
  const { cells, analysis } = buildZones([], { nowMs: NOW });
  assert.equal(cells.length, 0);
  assert.equal(analysis.risk, 'Alto');
  assert.match(analysis.conclusion, /No hay evidencia/);
});
