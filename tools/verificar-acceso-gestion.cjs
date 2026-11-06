'use strict';
const fs=require('node:fs');
const path=require('node:path');
const bytes=fs.readFileSync(path.join(process.env.USERPROFILE,'Desktop','ConDi - Gestión Municipal.lnk'));
if(bytes.readUInt32LE(0)!==76)throw new Error('Formato de acceso directo desconocido.');
const flags=bytes.readUInt32LE(20);
let cursor=76;
if(flags&1)cursor+=2+bytes.readUInt16LE(cursor);
if(flags&2)cursor+=bytes.readUInt32LE(cursor);
const strings={};
for(const [bit,name] of [[4,'description'],[8,'relativePath'],[16,'workingDirectory'],[32,'arguments'],[64,'icon']]){
  if(!(flags&bit))continue;
  const length=bytes.readUInt16LE(cursor);cursor+=2;
  const size=length*((flags&128)?2:1);
  strings[name]=bytes.subarray(cursor,cursor+size).toString((flags&128)?'utf16le':'latin1');
  cursor+=size;
}
if(strings.arguments!=='--app=https://project-5fc9024a-e961-42b7-9ee.web.app/admin/')throw new Error('El acceso directo no apunta al panel publicado.');
console.log('Acceso directo del escritorio verificado: panel publicado.');
