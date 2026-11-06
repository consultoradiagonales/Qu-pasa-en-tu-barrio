'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '..');
const req = createRequire(path.join(root, 'functions/package.json'));
const {GoogleAuth} = req('google-auth-library');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root, 'tools/private/google-auth/application_default_credentials.json');
const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi';
const out = path.join(root, 'output/clima-2026-11-06');

async function main() {
  fs.mkdirSync(out, {recursive:true});
  const token = await new GoogleAuth({scopes:['https://www.googleapis.com/auth/androidpublisher']}).getAccessToken();
  async function call(url, method='GET', body, binary=false) {
    const r = await fetch(url,{method,headers:{Authorization:`Bearer ${token}`,'X-Goog-User-Project':'condi-maps-2026',
      'Content-Type':binary?'application/octet-stream':'application/json'},
      ...(body===undefined?{}:{body:binary?body:JSON.stringify(body)}),signal:AbortSignal.timeout(binary?900000:60000)});
    const data = await r.json().catch(()=>({}));
    if(!r.ok) throw new Error(`Play HTTP ${r.status}: ${data.error?.message || 'Error'}`);
    return data;
  }
  const edit = await call(`${base}/edits`,'POST',{});
  let committed=false;
  try {
    const [tracks,bundles] = await Promise.all(['tracks','bundles'].map(x=>call(`${base}/edits/${edit.id}/${x}`)));
    const summary = {tracks:tracks.tracks.map(t=>({track:t.track,releases:t.releases?.map(r=>({status:r.status,versionCodes:r.versionCodes}))})),
      maxVersion:Math.max(0,...(bundles.bundles||[]).map(b=>b.versionCode),...tracks.tracks.flatMap(t=>(t.releases||[]).flatMap(r=>(r.versionCodes||[]).map(Number))))};
    if(!process.argv.includes('--publish')) {
      fs.writeFileSync(path.join(out,'play-previo.json'),JSON.stringify(summary,null,2));
      console.log(JSON.stringify(summary));
      return;
    }
    const expected = 26;
    const bytes = fs.readFileSync(path.join(root,'dist/ConDi-1.0.25+26-clima.aab'));
    const hash = createHash('sha256').update(bytes).digest('hex');
    const existing = (bundles.bundles||[]).find(b=>b.versionCode===expected);
    const bundle = existing || await call(`https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi/edits/${edit.id}/bundles?uploadType=media`,'POST',bytes,true);
    if(bundle.versionCode!==expected || bundle.sha256!==hash) throw new Error('Versión o firma de contenido no coincide.');
    const notes=[{language:'es-419',text:'Nueva sección Clima y prevención en Mi perfil: pronóstico de tu municipio para 24, 48 y 72 horas, alertas oficiales del SMN y avisos de ríos y arroyos.'}];
    await call(`${base}/edits/${edit.id}/tracks/internal`,'PUT',{track:'internal',releases:[{name:'ConDi 1.0.25 — clima y prevención',versionCodes:['26'],status:'completed',releaseNotes:notes}]});
    await call(`${base}/edits/${edit.id}:validate`,'POST',{});
    await call(`${base}/edits/${edit.id}:commit`,'POST',{});
    committed=true;
    const result={version:'1.0.25+26',bundle,track:'internal',status:'completed',internalLink:'https://play.google.com/apps/internaltest/4701647237677047143'};
    fs.writeFileSync(path.join(out,'publicacion-android.json'),JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
  } finally {
    if(!committed) await call(`${base}/edits/${edit.id}`,'DELETE').catch(()=>{});
  }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
