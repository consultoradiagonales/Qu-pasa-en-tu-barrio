'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {createRequire}=require('node:module');
const req=createRequire(path.join(__dirname,'../functions/package.json'));
const {GoogleAuth}=req('google-auth-library');
const root=path.resolve(__dirname,'..');
const output=path.join(root,'output/mvp-2026-10-31');
const base='https://project-5fc9024a-e961-42b7-9ee.web.app';
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const normalized=text=>text.replace(/\r\n/g,'\n').trim();
process.env.GOOGLE_APPLICATION_CREDENTIALS=path.join(root,'tools/private/google-auth/application_default_credentials.json');
async function main(){
  const client=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  const project='project-5fc9024a-e961-42b7-9ee';
  const {data:release}=await client.request({url:`https://firebaserules.googleapis.com/v1/projects/${project}/releases/cloud.firestore`});
  const {data:ruleset}=await client.request({url:`https://firebaserules.googleapis.com/v1/${release.rulesetName}`});
  if(normalized(ruleset.source.files[0].content)!==normalized(fs.readFileSync(path.join(root,'firestore.rules'),'utf8')))throw new Error('Las reglas remotas difieren del archivo verificado.');
  const {data:storageRelease}=await client.request({url:`https://firebaserules.googleapis.com/v1/projects/${project}/releases/firebase.storage/${project}.firebasestorage.app`});
  const storageBackup=JSON.parse(fs.readFileSync(path.join(output,'storage-anterior.json'),'utf8'));
  if(storageRelease.rulesetName!==storageBackup.release.rulesetName)throw new Error('Storage cambió durante la publicación. Revisar la migración pendiente.');
  const catalog=JSON.parse(fs.readFileSync(path.join(root,'assets/images/municipalities/catalog.json'),'utf8'));
  const assets=[catalog.province,...catalog.municipalities];
  const urls=['/version.json','/','/admin/','/privacidad.html','/eliminar-cuenta.html','/admin/app.js','/admin/management-access.js','/admin/municipality-branding.js',...assets.map(a=>`/assets/${a.crestAsset}`)];
  const checks=await Promise.all(urls.map(async url=>{
    const response=await fetch(`${base}${url}`,{signal:AbortSignal.timeout(60000)});
    if(!response.ok)throw new Error(`HTTP ${response.status}: ${url}`);
    const bytes=Buffer.from(await response.arrayBuffer());
    if(url==='/version.json'){
      const version=JSON.parse(bytes);
      if(version.version!=='1.0.23'||String(version.build_number)!=='24')throw new Error('Versión web incorrecta.');
    }
    if(url.startsWith('/admin/')&&url.endsWith('.js') && digest(bytes)!==digest(fs.readFileSync(path.join(root,'web',url))))throw new Error(`Código web desactualizado: ${url}`);
    if(url.startsWith('/assets/')&&!response.headers.get('content-type')?.startsWith('image/'))throw new Error(`El escudo no es una imagen: ${url}`);
    if(url==='/admin/'){
      const ids=[...bytes.toString().matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
      if(new Set(ids).size!==ids.length)throw new Error('El panel contiene IDs duplicados.');
    }
    return {url,status:response.status,bytes:bytes.length,contentType:response.headers.get('content-type')};
  }));
  const result={checkedAt:new Date().toISOString(),version:'1.0.23+24',firestoreRulesMatch:true,firestoreRelease:release.rulesetName,storageUnchanged:true,storageStatus:'Pendiente de migración de permisos y URLs de fotos. No declarado listo para datos sensibles.',checks};
  fs.writeFileSync(path.join(output,'verificacion-publicacion.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify({version:result.version,firestoreRulesMatch:true,storageUnchanged:true,publicResources:checks.length,crests:assets.length}));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
