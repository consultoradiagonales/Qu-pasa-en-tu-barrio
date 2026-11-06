'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue } = require('firebase-admin/firestore');
const { canManageMunicipality } = require('./management-access');

const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const ASSIGNABLE_STATUSES = new Set(['pending', 'assigned']);

function documentId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 &&
    value !== '.' && value !== '..' && !value.includes('/');
}

/** Revalida permisos, equipo y estado en cada reintento de Firestore. */
async function assignReportTeamHandler(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const { reportId, teamId, expectedVersion } = request.data || {};
  if (!documentId(reportId) || !documentId(teamId) ||
      (expectedVersion !== undefined &&
        (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0))) {
    throw new HttpsError('invalid-argument', 'El reporte, el equipo o la versión no son válidos.');
  }

  const profileRef = db.collection('users').doc(uid);
  const reportRef = db.collection('reports').doc(reportId);
  const teamRef = db.collection('teams').doc(teamId);
  const eventRef = reportRef.collection('assignmentEvents').doc();

  return db.runTransaction(async (transaction) => {
    const [profileSnap, reportSnap, teamSnap] = await transaction.getAll(profileRef, reportRef, teamRef);
    const profile = profileSnap.data();
    if (!profile || profile.disabled === true || !MANAGEMENT_ROLES.has(profile.role)) {
      throw new HttpsError('permission-denied', 'No podés asignar reportes.');
    }
    if (!reportSnap.exists) throw new HttpsError('not-found', 'El reporte no existe.');
    const report = reportSnap.data();
    if (!canManageMunicipality(profile, report.municipalityId)) {
      throw new HttpsError('permission-denied', 'Ese reporte es de otro municipio.');
    }
    if (!teamSnap.exists) throw new HttpsError('not-found', 'El equipo no existe.');
    const team = teamSnap.data();
    if (team.municipalityId !== report.municipalityId || team.active === false) {
      throw new HttpsError('failed-precondition', 'El equipo debe estar activo y pertenecer al municipio.');
    }
    if (!ASSIGNABLE_STATUSES.has(report.status)) {
      throw new HttpsError('failed-precondition', 'El reporte ya está en curso o cerrado, no se puede reasignar.');
    }
    // Los clientes anteriores siguen siendo compatibles. El panel nuevo envía
    // la versión observada y rechaza una reasignación desde una vista obsoleta.
    const version = Number.isSafeInteger(report.assignmentVersion) ? report.assignmentVersion : 0;
    if (expectedVersion !== undefined && expectedVersion !== version) {
      throw new HttpsError('aborted', 'La asignación cambió. Revisá el reporte y volvé a intentar.');
    }
    const now = FieldValue.serverTimestamp();
    transaction.update(reportRef, {
      assignedTeamId: teamId,
      assignedWorkerId: null,
      status: 'assigned',
      assignedAt: now,
      updatedAt: now,
      assignmentVersion: version + 1,
    });
    // Historial privado, escrito sólo por servidor. No habilita acceso vecinal.
    transaction.create(eventRef, {
      municipalityId: report.municipalityId,
      actorId: uid,
      actorRole: profile.role,
      previousTeamId: report.assignedTeamId || null,
      teamId,
      previousStatus: report.status,
      assignmentVersion: version + 1,
      createdAt: now,
    });
    return { ok: true, reportId, teamId, assignmentVersion: version + 1 };
  });
}

module.exports = { assignReportTeamHandler };
