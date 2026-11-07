'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const requireFunctions = createRequire(path.join(__dirname, '../functions/package.json'));
const { GoogleAuth } = requireFunctions('google-auth-library');
const { initializeApp } = requireFunctions('firebase-admin/app');
const { getFirestore, FieldValue } = requireFunctions('firebase-admin/firestore');

const projectId = 'project-5fc9024a-e961-42b7-9ee';
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/publicacion-2026-10-30');
fs.mkdirSync(output, { recursive: true });
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');
const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });

async function readRules() {
  const token = await auth.getAccessToken();
  async function read(url) {
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`No se pudo leer la versión de reglas: HTTP ${response.status}`);
    return response.json();
  }
  const release = await read(`https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/cloud.firestore`);
  const ruleset = await read(`https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  return { release, ruleset };
}

(async () => {
  const snapshot = await readRules();
  if (process.argv.includes('--verificar')) {
    const remote = snapshot.ruleset.source.files.find((file) => file.name.endsWith('firestore.rules')) || snapshot.ruleset.source.files[0];
    const normalize = (value) => value.replace(/\r\n/g, '\n').trim();
    if (normalize(remote.content) !== normalize(fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'))) {
      throw new Error('Las reglas publicadas no coinciden con las verificadas localmente.');
    }
    fs.writeFileSync(path.join(output, 'firestore-publicado.json'), JSON.stringify(snapshot.release, null, 2));
    console.log('Reglas publicadas verificadas contra el archivo local.');
    return;
  }
  const backupPath = path.join(output, 'firestore-anterior.json');
  if (!fs.existsSync(backupPath)) fs.writeFileSync(backupPath, JSON.stringify(snapshot, null, 2));
  const app = initializeApp({ projectId });
  const db = getFirestore(app);
  const policyRef = db.doc('reportSubmissionPolicy/current');
  const prior = await policyRef.get();
  const policyBackup = path.join(output, 'politica-anterior.json');
  if (!fs.existsSync(policyBackup)) fs.writeFileSync(policyBackup, JSON.stringify({ exists: prior.exists, data: prior.data() || null }, null, 2));
  await policyRef.set({
    legacyEnabled: true,
    newSubmissionProtocol: 1,
    reason: 'Validación web 1.0.22; conservar altas de las versiones móviles distribuidas hasta completar migración.',
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  if ((await policyRef.get()).get('legacyEnabled') !== true) throw new Error('No se confirmó la política de compatibilidad.');
  await db.terminate();
  console.log('Reglas anteriores respaldadas y transición móvil preparada.');
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
