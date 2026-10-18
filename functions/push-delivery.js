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
 * `messagingProvider` es opcional (por defecto el getMessaging real).
 * Devuelve { total, pushed, inApp }.
 */
async function deliverToUsers(db, users, { key, type, title, body, data = {} }, messagingProvider = getMessaging) {
  const result = { total: users.length, pushed: 0, inApp: 0 };
  for (let start = 0; start < users.length; start += BATCH) {
    const chunk = users.slice(start, start + BATCH);

    const fresh = [];
    const failures = [];
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
        if (error?.code !== 6 && error?.code !== 'already-exists') failures.push(error);
      }
    }));

    const withToken = fresh.filter((u) => typeof u.fcmToken === 'string' && u.fcmToken);
    const withoutToken = fresh.filter((u) => !(typeof u.fcmToken === 'string' && u.fcmToken));
    await Promise.all(withoutToken.map((u) => u.ref.set({ delivery: 'in_app' }, { merge: true })));
    result.inApp += withoutToken.length;

    if (withToken.length) {
      const stringData = Object.fromEntries(
        Object.entries({ type, ...data }).map(([k, v]) => [k, String(v ?? '')]),
      );
      let response = null;
      try {
        response = await messagingProvider().sendEach(withToken.map((u) => ({
          token: u.fcmToken,
          notification: { title, body },
          data: { ...stringData, notificationId: u.ref.id },
          android: { collapseKey: u.ref.id, notification: { channelId: CHANNEL_ID } },
          apns: { payload: { aps: { sound: 'default' } } },
        })));
      } catch (error) {
        // Falla total de FCM: el aviso queda en la bandeja y no se queda "pending".
        await Promise.all(withToken.map((u) => u.ref.set({ delivery: 'in_app', pushError: 'unavailable' }, { merge: true })));
        result.inApp += withToken.length;
      }

      if (response) {
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
    }

    // Los avisos que sí se crearon ya se procesaron; recién ahora se propaga
    // un fallo de escritura ajeno (así un usuario no deja a los demás en "pending").
    if (failures.length) throw failures[0];
  }
  return result;
}

module.exports = { deliverToUsers };
