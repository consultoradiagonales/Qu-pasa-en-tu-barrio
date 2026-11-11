const CLOSED_STATUSES = new Set(['resolved', 'closed', 'rejected']);
const RESOLVED_STATUSES = new Set(['resolved', 'closed']);
const STATUS_LABELS = Object.freeze({
  all: 'Todos los estados',
  open: 'Abiertos',
  unassigned: 'Sin asignar',
  field: 'En campo',
  resolved_week: 'Resueltos 7 días',
  resolution: 'Con tiempo de resolución',
  pending: 'Pendientes',
  assigned: 'Asignados',
  in_progress: 'En curso',
  resolved: 'Resueltos',
  rejected: 'Rechazados',
  closed: 'Cerrados',
});

function timestampMillis(value) {
  if (value == null) return null;
  try {
    let millis;
    if (typeof value.toMillis === 'function') millis = value.toMillis();
    else if (typeof value.toDate === 'function') millis = value.toDate()?.getTime?.();
    else if (value instanceof Date) millis = value.getTime();
    else if (typeof value === 'number') millis = value;
    else if (typeof value === 'string' && value.trim()) millis = Date.parse(value);
    return Number.isFinite(millis) ? millis : null;
  } catch {
    return null;
  }
}

export function reportStatusLabel(filter) {
  return Object.hasOwn(STATUS_LABELS, filter) ? STATUS_LABELS[filter] : STATUS_LABELS.all;
}

// Devuelve la fecha de resolución en milisegundos, no una duración.
// Un resolvedAt ausente o inválido permite usar la fecha de fin del trabajo.
export function reportResolutionTime(report) {
  return timestampMillis(report?.resolvedAt) ?? timestampMillis(report?.workFinishedAt);
}

export function matchesReportStatus(report, filter, now = Date.now()) {
  const status = report?.status;
  if (filter === 'open') return !CLOSED_STATUSES.has(status);
  if (filter === 'unassigned') return !CLOSED_STATUSES.has(status) && !report?.assignedTeamId;
  if (filter === 'field') return status === 'assigned' || status === 'in_progress';
  if (filter === 'resolved_week' || filter === 'resolution') {
    if (!RESOLVED_STATUSES.has(status)) return false;
    const resolved = reportResolutionTime(report);
    const cutoff = timestampMillis(now);
    if (resolved === null || cutoff === null || resolved > cutoff) return false;
    if (filter === 'resolved_week') return resolved >= cutoff - 7 * 86400000;
    const created = timestampMillis(report?.createdAt);
    return created !== null && resolved >= created;
  }
  if (Object.hasOwn(STATUS_LABELS, filter) && filter !== 'all') return status === filter;
  return true;
}
