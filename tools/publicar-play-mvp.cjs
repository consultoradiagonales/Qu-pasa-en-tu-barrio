'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {createRequire}=require('node:module');
const req=createRequire(path.join(__dirname,'../functions/package.json'));
const {GoogleAuth}=req('google-auth-library');
const root=path.resolve(__dirname,'..');
const output=path.join(root,'output/mvp-2026-10-31');
process.env.GOOGLE_APPLICATION_CREDENTIALS=path.join(root,'tools/private/google-auth/application_default_credentials.json');
const packageName='ar.com.consultoradiagonales.condi';
const base=`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
const description=`ConDi permite registrar problemas del barrio y consultar su seguimiento. Es una plataforma privada desarrollada por Consultora Diagonales: no pertenece al Gobierno ni representa automáticamente a una municipalidad. La atención municipal depende de que exista una integración o servicio activo en ese territorio.

CÓMO FUNCIONA
Elegí tu municipio, agregá una foto, revisá la ubicación del problema, seleccioná una categoría y describí lo ocurrido. Podés consultar el estado del reporte y recibir avisos sobre su avance cuando haya gestión activa.

PROBLEMAS DEL BARRIO
Infraestructura, alumbrado, residuos, espacios verdes, tránsito y otras incidencias urbanas. El mapa y los reportes disponibles dependen de tu municipio y de los permisos de tu cuenta.

INFORMACIÓN TERRITORIAL
La selección territorial utiliza datos de Georef (https://www.argentina.gob.ar/georef). Las alertas meteorológicas se basan en el Servicio Meteorológico Nacional (https://www.smn.gob.ar/alertas). Los escudos del MVP identifican territorios; no implican contratación, adhesión ni respaldo de esos gobiernos. Fuentes institucionales: https://www.gba.gob.ar/municipios.

PRIVACIDAD
La app solicita los permisos necesarios para las funciones que usás. La participación en el análisis territorial es opcional. Las condiciones de acceso, tratamiento de datos y eliminación de la cuenta están disponibles en la política de privacidad.

ConDi no es un canal de emergencias. Ante una emergencia utilizá los canales oficiales correspondientes.

ConDi es gratuita para vecinos y no tiene compras dentro de la app. Puede mostrar comunicaciones o promociones locales identificadas.

Desarrollo y contacto: Consultora Diagonales — info.consultoradiagonales@gmail.com
Política de privacidad: https://project-5fc9024a-e961-42b7-9ee.web.app/privacidad.html
Eliminación de cuenta: https://project-5fc9024a-e961-42b7-9ee.web.app/eliminar-cuenta.html`;
async function main(){
  const token=await new GoogleAuth({scopes:['https://www.googleapis.com/auth/androidpublisher']}).getAccessToken();
  const headers={Authorization:`Bearer ${token}`,'X-Goog-User-Project':'condi-maps-2026'};
  async function call(url,method='GET',body,binary=false){
    const res=await fetch(url,{method,headers:{...headers,'Content-Type':binary?'application/octet-stream':'application/json'},...(body!==undefined?{body:binary?body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(binary?900000:60000)});
    const data=await res.json().catch(()=>({}));
    if(!res.ok)throw new Error(`Play HTTP ${res.status}: ${data.error?.message || 'Error'}`);
    return data;
  }
  const edit=await call(`${base}/edits`,'POST',{});
  let committed=false;
  try{
    const details=await call(`${base}/edits/${edit.id}/details`);
    const tracks=await call(`${base}/edits/${edit.id}/tracks`);
    const backup=path.join(output,'play-anterior-publicacion.json');
    if(!fs.existsSync(backup))fs.writeFileSync(backup,JSON.stringify({details,tracks},null,2));
    await call(`${base}/edits/${edit.id}/details`,'PUT',{...details,contactEmail:'info.consultoradiagonales@gmail.com',contactWebsite:'https://project-5fc9024a-e961-42b7-9ee.web.app/'});
    await call(`${base}/edits/${edit.id}/listings/es-419`,'PUT',{language:'es-419',title:'ConDi',shortDescription:'Reportá problemas del barrio y consultá su seguimiento en tu municipio.',fullDescription:description});
    let bundle;
    if(!process.argv.includes('--solo-ficha')){
      const bundlePath=path.join(root,'dist/ConDi-1.0.23+24-mvp.aab');
      const bytes=fs.readFileSync(bundlePath);
      const hash=createHash('sha256').update(bytes).digest('hex');
      const existing=(await call(`${base}/edits/${edit.id}/bundles`)).bundles?.find(b=>b.versionCode===24);
      bundle=existing || await call(`https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}/edits/${edit.id}/bundles?uploadType=media`,'POST',bytes,true);
      if(bundle.versionCode!==24 || bundle.sha256!==hash)throw new Error('El paquete o su huella no coinciden con la compilación verificada.');
      const notes=[{language:'es-419',text:'Identidad de cinco municipios bonaerenses y de la Provincia de Buenos Aires. Separación de acceso municipal y consultora, fuentes de información y mejoras de estabilidad.'}];
      await call(`${base}/edits/${edit.id}/tracks/internal`,'PUT',{track:'internal',releases:[{name:'ConDi MVP 1.0.23',versionCodes:['24'],status:'completed',releaseNotes:notes}]});
      // Preparar la prueba cerrada no la publica ni inicia los 14 días.
      await call(`${base}/edits/${edit.id}/tracks/alpha`,'PUT',{track:'alpha',releases:[{name:'ConDi MVP 1.0.23 — prueba cerrada',versionCodes:['24'],status:'draft',releaseNotes:notes}]});
    }
    await call(`${base}/edits/${edit.id}:validate`,'POST',{});
    await call(`${base}/edits/${edit.id}:commit`,'POST',{});
    committed=true;
    const verify=await call(`${base}/edits`,'POST',{});
    try{
      const [detailsAfter,tracksAfter]=await Promise.all(['details','tracks'].map(resource=>call(`${base}/edits/${verify.id}/${resource}`)));
      const result={version:bundle?'1.0.23+24':null,bundle,details:detailsAfter,tracks:tracksAfter,internalLink:'https://play.google.com/apps/internaltest/4701647237677047143',production:'Bloqueada: 12 verificadores durante 14 días continuos. Prueba cerrada preparada en borrador, no iniciada.'};
      fs.writeFileSync(path.join(output,'publicacion-play.json'),JSON.stringify(result,null,2));
      console.log(JSON.stringify({version:result.version,contactEmail:detailsAfter.contactEmail,tracks:tracksAfter.tracks.map(t=>({track:t.track,releases:t.releases?.map(r=>({status:r.status,versionCodes:r.versionCodes}))}))}));
    }finally{await call(`${base}/edits/${verify.id}`,'DELETE');}
  }finally{if(!committed)await call(`${base}/edits/${edit.id}`,'DELETE').catch(()=>{});}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
