'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '..');
const req = createRequire(path.join(root, 'functions/package.json'));
const {applicationDefault, initializeApp} = req('firebase-admin/app');
const {FieldPath, getFirestore} = req('firebase-admin/firestore');
const {isCentralAdmin} = require('../functions/management-access');
process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(root,'tools/private/google-auth/application_default_credentials.json');
const out = path.join(root,'output/clima-2026-11-06');
const actionUrl = 'https://play.google.com/apps/internaltest/4701647237677047143';
const requestId = 'release_clima_v26_20261106';
const title = 'ConDi: nuevo Clima y prevención';
const body = 'Ahora podés consultar el pronóstico de tu municipio y los avisos de ríos y arroyos en Mi perfil > Clima y prevención. En Android, actualizá a la versión 1.0.25 desde Google Play.';

async function main() {
  initializeApp({credential:applicationDefault(),projectId:'project-5fc9024a-e961-42b7-9ee'});
  const db=getFirestore();
  const users=await db.collection('users').where('disabled','==',false).where('role','==','citizen').get();
  const summary={usuariosActivos:users.size,conToken:users.docs.filter(d=>typeof d.get('fcmToken')==='string' && d.get('fcmToken')).length,
    criterio:'Vecinos con cuenta habilitada (disabled=false)',requestId,title,body,actionUrl};
  if(!process.argv.includes('--send')) {
    fs.writeFileSync(path.join(out,'aviso-preparado.json'),JSON.stringify(summary,null,2));
    console.log(JSON.stringify(summary));
    return;
  }
  // No avisar una actualización que todavía no está disponible en el canal.
  const play=JSON.parse(fs.readFileSync(path.join(out,'play-previo.json'),'utf8'));
  const ready=play.tracks.find(t=>t.track==='internal')?.releases?.some(r=>r.status==='completed' && r.versionCodes?.includes('26'));
  const receipt=JSON.parse(fs.readFileSync(path.join(out,'publicacion-android.json'),'utf8'));
  if(!ready || receipt.bundle?.versionCode!==26) throw new Error('La actualización Android aún no está verificada como disponible.');
  const admins=await db.collection('users').where('role','==','admin').get();
  const admin=admins.docs.find(d=>isCentralAdmin(d.data()));
  if(!admin) throw new Error('No hay administración central habilitada.');
  const {sendCustomMessageHandler}=require('../functions/user-messaging');
  const result=await sendCustomMessageHandler({auth:{uid:admin.id},data:{audience:{type:'all'},requestId,title,body,actionUrl}},{db});
  const prefix=`custom_${requestId}_`;
  const docs=await db.collection('notifications').where(FieldPath.documentId(),'>=',prefix).where(FieldPath.documentId(),'<=',`${prefix}\uf8ff`).get();
  const records=docs.docs.map(d=>d.data());
  if(records.some(r=>r.title!==title || r.body!==body || r.actionUrl!==actionUrl)) throw new Error('No coincide el aviso guardado.');
  const verification={cuentas:records.length,pushAceptados:records.filter(r=>r.delivery==='push').length,
    soloBandeja:records.filter(r=>r.delivery==='in_app').length,pendientes:records.filter(r=>r.delivery==='pending').length};
  const final={...summary,result,verification,fecha:new Date().toISOString()};
  fs.writeFileSync(path.join(out,'aviso-enviado.json'),JSON.stringify(final,null,2));
  console.log(JSON.stringify({ok:true,...verification,actionUrl}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
