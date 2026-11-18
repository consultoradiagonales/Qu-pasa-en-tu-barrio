'use strict';

// Avisa únicamente a titulares activos de reportes cuya foto sigue pendiente.
// Sin --send realiza sólo la selección; con --send entrega y verifica.
const path = require('node:path');
const { createRequire } = require('node:module');

const root = path.resolve(__dirname, '..');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  root,
  'tools/private/google-auth/application_default_credentials.json',
);
const fromFunctions = createRequire(path.join(root, 'functions/package.json'));
const { applicationDefault, getApps, initializeApp } = fromFunctions('firebase-admin/app');
const { getFirestore } = fromFunctions('firebase-admin/firestore');
const { deliverToUsers } = require('../functions/push-delivery');

const PROJECT_ID = 'project-5fc9024a-e961-42b7-9ee';
const KEY = 'pending_photo_retry_2026_11_18';
const PLAY_LINK = 'https://play.google.com/apps/internaltest/4701647237677047143';

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
  }
  const db = getFirestore();
  const pending = await db.collection('reports')
    .where('photoUploadStatus', '==', 'pending')
    .get();
  const ownerIds = [...new Set(pending.docs.map((doc) => doc.get('userId')).filter(Boolean))];
  const owners = (await Promise.all(ownerIds.map((uid) => db.collection('users').doc(uid).get())))
    .filter((doc) => doc.exists && doc.get('disabled') !== true);

  console.log(JSON.stringify({ pendingReports: pending.size, affectedActiveUsers: owners.length }));
  if (!process.argv.includes('--send') || owners.length === 0) return;

  const result = await deliverToUsers(
    db,
    owners.map((doc) => ({ uid: doc.id, fcmToken: doc.get('fcmToken') })),
    {
      key: KEY,
      type: 'municipality_message',
      title: 'Completá la foto de tu reporte',
      body: `Actualizá ConDi desde Google Play, abrí el borrador pendiente y tocá “Reintentar foto”. El reporte ya fue recibido: no crees otro. ${PLAY_LINK}`,
      data: { actionUrl: PLAY_LINK },
    },
  );
  const saved = await Promise.all(
    owners.map((doc) => db.collection('notifications').doc(`${KEY}_${doc.id}`).get()),
  );
  if (saved.some((doc) => !doc.exists || doc.get('delivery') === 'pending')) {
    throw new Error('El aviso no quedó confirmado para todos los usuarios afectados.');
  }
  console.log(JSON.stringify({ ...result, verified: true }));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
