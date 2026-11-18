'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { createRequire } = require('node:module');

const root = path.resolve(__dirname, '..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { GoogleAuth } = requireFromFunctions('google-auth-library');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');

const versionCode = 37;
const bundlePath = path.join(root, 'build/app/outputs/bundle/release/app-release.aab');
const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi';
const notes = [{ language: 'es-419', text: 'Inicio más limpio con la cámara grande; Clima y predicciones abre el motor meteorológico; nueva opción para invitar a otros a usar ConDi desde Perfil.' }];

async function main() {
  const bytes = fs.readFileSync(bundlePath);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const token = await new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] }).getAccessToken();
  const headers = { Authorization: `Bearer ${token}`, 'X-Goog-User-Project': 'condi-maps-2026' };
  async function call(url, method = 'GET', body, binary = false) {
    const response = await fetch(url, {
      method,
      headers: { ...headers, 'Content-Type': binary ? 'application/octet-stream' : 'application/json' },
      ...(body === undefined ? {} : { body: binary ? body : JSON.stringify(body) }),
      signal: AbortSignal.timeout(binary ? 900000 : 60000),
    });
    const result = response.status === 204 ? null : await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(`Play HTTP ${response.status}: ${result?.error?.message || 'Error'}`);
    return result;
  }

  const edit = await call(`${base}/edits`, 'POST', {});
  let committed = false;
  try {
    const [tracks, bundles] = await Promise.all(['tracks', 'bundles'].map((resource) => call(`${base}/edits/${edit.id}/${resource}`)));
    const internal = tracks.tracks?.find((track) => track.track === 'internal');
    const current = Math.max(0, ...(internal?.releases || []).flatMap((release) => (release.versionCodes || []).map(Number)));
    if (current > versionCode) throw new Error(`Play tiene una versión más reciente (${current}).`);
    const existing = bundles.bundles?.find((bundle) => bundle.versionCode === versionCode);
    const bundle = existing || await call(
      `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi/edits/${edit.id}/bundles?uploadType=media`,
      'POST', bytes, true,
    );
    if (Number(bundle.versionCode) !== versionCode || bundle.sha256 !== sha256) {
      throw new Error('La versión o la huella SHA-256 del AAB no coincide.');
    }
    await call(`${base}/edits/${edit.id}/tracks/internal`, 'PUT', {
      track: 'internal',
      releases: [{ name: 'ConDi 1.0.36', versionCodes: [String(versionCode)], status: 'completed', releaseNotes: notes }],
    });
    await call(`${base}/edits/${edit.id}:validate`, 'POST', {});
    await call(`${base}/edits/${edit.id}:commit`, 'POST', {});
    committed = true;
  } finally {
    if (!committed) await call(`${base}/edits/${edit.id}`, 'DELETE').catch(() => {});
  }

  const verifyEdit = await call(`${base}/edits`, 'POST', {});
  try {
    const tracks = await call(`${base}/edits/${verifyEdit.id}/tracks`);
    const release = tracks.tracks?.find((track) => track.track === 'internal')?.releases
      ?.find((entry) => entry.status === 'completed' && entry.versionCodes?.map(Number).includes(versionCode));
    if (!release) throw new Error('Play no muestra la versión publicada en prueba interna.');
  } finally {
    await call(`${base}/edits/${verifyEdit.id}`, 'DELETE').catch(() => {});
  }
  const result = { version: '1.0.36+37', sha256, track: 'internal', status: 'completed',
    internalLink: 'https://play.google.com/apps/internaltest/4701647237677047143' };
  const output = path.join(root, 'store_assets/PLAY_RELEASE_1.0.36.json');
  fs.writeFileSync(output, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
