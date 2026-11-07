'use strict';

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

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

const reportLifecycleNotifications = onDocumentUpdated(
  { document: 'reports/{reportId}', region: REGION, retry: true },
  notifyReportOwner,
);

module.exports = {
  reportLifecycleNotifications,
  notificationForChange,
  isInvalidToken,
  notifyReportOwner,
};
