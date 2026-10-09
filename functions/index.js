'use strict';

const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const {createHash} = require('node:crypto');
const {countable, analyticsDelta} = require('./analytics');

initializeApp();
const db = getFirestore();

/** Assignments are atomic and authorized on the server. */
exports.assignReportTeam = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Iniciá sesión.');

  const {reportId, teamId} = request.data || {};
  if (typeof reportId !== 'string' || !reportId || reportId.includes('/') ||
      typeof teamId !== 'string' || !teamId || teamId.includes('/')) {
    throw new HttpsError('invalid-argument', 'Reporte o equipo inválido.');
  }

  const actor = await db.collection('users').doc(uid).get();
  const actorData = actor.data();
  if (!actor.exists || actorData.disabled ||
      !['coordinator', 'admin'].includes(actorData.role)) {
    throw new HttpsError('permission-denied', 'No tenés permiso para asignar.');
  }

  const reportRef = db.collection('reports').doc(reportId);
  const teamRef = db.collection('teams').doc(teamId);
  await db.runTransaction(async (tx) => {
    const [report, team] = await Promise.all([tx.get(reportRef), tx.get(teamRef)]);
    if (!report.exists) throw new HttpsError('not-found', 'Reporte no encontrado.');
    if (!team.exists || team.get('active') !== true) {
      throw new HttpsError('failed-precondition', 'Equipo no disponible.');
    }
    const municipalityId = report.get('municipalityId');
    if (!municipalityId || team.get('municipalityId') !== municipalityId ||
        (actorData.role !== 'admin' && actorData.municipalityId !== municipalityId)) {
      throw new HttpsError('permission-denied', 'Municipio incorrecto.');
    }
    if (!['pending', 'assigned'].includes(report.get('status'))) {
      throw new HttpsError('failed-precondition', 'El reporte ya está en curso o cerrado.');
    }
    if (report.get('assignedTeamId') === teamId && report.get('status') === 'assigned') return;

    tx.update(reportRef, {
      status: 'assigned',
      assignedTeamId: teamId,
      assignedWorkerId: null,
      assignedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

async function notify(userId, type, reportId, title, body, eventId) {
  if (!userId) return;
  const id = `${eventId}_${userId}`;
  const notification = db.collection('notifications').doc(id);
  try {
    await notification.create({
      userId, type, reportId, title, body, read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (error.code === 6 || error.code === 'already-exists') return;
    throw error;
  }

  const user = await db.collection('users').doc(userId).get();
  const token = user.get('fcmToken');
  if (typeof token !== 'string' || !token) return;
  try {
    await getMessaging().send({
      token,
      notification: {title, body},
      data: {reportId, type, notificationId: id},
    });
  } catch (error) {
    logger.warn('No se pudo enviar push', {userId, code: error.code});
    if (['messaging/registration-token-not-registered',
      'messaging/invalid-registration-token'].includes(error.code)) {
      await user.ref.update({fcmToken: FieldValue.delete()});
    }
  }
}

exports.onReportCreated = onDocumentCreated('reports/{reportId}', async (event) => {
  const report = event.data?.data();
  if (!report || !report.municipalityId || report.hidden === true) return;
  const coordinators = await db.collection('users')
      .where('municipalityId', '==', report.municipalityId)
      .where('role', '==', 'coordinator').get();
  await Promise.all(coordinators.docs.filter((doc) => !doc.get('disabled')).map((doc) =>
    notify(doc.id, 'new_report', event.params.reportId,
        'Nuevo reporte en tu municipio', report.title || 'Revisá el reporte', event.id)));
});

exports.onReportStatusChanged = onDocumentUpdated('reports/{reportId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || after.hidden === true) return;
  const reportId = event.params.reportId;
  const statusChanged = before.status !== after.status;
  const teamChanged = before.assignedTeamId !== after.assignedTeamId;

  if (after.status === 'assigned' && (statusChanged || teamChanged)) {
    const recipients = new Set();
    if (after.userId) recipients.add(after.userId);
    if (after.assignedTeamId) {
      const workers = await db.collection('users')
          .where('municipalityId', '==', after.municipalityId)
          .where('teamId', '==', after.assignedTeamId)
          .where('role', '==', 'field_worker').get();
      workers.docs.filter((doc) => !doc.get('disabled')).forEach((doc) => recipients.add(doc.id));
    }
    await Promise.all([...recipients].map((uid) =>
      notify(uid, 'report_assigned', reportId, 'Reporte asignado',
          after.title || 'Hay una nueva tarea', event.id)));
  } else if (statusChanged && after.status === 'in_progress') {
    await notify(after.userId, 'worker_arrived', reportId,
        'El equipo llegó al lugar', after.title || 'Tu reporte está en curso', event.id);
  } else if (statusChanged && after.status === 'resolved') {
    await notify(after.userId, 'report_resolved', reportId,
        'Reporte resuelto', 'Mirá las fotos del antes y después y calificá el trabajo.', event.id);
  }
});

/** Contadores por municipio para el tablero, idempotentes ante reintentos. */
exports.onReportAnalytics = onDocumentWritten('reports/{reportId}', async (event) => {
  const before = countable(event.data?.before.exists ? event.data.before.data() : null);
  const after = countable(event.data?.after.exists ? event.data.after.data() : null);
  if (!before && !after) return;
  const eventKey = createHash('sha256').update(event.id).digest('hex');
  const ledger = db.collection('_analyticsEvents').doc(eventKey);
  await db.runTransaction(async (tx) => {
    if ((await tx.get(ledger)).exists) return;
    const municipalities = new Set([before?.municipalityId, after?.municipalityId].filter(Boolean));
    for (const municipalityId of municipalities) {
      const delta = analyticsDelta(
          before?.municipalityId === municipalityId ? before : null,
          after?.municipalityId === municipalityId ? after : null);
      const patch = {updatedAt: FieldValue.serverTimestamp()};
      for (const [key, value] of Object.entries(delta)) {
        if (!value) continue;
        if (key.startsWith('statusCounts.')) {
          patch.statusCounts ??= {};
          patch.statusCounts[key.slice('statusCounts.'.length)] = FieldValue.increment(value);
        } else if (key.startsWith('categoryCounts.')) {
          patch.categoryCounts ??= {};
          patch.categoryCounts[key.slice('categoryCounts.'.length)] = FieldValue.increment(value);
        } else {
          patch[key] = FieldValue.increment(value);
        }
      }
      if (Object.keys(patch).length > 1) {
        tx.set(db.collection('municipalityStats').doc(municipalityId), patch, {merge: true});
      }
    }
    tx.create(ledger, {reportId: event.params.reportId, createdAt: FieldValue.serverTimestamp()});
  });
});
