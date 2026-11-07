'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const mapping=JSON.parse(fs.readFileSync(path.join(root,'output/mvp-2026-10-31/official-crest-mapping.json'),'utf8')).matched;
const requested=new Set(['Trenque Lauquen','Saladillo','La Plata','Escobar','Rivadavia']);
const folder=path.join(root,'assets/images/municipalities');
fs.mkdirSync(folder,{recursive:true});

(async()=>{
  const entries=[];
  for(const item of mapping.filter(item=>requested.has(item.name))){
    const key=item.name.toLowerCase().replaceAll(' ','_');
    const asset=`assets/images/municipalities/${key}_official.png`;
    const response=await fetch(item.source.image,{signal:AbortSignal.timeout(30000)});
    if(!response.ok)throw Error(`${item.name}: HTTP ${response.status}`);
    const bytes=Buffer.from(await response.arrayBuffer());
    if(!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))throw Error(`${item.name}: la fuente no es PNG`);
    fs.writeFileSync(path.join(root,asset),bytes);
    entries.push({id:`georef_${item.id}`,code:item.id,censusCode:item.id.slice(0,2)+item.id.slice(3),key,name:item.name,provinceId:'06',province:'Buenos Aires',center:{lat:item.center.lat,lng:item.center.lon},crestAsset:asset,source:item.source.image,sourcePage:'https://www.gba.gob.ar/municipios',sourceLabel:item.source.title,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
  }
  const file='Coat_of_arms_of_the_Buenos_Aires_Province.svg';
  const md5=crypto.createHash('md5').update(file).digest('hex');
  const url=`https://upload.wikimedia.org/wikipedia/commons/${md5[0]}/${md5.slice(0,2)}/${file}`;
  const response=await fetch(url,{headers:{'User-Agent':'ConDiMVP/1.0 (info.consultoradiagonales@gmail.com)'},signal:AbortSignal.timeout(30000)});
  if(!response.ok)throw Error(`Provincia: HTTP ${response.status}`);
  const svg=await response.text();
  if(!svg.includes('<svg')||/<script\b|<foreignObject\b/i.test(svg))throw Error('SVG provincial no válido');
  const province={id:'06',name:'Provincia de Buenos Aires',crestAsset:'assets/images/municipalities/buenos_aires_province.svg',source:url,sourcePage:'https://commons.wikimedia.org/wiki/File:Coat_of_arms_of_the_Buenos_Aires_Province.svg',license:'Dominio público PD-AR-Gov; fuente reconocida. Vector por Hurfer.'};
  fs.writeFileSync(path.join(root,province.crestAsset),svg);
  const catalog={schemaVersion:1,retrievedAt:'2026-10-31',province,municipalities:entries.sort((a,b)=>a.name.localeCompare(b.name,'es')),notice:'Identidad territorial de referencia. La inclusión no acredita contratación, adhesión ni representación oficial.'};
  fs.writeFileSync(path.join(folder,'catalog.json'),JSON.stringify(catalog,null,2));
  fs.writeFileSync(path.join(folder,'SOURCES_MVP.md'),'# Escudos del MVP\n\nConsulta: 31/10/2026.\n\n'+entries.map(item=>`- ${item.name} (${item.code}): [catálogo oficial](${item.sourcePage}), [archivo](${item.source}).`).join('\n')+`\n- ${province.name}: [fuente y licencia](${province.sourcePage}).\n\n${catalog.notice}\n`);
  console.log(JSON.stringify({municipalities:entries.map(item=>item.name),province:province.name}));
})().catch(error=>{console.error(error.message);process.exitCode=1;});
