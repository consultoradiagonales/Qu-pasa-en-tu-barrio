'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

const REGION = 'southamerica-east1';
const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const CLOSED_STATUSES = new Set(['resolved', 'closed', 'rejected']);

function cleanMessage(value, max = 280) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    .replace(/https?:\/\/\S+/gi, '[enlace omitido]')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function validId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,80}$/.test(value);
}

function validReportId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 180 && !value.includes('/');
}

function canManage(profile, report) {
  if (!profile || profile.disabled === true || !MANAGEMENT_ROLES.has(profile.role)) return false;
  return profile.role === 'admin' ||
    (typeof profile.municipalityId === 'string' && profile.municipalityId === report.municipalityId);
}

function evidenceFor(report) {
  const after = Array.isArray(report.photosAfter) ? report.photosAfter : [];
  const progress = Array.isArray(report.photosProgress) ? report.photosProgress : [];
  const candidate = after[0] || progress[progress.length - 1] || null;
  return typeof candidate === 'string' && /^https:\/\//i.test(candidate) ? candidate : null;
}

function isInvalidToken(error) {
  return error?.code === 'messaging/registration-token-not-registered' ||
    error?.code === 'messaging/invalid-registration-token';
}

async function getAuthorizedReport(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const reportId = request.data?.reportId;
  if (!validReportId(reportId)) throw new HttpsError('invalid-argument', 'El reporte no es válido.');

  const db = getFirestore();
  const [profileSnap, reportSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('reports').doc(reportId).get(),
  ]);
  if (!profileSnap.exists) throw new HttpsError('permission-denied', 'Tu usuario no tiene perfil.');
  if (!reportSnap.exists) throw new HttpsError('not-found', 'El reporte no existe.');
  const profile = profileSnap.data();
  const report = reportSnap.data();
  if (!canManage(profile, report)) {
    throw new HttpsError('permission-denied', 'No podés gestionar este reporte.');
  }
  return { db, uid, reportId, reportRef: reportSnap.ref, report };
}

async function setReportPriorityHandler(request) {
  const { reportRef, reportId, report } = await getAuthorizedReport(request);
  const priority = Number(request.data?.priority);
  if (!Number.isInteger(priority) || priority < 1 || priority > 5) {
    throw new HttpsError('invalid-argument', 'La prioridad debe ser un número entre 1 y 5.');
  }
  if (CLOSED_STATUSES.has(report.status)) {
    throw new HttpsError('failed-precondition', 'No se puede cambiar la prioridad de un reporte cerrado.');
  }
  await reportRef.update({ priority, updatedAt: FieldValue.serverTimestamp() });
  return { ok: true, reportId, priority };
}

async function sendReportUpdateHandler(request) {
  const { db, reportId, report } = await getAuthorizedReport(request);
  const message = cleanMessage(request.data?.message);
  const requestId = request.data?.requestId;
  if (message.length < 3) {
    throw new HttpsError('invalid-argument', 'Escribí una actualización de al menos 3 caracteres.');
  }
  if (!validId(requestId)) {
    throw new HttpsError('invalid-argument', 'La solicitud de notificación no es válida.');
  }
  if (typeof report.userId !== 'string' || !report.userId) {
    throw new HttpsError('failed-precondition', 'El reporte no tiene destinatario.');
  }

  const imageUrl = evidenceFor(report);
  const notificationRef = db.collection('notifications').doc(`${reportId}_manual_${requestId}`);
  let notification = await notificationRef.get();
  if (!notification.exists) {
    try {
      await notificationRef.create({
        userId: report.userId,
        reportId,
        type: 'municipality_update',
        title: 'Actualización de tu reporte',
        body: message,
        imageUrl,
        read: false,
        delivery: 'pending',
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (error?.code !== 6 && error?.code !== 'already-exists') throw error;
    }
    notification = await notificationRef.get();
  }

  const existingDelivery = notification.get('delivery');
  if (notification.get('pushSentAt') || ['in_app', 'unavailable'].includes(existingDelivery)) {
    return { ok: true, reportId, notificationId: notificationRef.id, delivery: existingDelivery || 'push', imageAttached: Boolean(imageUrl) };
  }

  const userRef = db.collection('users').doc(report.userId);
  const user = await userRef.get();
  const token = user.get('fcmToken');
  if (typeof token !== 'string' || !token) {
    await notificationRef.set({ delivery: 'in_app' }, { merge: true });
    return { ok: true, reportId, notificationId: notificationRef.id, delivery: 'in_app', imageAttached: Boolean(imageUrl) };
  }

  const push = {
    token,
    notification: { title: 'Actualización de tu reporte', body: message },
    data: {
      reportId,
      notificationId: notificationRef.id,
      type: 'municipality_update',
      imageUrl: imageUrl || '',
    },
    android: {
      collapseKey: notificationRef.id,
      notification: { channelId: 'condi_report_updates' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  if (imageUrl) {
    push.notification.imageUrl = imageUrl;
    push.apns.fcmOptions = { imageUrl };
  }

  try {
    await getMessaging().send(push);
    await notificationRef.set({ delivery: 'push', pushSentAt: FieldValue.serverTimestamp() }, { merge: true });
    return { ok: true, reportId, notificationId: notificationRef.id, delivery: 'push', imageAttached: Boolean(imageUrl) };
  } catch (error) {
    if (isInvalidToken(error)) {
      await Promise.all([
        userRef.update({ fcmToken: FieldValue.delete() }),
        notificationRef.set({ delivery: 'in_app', pushError: 'invalid_token' }, { merge: true }),
      ]);
      return { ok: true, reportId, notificationId: notificationRef.id, delivery: 'in_app', imageAttached: Boolean(imageUrl) };
    }
    // La actualización queda disponible dentro de la app aunque FCM esté
    // temporalmente fuera de servicio; no se reintenta el push para evitar
    // que un reenvío manual duplique el aviso.
    await notificationRef.set({ delivery: 'in_app', pushError: 'unavailable' }, { merge: true });
    return { ok: true, reportId, notificationId: notificationRef.id, delivery: 'in_app', imageAttached: Boolean(imageUrl) };
  }
}

const setReportPriority = onCall({ region: REGION }, setReportPriorityHandler);
const sendReportUpdate = onCall({ region: REGION }, sendReportUpdateHandler);

module.exports = {
  setReportPriority,
  sendReportUpdate,
  setReportPriorityHandler,
  sendReportUpdateHandler,
  cleanMessage,
  validId,
  evidenceFor,
  canManage,
  isInvalidToken,
};
