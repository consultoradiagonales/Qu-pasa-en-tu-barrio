import test from 'node:test';
import assert from 'node:assert/strict';
import {
  reportStatusLabel,
  matchesReportStatus,
  reportResolutionTime,
} from '../../web/admin/report-status.js';

const NOW = Date.parse('2026-11-10T15:00:00Z');
const DAY = 86400000;

test('las etiquetas distinguen los grupos del resumen de los estados individuales', () => {
  assert.equal(reportStatusLabel('open'), 'Abiertos');
  assert.equal(reportStatusLabel('unassigned'), 'Sin asignar');
  assert.equal(reportStatusLabel('field'), 'En campo');
  assert.equal(reportStatusLabel('resolved_week'), 'Resueltos 7 días');
  assert.equal(reportStatusLabel('resolution'), 'Con tiempo de resolución');
  assert.equal(reportStatusLabel('pending'), 'Pendientes');
  assert.equal(reportStatusLabel('in_progress'), 'En curso');
  assert.equal(reportStatusLabel('all'), 'Todos los estados');
  assert.equal(reportStatusLabel('toString'), 'Todos los estados');
});

test('abiertos incluye estados activos y desconocidos, igual que el agregador completo', () => {
  for (const status of ['pending', 'assigned', 'in_progress', 'legacy', undefined]) {
    assert.equal(matchesReportStatus({ status }, 'open', NOW), true, String(status));
  }
  for (const status of ['resolved', 'closed', 'rejected']) {
    assert.equal(matchesReportStatus({ status }, 'open', NOW), false, status);
  }
});

test('sin asignar nunca incluye casos terminales y usa la misma condición de equipo que el backend', () => {
  assert.equal(matchesReportStatus({ status: 'pending' }, 'unassigned', NOW), true);
  assert.equal(matchesReportStatus({ status: 'legacy', assignedTeamId: null }, 'unassigned', NOW), true);
  assert.equal(matchesReportStatus({ status: 'pending', assignedTeamId: '' }, 'unassigned', NOW), true);
  assert.equal(matchesReportStatus({ status: 'pending', assignedTeamId: 'equipo-01' }, 'unassigned', NOW), false);
  assert.equal(matchesReportStatus({ status: 'pending', assignedTeamId: ' ' }, 'unassigned', NOW), false);
  for (const status of ['resolved', 'closed', 'rejected']) {
    assert.equal(matchesReportStatus({ status, assignedTeamId: null }, 'unassigned', NOW), false);
  }
});

test('en campo reúne asignados y en curso, sin depender de tener un equipo cargado', () => {
  for (const status of ['assigned', 'in_progress']) {
    assert.equal(matchesReportStatus({ status }, 'field', NOW), true);
  }
  for (const status of ['pending', 'resolved', 'closed', 'rejected', 'legacy']) {
    assert.equal(matchesReportStatus({ status, assignedTeamId: 'equipo-01' }, 'field', NOW), false);
  }
});

test('cada estado individual devuelve únicamente sus reportes', () => {
  const statuses = ['pending', 'assigned', 'in_progress', 'resolved', 'closed', 'rejected'];
  for (const filter of statuses) {
    for (const status of statuses) {
      assert.equal(matchesReportStatus({ status }, filter, NOW), status === filter, `${filter}/${status}`);
    }
  }
});

test('la semana de resolución incluye ambos límites y excluye futuros y casos anteriores', () => {
  for (const status of ['resolved', 'closed']) {
    assert.equal(matchesReportStatus({ status, resolvedAt: NOW - 7 * DAY }, 'resolved_week', NOW), true);
    assert.equal(matchesReportStatus({ status, resolvedAt: NOW }, 'resolved_week', NOW), true);
    assert.equal(matchesReportStatus({ status, resolvedAt: NOW - 7 * DAY - 1 }, 'resolved_week', NOW), false);
    assert.equal(matchesReportStatus({ status, resolvedAt: NOW + 1 }, 'resolved_week', NOW), false);
  }
  assert.equal(matchesReportStatus({ status: 'pending', resolvedAt: NOW }, 'resolved_week', NOW), false);
  assert.equal(matchesReportStatus({ status: 'rejected', resolvedAt: NOW }, 'resolved_week', NOW), false);
});

test('resueltos de la semana usa la fecha de resolución, no la de creación', () => {
  assert.equal(matchesReportStatus({
    status: 'resolved', createdAt: NOW - 300 * DAY, workFinishedAt: new Date(NOW - DAY),
  }, 'resolved_week', NOW), true);
  assert.equal(matchesReportStatus({
    status: 'resolved', createdAt: NOW - DAY, resolvedAt: NOW - 8 * DAY,
  }, 'resolved_week', NOW), false);
});

test('la fecha de resolución acepta las representaciones utilizadas por clientes y Firestore', () => {
  const examples = [
    new Date(NOW),
    NOW,
    new Date(NOW).toISOString(),
    { toMillis: () => NOW },
    { toDate: () => new Date(NOW) },
  ];
  for (const resolvedAt of examples) {
    assert.equal(reportResolutionTime({ resolvedAt }), NOW);
    assert.equal(matchesReportStatus({ status: 'resolved', resolvedAt }, 'resolved_week', NOW), true);
  }
});

test('fallback de fecha funciona ante ausencia, dato inválido y Timestamp que falla', () => {
  for (const resolvedAt of [undefined, null, '', 'no es fecha', new Date(NaN), NaN, Infinity, { toMillis: () => { throw new Error('invalid'); } }]) {
    assert.equal(reportResolutionTime({ resolvedAt, workFinishedAt: NOW }), NOW);
  }
  assert.equal(reportResolutionTime({ resolvedAt: NOW - DAY, workFinishedAt: NOW }), NOW - DAY);
  assert.equal(reportResolutionTime({ resolvedAt: 0, workFinishedAt: NOW }), 0);
  assert.equal(reportResolutionTime({}), null);
});

test('tiempo de resolución exige fechas coherentes y no incluye pendientes ni rechazos', () => {
  assert.equal(matchesReportStatus({ status: 'resolved', createdAt: NOW - DAY, resolvedAt: NOW }, 'resolution', NOW), true);
  assert.equal(matchesReportStatus({ status: 'closed', createdAt: NOW, resolvedAt: NOW }, 'resolution', NOW), true);
  assert.equal(matchesReportStatus({ status: 'closed', createdAt: NOW, resolvedAt: NOW - 1 }, 'resolution', NOW), false);
  assert.equal(matchesReportStatus({ status: 'resolved', createdAt: NOW, resolvedAt: NOW + 1 }, 'resolution', NOW), false);
  assert.equal(matchesReportStatus({ status: 'resolved', resolvedAt: NOW }, 'resolution', NOW), false);
  assert.equal(matchesReportStatus({ status: 'resolved', createdAt: 'inválida', resolvedAt: NOW }, 'resolution', NOW), false);
  assert.equal(matchesReportStatus({ status: 'pending', createdAt: NOW - DAY, resolvedAt: NOW }, 'resolution', NOW), false);
  assert.equal(matchesReportStatus({ status: 'rejected', createdAt: NOW - DAY, resolvedAt: NOW }, 'resolution', NOW), false);
});

test('el instante cero y duraciones cero son fechas válidas', () => {
  assert.equal(matchesReportStatus({ status: 'resolved', createdAt: 0, resolvedAt: 0 }, 'resolution', 0), true);
  assert.equal(matchesReportStatus({ status: 'closed', resolvedAt: 0 }, 'resolved_week', 0), true);
  assert.equal(matchesReportStatus({ status: 'resolved', createdAt: -DAY, workFinishedAt: 0 }, 'resolution', 0), true);
});

test('un reloj inválido no produce coincidencias temporales y all no restringe estados', () => {
  const report = { status: 'resolved', createdAt: NOW - DAY, resolvedAt: NOW };
  assert.equal(matchesReportStatus(report, 'resolved_week', NaN), false);
  assert.equal(matchesReportStatus(report, 'resolution', NaN), false);
  assert.equal(matchesReportStatus(report, 'all', NOW), true);
  assert.equal(matchesReportStatus({ status: 'legacy' }, 'all', NOW), true);
  assert.equal(matchesReportStatus(report, 'toString', NOW), true);
});
