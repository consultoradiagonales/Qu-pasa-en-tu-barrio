'use strict';
// Ensaya un edit desechable. Nunca confirma ni publica la versión existente.
const fs=require('node:fs');
const path=require('node:path');
const {createRequire}=require('node:module');
const req=createRequire(path.join(__dirname,'../functions/package.json'));
const {GoogleAuth}=req('google-auth-library');
const root=path.resolve(__dirname,'..');
process.env.GOOGLE_APPLICATION_CREDENTIALS=path.join(root,'tools/private/google-auth/application_default_credentials.json');
(async()=>{
 const token=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/androidpublisher']}).getAccessToken();
 const base='https://androidpublisher.googleapis.com/androidpublisher/v3/applications/ar.com.consultoradiagonales.condi';
 async function call(url,method='GET',body){const r=await fetch(url,{method,headers:{Authorization:`Bearer ${token}`,'X-Goog-User-Project':'condi-maps-2026','Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)});const data=await r.json().catch(()=>({}));return {ok:r.ok,status:r.status,data};}
 const created=await call(`${base}/edits`,'POST',{});
 if(!created.ok)throw Error(created.data.error?.message || `HTTP ${created.status}`);
 const edit=created.data.id;
 let result;
 try {
   const track=await call(`${base}/edits/${edit}/tracks/production`,'PUT',{track:'production',releases:[{name:'Validación de acceso · borrador desechable',versionCodes:['22'],status:'completed'}]});
   const validation=track.ok?await call(`${base}/edits/${edit}:validate`,'POST',{}):null;
   result={published:false,committed:false,trackCheck:track,validation};
 } finally {await call(`${base}/edits/${edit}`,'DELETE');}
 fs.writeFileSync(path.join(root,'output/mvp-2026-10-31/acceso-produccion.json'),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
