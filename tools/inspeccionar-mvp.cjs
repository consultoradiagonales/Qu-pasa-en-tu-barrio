'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const requireFunctions = createRequire(path.join(__dirname, '../functions/package.json'));
const { GoogleAuth } = requireFunctions('google-auth-library');
const { initializeApp } = requireFunctions('firebase-admin/app');
const { getFirestore } = requireFunctions('firebase-admin/firestore');
const { getAuth } = requireFunctions('firebase-admin/auth');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output/mvp-2026-10-31');
fs.mkdirSync(output, { recursive: true });
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');

(async () => {
  const app = initializeApp({ projectId: 'project-5fc9024a-e961-42b7-9ee' });
  const db = getFirestore(app);
  const owner = await getAuth(app).getUserByEmail('info.consultoradiagonales@gmail.com');
  const managers = await db.collection('users').where('role', 'in', ['admin','coordinator','moderator','municipal_admin']).select('role','municipalityId','organizationId','disabled').get();
  const scope = { ownerUid: owner.uid, ownerEmailVerified: owner.emailVerified, managers: managers.docs.map(doc => ({ uid: doc.id, ...doc.data() })) };
  fs.writeFileSync(path.join(output, 'perfiles-gestion.json'), JSON.stringify(scope, null, 2));
  console.log(JSON.stringify({ ownerEmailVerified: owner.emailVerified, managerCount: scope.managers.length, roles: scope.managers.map(p => ({ role:p.role, municipalityId:p.municipalityId, owner:p.uid===owner.uid })) }));
  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const token = await auth.getAccessToken();
  const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi';
  async function call(url, method='GET', body) {
    const response = await fetch(url, {method,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Goog-User-Project':'condi-maps-2026'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)});
    const data = await response.json().catch(()=>({}));
    if(!response.ok) throw new Error(`Play HTTP ${response.status}: ${data.error?.message || 'Error'}`);
    return data;
  }
  const edit = await call(`${base}/edits`, 'POST', {});
  try {
    const [tracks, details, listings, bundles] = await Promise.all(['tracks','details','listings','bundles'].map(resource => call(`${base}/edits/${edit.id}/${resource}`)));
    fs.writeFileSync(path.join(output,'estado-google-play.json'),JSON.stringify({tracks,details,listings,bundles},null,2));
    console.log(JSON.stringify({playTracks:tracks.tracks?.map(track=>({track:track.track,releases:track.releases?.map(r=>({status:r.status,versionCodes:r.versionCodes}))})),listingLanguages:listings.listings?.map(l=>l.language),bundles:bundles.bundles?.map(b=>b.versionCode)}));
  } finally { await call(`${base}/edits/${edit.id}`, 'DELETE'); }
  await db.terminate();
})().catch(e=>{console.error(e.message);process.exitCode=1;});
