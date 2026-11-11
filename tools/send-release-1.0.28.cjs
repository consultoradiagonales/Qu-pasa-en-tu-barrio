'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const root = path.resolve(__dirname, '..');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  root,
  'tools',
  'private',
  'google-auth',
  'application_default_credentials.json',
);
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { applicationDefault, getApps, initializeApp } = requireFromFunctions('firebase-admin/app');
const { FieldPath, getFirestore } = requireFromFunctions('firebase-admin/firestore');

const projectId = 'project-5fc9024a-e961-42b7-9ee';
const requestId = 'release_1_0_28_build_29';
const title = 'Actualiza la APP';
const body = 'Actualiza la APP para poder seguir mejorando. No dejes de publicar un reporte diario, nos resulta muy necesario para validar la APP 🤝🏽 Te agradecemos el ser parte de esta comunidad de validadores';
const actionUrl = 'https://play.google.com/apps/internaltest/4701647237677047143';

async function main() {
  if (!getApps().length) initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  const { sendCustomMessageHandler } = require('../functions/user-messaging');
  const admins = await db.collection('users').where('role', '==', 'admin').get();
  const admin = admins.docs.find((doc) => doc.get('disabled') !== true);
  if (!admin) throw new Error('No hay una cuenta administradora activa.');

  const delivery = await sendCustomMessageHandler({
    auth: { uid: admin.id },
    data: { audience: { type: 'all' }, requestId, title, body, actionUrl },
  }, { db });

  const prefix = `custom_${requestId}_`;
  const saved = await db.collection('notifications')
    .where(FieldPath.documentId(), '>=', prefix)
    .where(FieldPath.documentId(), '<=', `${prefix}\uf8ff`)
    .get();
  const records = saved.docs.map((doc) => doc.data());
  if (records.length !== delivery.total || records.some((item) =>
    item.actionUrl !== actionUrl || item.title !== title || item.body !== body)) {
    throw new Error('No se pudo verificar el aviso enviado a todos los destinatarios.');
  }

  const result = {
    sentAt: new Date().toISOString(),
    versionName: '1.0.28',
    versionCode: 29,
    requestId,
    audience: 'vecinos activos (cuentas no deshabilitadas)',
    title,
    body,
    total: delivery.total,
    pushed: delivery.pushed,
    inApp: delivery.inApp,
    actionUrl,
    verified: true,
  };
  const output = path.join(root, 'output', 'comunicacion-2026-11-10', 'NOTIFICATION_RELEASE_1.0.28.json');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(result, null, 2));
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
