'use strict';

const { FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

const CHANNEL_ID = 'condi_report_updates';
const BATCH = 500;

function isInvalidToken(code) {
  return code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-registration-token';
}

/**
 * Guarda un aviso en la bandeja de cada usuario y, si tiene token, lo envía
 * como push. El id del aviso es `${key}_${uid}`: reintentar la misma alerta no
 * duplica nada.
 *
 * `users` es una lista de { uid, fcmToken }.
 * Devuelve { total, pushed, inApp }.
 */
async function deliverToUsers(db, users, { key, type, title, body, data = {} }) {
  const result = { total: users.length, pushed: 0, inApp: 0 };
  for (let start = 0; start < users.length; start += BATCH) {
    const chunk = users.slice(start, start + BATCH);

    const fresh = [];
    await Promise.all(chunk.map(async (user) => {
      const ref = db.collection('notifications').doc(`${key}_${user.uid}`);
      try {
        await ref.create({
          userId: user.uid,
          type,
          title,
          body,
          read: false,
          delivery: 'pending',
          createdAt: FieldValue.serverTimestamp(),
          ...data,
        });
        fresh.push({ ...user, ref });
      } catch (error) {
        // Ya existía: este usuario ya recibió este aviso.
        if (error?.code !== 6 && error?.code !== 'already-exists') throw error;
      }
    }));

    const withToken = fresh.filter((u) => typeof u.fcmToken === 'string' && u.fcmToken);
    const withoutToken = fresh.filter((u) => !(typeof u.fcmToken === 'string' && u.fcmToken));
    await Promise.all(withoutToken.map((u) => u.ref.set({ delivery: 'in_app' }, { merge: true })));
    result.inApp += withoutToken.length;
    if (!withToken.length) continue;

    const stringData = Object.fromEntries(
      Object.entries({ type, ...data }).map(([k, v]) => [k, String(v ?? '')]),
    );
    const response = await getMessaging().sendEach(withToken.map((u) => ({
      token: u.fcmToken,
      notification: { title, body },
      data: { ...stringData, notificationId: u.ref.id },
      android: { collapseKey: u.ref.id, notification: { channelId: CHANNEL_ID } },
      apns: { payload: { aps: { sound: 'default' } } },
    })));

    await Promise.all(response.responses.map(async (res, index) => {
      const user = withToken[index];
      if (res.success) {
        result.pushed += 1;
        await user.ref.set({ delivery: 'push', pushSentAt: FieldValue.serverTimestamp() }, { merge: true });
        return;
      }
      result.inApp += 1;
      const invalid = isInvalidToken(res.error?.code);
      await user.ref.set({ delivery: 'in_app', pushError: invalid ? 'invalid_token' : 'unavailable' }, { merge: true });
      if (invalid) {
        await db.collection('users').doc(user.uid).update({ fcmToken: FieldValue.delete() }).catch(() => {});
      }
    }));
  }
  return result;
}

module.exports = { deliverToUsers };
