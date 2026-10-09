// Backend local de la maqueta. Requiere Node.js 22.13+ (node:sqlite).
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {DatabaseSync} = require('node:sqlite');

const root = __dirname;
const port = Number(process.env.PORT || 4173);
const host = process.env.HOST || '127.0.0.1';
const databasePath = process.env.DB_PATH || path.join(root, 'data', 'maqueta.sqlite');
fs.mkdirSync(path.dirname(databasePath), {recursive: true});
const db = new DatabaseSync(databasePath);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS reports (
    id TEXT PRIMARY KEY, status TEXT NOT NULL, category TEXT NOT NULL,
    team_id TEXT, created_at INTEGER NOT NULL, resolved_at INTEGER,
    supports INTEGER NOT NULL DEFAULT 0, document TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY, role TEXT NOT NULL, report_id TEXT NOT NULL,
    time INTEGER NOT NULL, document TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS reports_status_idx ON reports(status);
  CREATE INDEX IF NOT EXISTS reports_category_idx ON reports(category);
  CREATE INDEX IF NOT EXISTS notifications_role_time_idx ON notifications(role, time DESC);
`);

const teams = new Set(['norte', 'centro', 'verde']);
const categories = new Set(['Infraestructura','Alumbrado','Limpieza','Ambiente','Seguridad','Salud','Transporte']);
const seedReports = [
  {id:'r101',title:'Luminaria apagada en la esquina',description:'La esquina está a oscuras desde hace varios días. Es una zona muy transitada por la noche.',category:'Alumbrado',status:'pending',teamId:null,createdAt:Date.now()-7200000,supports:12,x:31,y:43,owner:'vecino',rating:0},
  {id:'r102',title:'Vereda rota junto a la plaza',description:'Hay baldosas levantadas y se dificulta el paso de cochecitos y personas mayores.',category:'Infraestructura',status:'assigned',teamId:'norte',createdAt:Date.now()-86400000,supports:8,x:70,y:36,owner:'otro',rating:0},
  {id:'r103',title:'Basural retirado de la calle',description:'Se habían acumulado bolsas y residuos en la esquina. El equipo limpió el espacio.',category:'Limpieza',status:'resolved',teamId:'centro',createdAt:Date.now()-172800000,supports:24,x:53,y:72,owner:'vecino',rating:5,arrivedAt:Date.now()-10800000,resolvedAt:Date.now()-7200000},
];
const seedNotifications = [
  {id:'n1',role:'citizen',reportId:'r103',title:'¡Problema resuelto!',body:'La limpieza terminó. Mirá el antes y después.',time:Date.now()-7200000,read:false},
  {id:'n2',role:'coordinator',reportId:'r101',title:'Nuevo reporte en tu municipio',body:'Luminaria apagada en la esquina',time:Date.now()-7200000,read:false},
  {id:'n3',role:'field',reportId:'r102',title:'Nueva tarea asignada',body:'Vereda rota junto a la plaza',time:Date.now()-3600000,read:false},
];

const putReport = db.prepare(`INSERT INTO reports(id,status,category,team_id,created_at,resolved_at,supports,document)
  VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,
  category=excluded.category,team_id=excluded.team_id,resolved_at=excluded.resolved_at,
  supports=excluded.supports,document=excluded.document`);
const putNotification = db.prepare(`INSERT INTO notifications(id,role,report_id,time,document)
  VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET document=excluded.document`);
function storeReport(report){putReport.run(report.id,report.status,report.category,report.teamId||null,report.createdAt,report.resolvedAt||null,report.supports,JSON.stringify(report))}
function storeNotification(note){putNotification.run(note.id,note.role,note.reportId,note.time,JSON.stringify(note))}
function resetDatabase(){db.exec('BEGIN');try{db.exec('DELETE FROM notifications; DELETE FROM reports;');seedReports.forEach(storeReport);seedNotifications.forEach(storeNotification);db.exec('COMMIT')}catch(error){db.exec('ROLLBACK');throw error}}
if(db.prepare('SELECT COUNT(*) AS count FROM reports').get().count===0)resetDatabase();

function reports(){return db.prepare('SELECT document FROM reports ORDER BY created_at DESC').all().map(row=>JSON.parse(row.document))}
function notifications(){return db.prepare('SELECT document FROM notifications ORDER BY time DESC').all().map(row=>JSON.parse(row.document))}
function analytics(){
  const byStatus=Object.fromEntries(db.prepare('SELECT status, COUNT(*) AS count FROM reports GROUP BY status').all().map(row=>[row.status,row.count]));
  const byCategory=db.prepare('SELECT category, COUNT(*) AS count FROM reports GROUP BY category ORDER BY count DESC, category').all();
  const summary=db.prepare(`SELECT COUNT(*) AS total, COALESCE(SUM(supports),0) AS supports,
    ROUND(AVG(CASE WHEN resolved_at IS NOT NULL THEN (resolved_at-created_at)/3600000.0 END),1) AS avgResolutionHours
    FROM reports`).get();
  return {...summary,byStatus,byCategory,active:(byStatus.assigned||0)+(byStatus.in_progress||0)};
}
let revision=0;
const clients=new Set();
function snapshot(){return {reports:reports(),notifications:notifications(),analytics:analytics(),revision}}
function broadcast(){revision++;const message=`data: ${JSON.stringify(snapshot())}\n\n`;for(const client of clients)client.write(message)}
function notify(role,reportId,title,body){storeNotification({id:randomUUID(),role,reportId,title,body,time:Date.now(),read:false})}
function error(status,message){const issue=new Error(message);issue.status=status;throw issue}
function findReport(id){const row=db.prepare('SELECT document FROM reports WHERE id=?').get(id);if(!row)error(404,'Reporte no encontrado.');return JSON.parse(row.document)}
function requireText(value,max,label){if(typeof value!=='string'||!value.trim()||value.trim().length>max)error(400,`${label} inválido.`);return value.trim()}
function applyAction(input){
  if(!input||typeof input!=='object')error(400,'Solicitud inválida.');
  const action=input.action;
  if(action==='reset'){
    db.exec('DELETE FROM notifications; DELETE FROM reports;');
    seedReports.forEach(storeReport);
    seedNotifications.forEach(storeNotification);
    return {ok:true};
  }
  if(action==='create'){
    const title=requireText(input.title,80,'Título');
    const description=requireText(input.description,500,'Descripción');
    if(!categories.has(input.category))error(400,'Categoría inválida.');
    const item={id:randomUUID(),title,description,category:input.category,status:'pending',teamId:null,
      createdAt:Date.now(),supports:0,x:26+Math.round(Math.random()*52),y:27+Math.round(Math.random()*43),owner:'vecino',rating:0};
    storeReport(item);notify('coordinator',item.id,'Nuevo reporte en tu municipio',title);return {ok:true,id:item.id};
  }
  if(action==='mark_read'){
    const row=db.prepare('SELECT document FROM notifications WHERE id=?').get(input.id);
    if(!row)error(404,'Aviso no encontrado.');
    const note=JSON.parse(row.document);note.read=true;storeNotification(note);return {ok:true};
  }
  const item=findReport(input.id);
  if(action==='assign'){
    if(!['pending','assigned'].includes(item.status))error(409,'El reporte ya está en curso o resuelto.');
    if(!teams.has(input.teamId))error(400,'Equipo inválido.');
    if(item.status==='assigned'&&item.teamId===input.teamId)return {ok:true};
    item.teamId=input.teamId;item.status='assigned';
    notify('citizen',item.id,'Reporte asignado',item.title);
    notify('field',item.id,'Nueva tarea asignada',item.title);
  }else if(action==='arrive'){
    if(item.status!=='assigned')error(409,'La tarea no está asignada.');
    item.status='in_progress';item.arrivedAt=Date.now();
    notify('citizen',item.id,'Equipo en el lugar',item.title);
  }else if(action==='progress_photo'){
    if(item.status!=='in_progress')error(409,'La tarea no está en curso.');
    item.progressPhotos=(item.progressPhotos||0)+1;
  }else if(action==='finish'){
    if(item.status!=='in_progress')error(409,'La tarea no está en curso.');
    item.status='resolved';item.resolvedAt=Date.now();item.note=typeof input.note==='string'?input.note.trim().slice(0,200):'';
    notify('citizen',item.id,'¡Problema resuelto!',`Mirá el antes y después de ${item.title.toLowerCase()}.`);
  }else if(action==='support'){
    if(!item.supported){item.supports++;item.supported=true}
  }else if(action==='rate'){
    const rating=Number(input.rating);
    if(item.status!=='resolved'||item.owner!=='vecino'||!Number.isInteger(rating)||rating<1||rating>5)error(400,'Calificación inválida.');
    item.rating=rating;
  }else error(400,'Acción desconocida.');
  storeReport(item);return {ok:true};
}

function json(response,status,payload){response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}).end(JSON.stringify(payload))}
function body(request){return new Promise((resolve,reject)=>{let chunks='';request.on('data',chunk=>{chunks+=chunk;if(chunks.length>16384){request.destroy();reject(new Error('Solicitud demasiado grande.'))}});request.on('end',()=>{try{resolve(JSON.parse(chunks||'{}'))}catch{reject(new Error('JSON inválido.'))}});request.on('error',reject)})}
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.webmanifest':'application/manifest+json; charset=utf-8','.svg':'image/svg+xml'};
const server=http.createServer(async(request,response)=>{
  try{
    const pathname=decodeURIComponent(new URL(request.url,'http://localhost').pathname);
    if(request.method==='GET'&&pathname==='/api/health')return json(response,200,{ok:true,revision});
    if(request.method==='GET'&&pathname==='/api/bootstrap')return json(response,200,snapshot());
    if(request.method==='GET'&&pathname==='/api/analytics')return json(response,200,analytics());
    if(request.method==='GET'&&pathname==='/api/events'){
      response.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-cache, no-transform','Connection':'keep-alive','X-Accel-Buffering':'no'});
      response.write(`data: ${JSON.stringify(snapshot())}\n\n`);clients.add(response);
      request.on('close',()=>clients.delete(response));return;
    }
    if(request.method==='POST'&&pathname==='/api/actions'){
      const input=await body(request);
      db.exec('BEGIN');let result;
      try{result=applyAction(input);db.exec('COMMIT')}catch(issue){db.exec('ROLLBACK');throw issue}
      broadcast();return json(response,200,result);
    }
    if(request.method!=='GET')return json(response,405,{error:'Método no permitido.'});
    const file=path.resolve(root,`.${pathname==='/'?'/index.html':pathname}`);
    if(!file.startsWith(root+path.sep)||!types[path.extname(file)])return json(response,404,{error:'No encontrado.'});
    fs.readFile(file,(issue,content)=>{if(issue)json(response,404,{error:'No encontrado.'});else response.writeHead(200,{'Content-Type':types[path.extname(file)],'Cache-Control':'no-store'}).end(content)});
  }catch(issue){json(response,issue.status||400,{error:issue.message||'Error de servidor.'})}
});
setInterval(()=>{for(const client of clients)client.write(': ping\n\n')},15000).unref();
server.listen(port,host,()=>process.stdout.write(`Maqueta y backend: http://${host}:${port}\nSQLite: ${databasePath}\n`));
