'use strict';

const { getFirestore } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');
const { deliverToUsers } = require('./push-delivery');

function clean(value, max = 140) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max)
    : '';
}

function workerAssignedKey(reportId, workerId) {
  const rDigest = createHash('sha256').update(String(reportId)).digest('hex').slice(0, 24);
  const wDigest = createHash('sha256').update(String(workerId)).digest('hex').slice(0, 16);
  return `worker_assigned_${rDigest}_${wDigest}`;
}

/**
 * Envía una notificación push al cuadrillero específico (assignedWorkerId)
 * cuando este campo pasa de null/vacío a un UID concreto.
 *
 * Complementa a notifyAssignedWorkers (que avisa a todo el equipo cuando el
 * estado pasa a 'assigned'): esta función avisa al trabajador puntual en el
 * momento en que queda nominalmente asignado — sea por asignación directa del
 * coordinador o como confirmación al iniciar el trabajo.
 */
async function notifyAssignedWorker(event, database = getFirestore()) {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();

  const prevWorker = clean(before?.assignedWorkerId || '', 128) || null;
  const newWorker = clean(after?.assignedWorkerId || '', 128) || null;

  // Solo disparar cuando assignedWorkerId cambia a un valor nuevo y no vacío.
  if (!newWorker || newWorker === prevWorker) return null;

  const reportId = event.params.reportId;
  const key = workerAssignedKey(reportId, newWorker);

  const workerSnap = await database.collection('users').doc(newWorker).get();
  if (!workerSnap.exists) return null;

  const worker = workerSnap.data();
  if (worker.disabled === true) return null;
  const fcmToken = typeof worker.fcmToken === 'string' && worker.fcmToken
    ? worker.fcmToken
    : null;

  return deliverToUsers(
    database,
    [{ uid: newWorker, fcmToken }],
    {
      key,
      type: 'worker_assigned',
      title: 'Se te asignó una tarea',
      body: 'Tenés un trabajo municipal que atender. Abrí la app para ver los detalles.',
      data: {
        reportId,
        actionUrl: `/field/task/${reportId}`,
      },
    },
  );
}

module.exports = {
  notifyAssignedWorker,
  workerAssignedKey,
};
