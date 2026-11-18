'use strict';

// Aviso de la versión 1.0.35 SOLO a las dos cuentas validadoras (regla del titular,
// 2026-11-17). Sin --send solo cuenta destinatarios; con --send entrega y verifica.
const path = require('node:path');
const { createRequire } = require('node:module');

const root = path.resolve(__dirname, '..');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');
const fromFunctions = createRequire(path.join(root, 'functions/package.json'));
const { applicationDefault, getApps, initializeApp } = fromFunctions('firebase-admin/app');
const { getFirestore } = fromFunctions('firebase-admin/firestore');
const { deliverToUsers } = require('../functions/push-delivery');

const RECIPIENTS = ['despuesnodiganque@gmail.com', 'yanisolanna@gmail.com'];
const KEY = 'custom_release_1_0_35_build_36';
const PLAY_LINK = 'https://play.google.com/apps/internaltest/4701647237677047143';

async function main() {
  if (!getApps().length) initializeApp({ credential: applicationDefault(), projectId: 'project-5fc9024a-e961-42b7-9ee' });
  const db = getFirestore();
  const docs = [];
  for (const email of RECIPIENTS) {
    const snap = await db.collection('users').where('email', '==', email).get();
    docs.push(...snap.docs.filter((doc) => doc.get('disabled') !== true));
  }
  console.log(JSON.stringify({ requested: RECIPIENTS.length, found: docs.length }));
  // Nunca se amplía: solo cuentas de RECIPIENTS que existan en ConDi.
  if (docs.length === 0 || docs.length > RECIPIENTS.length) throw new Error('Destinatarios fuera de lo esperado; no se envía nada.');
  if (!process.argv.includes('--send')) return;
  const result = await deliverToUsers(db, docs.map((doc) => ({ uid: doc.id, fcmToken: doc.get('fcmToken') })), {
    key: KEY,
    type: 'municipality_message',
    title: 'Nueva versión de ConDi 1.0.35',
    body: `Ya está disponible ConDi 1.0.35: Clima y predicciones abre el motor meteorológico, mejoramos las fotos de los reportes y las notificaciones, y quitamos la ayuda de IA. Actualizá desde Google Play: ${PLAY_LINK}`,
    data: { actionUrl: PLAY_LINK },
  });
  const saved = await Promise.all(docs.map((doc) => db.collection('notifications').doc(`${KEY}_${doc.id}`).get()));
  if (saved.some((doc) => !doc.exists || doc.get('delivery') === 'pending')) {
    throw new Error('El aviso no quedó confirmado para todas las cuentas encontradas.');
  }
  console.log(JSON.stringify({ ...result, verified: true }));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
