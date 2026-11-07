'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const req = createRequire(path.join(__dirname, '../functions/package.json'));
const { GoogleAuth } = req('google-auth-library');
const { initializeApp } = req('firebase-admin/app');
const { getFirestore, FieldValue } = req('firebase-admin/firestore');
const { getAuth } = req('firebase-admin/auth');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/mvp-2026-10-31');
const projectId = 'project-5fc9024a-e961-42b7-9ee';
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');
fs.mkdirSync(output, { recursive: true });
async function main() {
  const client = await new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] }).getClient();
  for (const service of ['cloud.firestore', 'firebase.storage/project-5fc9024a-e961-42b7-9ee.firebasestorage.app']) {
    const {data: release} = await client.request({url: `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/${service}`});
    const {data: ruleset} = await client.request({url: `https://firebaserules.googleapis.com/v1/${release.rulesetName}`});
    const file = path.join(output, service.startsWith('cloud') ? 'firestore-anterior.json' : 'storage-anterior.json');
    if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify({release,ruleset},null,2));
  }
  const app = initializeApp({projectId});
  const db = getFirestore(app);
  try {
    const owner = await getAuth(app).getUserByEmail('info.consultoradiagonales@gmail.com');
    if (!owner.emailVerified || owner.disabled) throw new Error('La cuenta propietaria debe estar verificada y habilitada.');
    const ref = db.doc(`users/${owner.uid}`);
    const profile = (await ref.get()).data();
    if (profile?.role !== 'admin' || profile.disabled === true) throw new Error('El perfil propietario no tiene el rol esperado.');
    const backup = path.join(output, 'perfil-propietario-anterior.json');
    if (!fs.existsSync(backup)) fs.writeFileSync(backup, JSON.stringify({uid:owner.uid,profile},null,2));
    await ref.update({organizationId:'diagonales', updatedAt:FieldValue.serverTimestamp()});
    if ((await ref.get()).get('organizationId') !== 'diagonales') throw new Error('No se confirmó el acceso integral.');
    console.log('Reglas respaldadas y acceso integral del propietario confirmado.');
  } finally { await db.terminate(); }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
