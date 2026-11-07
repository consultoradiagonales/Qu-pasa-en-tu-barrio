'use strict';

const path = require('node:path');
const { createRequire } = require('node:module');

const requireFromFunctions = createRequire(path.join(__dirname, '..', 'functions', 'package.json'));
const { applicationDefault, getApps, initializeApp } = requireFromFunctions('firebase-admin/app');
const { FieldPath, getFirestore } = requireFromFunctions('firebase-admin/firestore');

const PROJECT_ID = 'project-5fc9024a-e961-42b7-9ee';
const PLAY_URL = 'https://play.google.com/apps/internaltest/4701647237677047143';

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
  }

  const { sendCustomMessageHandler } = require('../functions/user-messaging');
  const db = getFirestore();
  const admins = await db.collection('users').where('role', '==', 'admin').get();
  const admin = admins.docs.find((doc) => doc.get('disabled') !== true);
  if (!admin) throw new Error('No hay una cuenta administradora activa.');

  const requestId = 'release_1_0_20_build_21';
  await sendCustomMessageHandler({
    auth: { uid: admin.id },
    data: {
      audience: { type: 'all' },
      requestId,
      title: 'ConDi 1.0.20 disponible',
      body: 'Ya podés actualizar ConDi. La nueva versión incorpora inicio con cámara y perfil, dirección manual rápida, nuevos tipos de reportes, análisis municipal con IA y el escudo de La Plata. Tocá para actualizar desde Google Play.',
      actionUrl: PLAY_URL,
    },
  }, { db });

  const prefix = `custom_${requestId}_`;
  const notifications = await db.collection('notifications')
    .where(FieldPath.documentId(), '>=', prefix)
    .where(FieldPath.documentId(), '<=', `${prefix}\uf8ff`)
    .get();
  const records = notifications.docs.map((doc) => doc.data());
  if (!records.length || records.some((item) => item.actionUrl !== PLAY_URL)) {
    throw new Error('No se pudo verificar la acción de actualización.');
  }
  const pushed = records.filter((item) => item.delivery === 'push').length;
  process.stdout.write(`${JSON.stringify({
    ok: true,
    total: records.length,
    pushed,
    inApp: records.length - pushed,
    actionUrl: PLAY_URL,
  })}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
