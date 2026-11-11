'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');

const root = path.resolve(__dirname, '..');
const req = createRequire(path.join(root, 'functions/package.json'));
const admin = req('firebase-admin');
const project = 'project-5fc9024a-e961-42b7-9ee';
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');

async function main() {
  const app = admin.initializeApp({projectId: project, credential: admin.credential.applicationDefault()});
  const source = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const ruleset = await admin.securityRules(app).releaseFirestoreRulesetFromSource(source);
  const result = {project, ruleset: ruleset.name, release: `projects/${project}/releases/cloud.firestore`, deployedAt: new Date().toISOString()};
  fs.writeFileSync(path.join(root, 'dist/ConDi-Cierre-1.0.26+27/Producto/DESPLIEGUE_FIRESTORE.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
