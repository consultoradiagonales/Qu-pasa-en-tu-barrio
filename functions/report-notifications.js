'use strict';

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { createHash } = require('node:crypto');
const { deliverToUsers } = require('./push-delivery');

const REGION = 'southamerica-east1';

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function clean(value, max = 140) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max)
    : '';
}

function notificationForChange(before, after) {
  if (!after || !after.userId) return null;
  const previousStatus = before?.status || 'pending';
  const status = after.status || 'pending';
  const afterPhotos = asArray(after.photosAfter);

  if (status === 'resolved' &&
      (previousStatus !== 'resolved' || afterPhotos.length > asArray(before?.photosAfter).length)) {
    return {
      key: 'resolved',
      type: 'report_resolved',
      title: 'Tu reporte fue resuelto',
      body: 'La cuadrilla cargó una foto del trabajo finalizado.',
      imageUrl: typeof afterPhotos[0] === 'string' ? afterPhotos[0] : null,
    };
  }

  if (previousStatus !== status) {
    if (status === 'assigned') {
      return {
        key: `assigned_${clean(after.assignedTeamId, 80) || 'team'}`,
        type: 'report_assigned',
        title: 'Tu reporte fue asignado',
        body: 'Una cuadrilla fue asignada para revisar el problema.',
        imageUrl: null,
      };
    }
    if (status === 'in_progress') {
      return {
        key: 'in_progress',
        type: 'worker_arrived',
        title: 'La cuadrilla llegó al lugar',
        body: 'El trabajo sobre tu reporte ya está en curso.',
        imageUrl: null,
      };
    }
    if (status === 'rejected') {
      return {
        key: 'rejected',
        type: 'report_rejected',
        title: 'Actualización de tu reporte',
        body: 'El municipio dejó una actualización en el detalle del reporte.',
        imageUrl: null,
      };
    }
  }

  const progressPhotos = asArray(after.photosProgress);
  if (progressPhotos.length > asArray(before?.photosProgress).length) {
    return {
      key: `progress_${progressPhotos.length}`,
      type: 'report_progress',
      title: 'Hay novedades en tu reporte',
      body: 'La cuadrilla cargó una actualización del trabajo.',
      imageUrl: typeof progressPhotos[progressPhotos.length - 1] === 'string'
        ? progressPhotos[progressPhotos.length - 1]
        : null,
    };
  }
  return null;
}

function isInvalidToken(error) {
  return error?.code === 'messaging/registration-token-not-registered' ||
    error?.code === 'messaging/invalid-registration-token';
}

function assignmentChange(before, after) {
  if (!after || after.status !== 'assigned' || !clean(after.assignedTeamId, 128)) {
    return false;
  }
  return before?.status !== 'assigned' ||
    before?.assignedTeamId !== after.assignedTeamId ||
    before?.assignmentVersion !== after.assignmentVersion;
}

function assignmentKey(reportId, version, teamId = '') {
  const digest = createHash('sha256').update(String(reportId)).digest('hex').slice(0, 24);
  if (Number.isSafeInteger(version) && version >= 0) {
    return `field_assignment_${digest}_${version}`;
  }
  // Sin assignmentVersion (reportes legados): la clave incluye el equipo para
  // que una reasignación a otro equipo vuelva a avisar a la gerencia central.
  const teamDigest = createHash('sha256').update(String(teamId)).digest('hex').slice(0, 16);
  return `field_assignment_${digest}_t${teamDigest}`;
}

async function notifyAssignedWorkers(event, database = getFirestore()) {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!assignmentChange(before, after)) return null;

  const teamId = clean(after.assignedTeamId, 128);
  const [teamWorkers, fieldManagers] = await Promise.all([
    database.collection('users').where('teamId', '==', teamId).get(),
    database.collection('users').where('role', '==', 'field_manager').get(),
  ]);
  const recipients = new Map();
  for (const snapshot of [...teamWorkers.docs, ...fieldManagers.docs]) {
    const profile = snapshot.data();
    const isTeamWorker = profile.teamId === teamId && profile.role === 'field_worker';
    const isGlobalManager = profile.role === 'field_manager' &&
      profile.organizationId === 'diagonales';
    if (profile.disabled !== true && (isTeamWorker || isGlobalManager)) {
      recipients.set(snapshot.id, { uid: snapshot.id, fcmToken: profile.fcmToken });
    }
  }
  if (!recipients.size) return { total: 0, pushed: 0, inApp: 0 };

  return deliverToUsers(database, [...recipients.values()], {
    key: assignmentKey(event.params.reportId, after.assignmentVersion, teamId),
    type: 'field_assignment',
    title: 'Nueva tarea asignada',
    body: 'Tenés un nuevo trabajo municipal para revisar.',
    data: {
      reportId: event.params.reportId,
      teamId,
      actionUrl: `/field/task/${event.params.reportId}`,
    },
  });
}

async function notifyReportOwner(event) {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  const change = notificationForChange(before, after);
  if (!change) return null;

  const reportId = event.params.reportId;
  const db = getFirestore();
  const notificationRef = db.collection('notifications').doc(`${reportId}_${change.key}`);
  try {
    await notificationRef.create({
      userId: after.userId,
      reportId,
      type: change.type,
      title: change.title,
      body: change.body,
      imageUrl: change.imageUrl,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (error?.code !== 6 && error?.code !== 'already-exists') throw error;
  }

  const notification = await notificationRef.get();
  if (notification.get('pushSentAt') || notification.get('delivery') === 'unavailable') return null;

  const userRef = db.collection('users').doc(after.userId);
  const user = await userRef.get();
  const token = user.get('fcmToken');
  if (typeof token !== 'string' || !token) {
    await notificationRef.set({ delivery: 'in_app' }, { merge: true });
    return null;
  }

  const message = {
    token,
    notification: { title: change.title, body: change.body },
    data: {
      reportId,
      notificationId: notificationRef.id,
      type: change.type,
      imageUrl: change.imageUrl || '',
    },
    android: {
      collapseKey: notificationRef.id,
      notification: { channelId: 'condi_report_updates' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  if (change.imageUrl) {
    message.notification.imageUrl = change.imageUrl;
    message.apns.fcmOptions = { imageUrl: change.imageUrl };
  }

  try {
    await getMessaging().send(message);
    await notificationRef.set({
      delivery: 'push',
      pushSentAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    if (isInvalidToken(error)) {
      await Promise.all([
        userRef.update({ fcmToken: FieldValue.delete() }),
        notificationRef.set({ delivery: 'in_app', pushError: 'invalid_token' }, { merge: true }),
      ]);
      return null;
    }
    throw error;
  }
  return null;
}

async function notifyReportChange(event) {
  await Promise.all([
    notifyReportOwner(event),
    notifyAssignedWorkers(event),
  ]);
  return null;
}

const reportLifecycleNotifications = onDocumentUpdated(
  { document: 'reports/{reportId}', region: REGION, retry: true },
  notifyReportChange,
);

module.exports = {
  reportLifecycleNotifications,
  notificationForChange,
  isInvalidToken,
  notifyReportOwner,
  notifyAssignedWorkers,
  notifyReportChange,
  assignmentChange,
  assignmentKey,
};
