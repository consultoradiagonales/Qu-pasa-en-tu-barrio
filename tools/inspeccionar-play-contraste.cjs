'use strict';
// Solo consulta versiones. La edición temporal se descarta; no sube paquetes,
// no cambia canales y no realiza commit de ninguna edición.
const path = require('node:path');
const fs = require('node:fs');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '..');
const req = createRequire(path.join(root,'functions/package.json'));
const {GoogleAuth} = req('google-auth-library');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root,'tools/private/google-auth/application_default_credentials.json');
async function main() {
  const token=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/androidpublisher']}).getAccessToken();
  const base='https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi/edits';
  const headers={Authorization:`Bearer ${token}`,'X-Goog-User-Project':'condi-maps-2026','Content-Type':'application/json'};
  async function call(url,method='GET') {
    const r=await fetch(url,{method,headers,...(method==='POST'?{body:'{}'}:{}),signal:AbortSignal.timeout(60000)});
    const j=await r.json().catch(()=>({}));
    if(!r.ok) throw new Error(`Play ${r.status}: ${j.error?.message || 'Error'}`);
    return j;
  }
  const edit=await call(base,'POST');
  try {
    const [tracks,bundles]=await Promise.all([call(`${base}/${edit.id}/tracks`),call(`${base}/${edit.id}/bundles`)]);
    const result={tracks:tracks.tracks.map(t=>({track:t.track,releases:t.releases?.map(r=>({status:r.status,versionCodes:r.versionCodes}))})),
      maxVersion:Math.max(0,...(bundles.bundles||[]).map(b=>b.versionCode),...tracks.tracks.flatMap(t=>(t.releases||[]).flatMap(r=>(r.versionCodes||[]).map(Number))))};
    fs.writeFileSync(path.join(root,'output/fondos-claros-2026-11-05/play-previo.json'),JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
  } finally { await call(`${base}/${edit.id}`,'DELETE'); }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
