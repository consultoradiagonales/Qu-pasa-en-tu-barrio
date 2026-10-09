const STORAGE_KEY = 'qpbtb-maqueta-v1';
const TEAMS = [
  {id:'norte', name:'Cuadrilla Norte', specialties:['Alumbrado','Infraestructura']},
  {id:'centro', name:'Equipo Centro', specialties:['Limpieza','Infraestructura']},
  {id:'verde', name:'Espacios Verdes', specialties:['Ambiente','Limpieza']},
];
const SEED = [
  {id:'r101',title:'Luminaria apagada en la esquina',description:'La esquina está a oscuras desde hace varios días. Es una zona muy transitada por la noche.',category:'Alumbrado',status:'pending',teamId:null,createdAt:Date.now()-7200000,supports:12,x:31,y:43,owner:'vecino',rating:0},
  {id:'r102',title:'Vereda rota junto a la plaza',description:'Hay baldosas levantadas y se dificulta el paso de cochecitos y personas mayores.',category:'Infraestructura',status:'assigned',teamId:'norte',createdAt:Date.now()-86400000,supports:8,x:70,y:36,owner:'otro',rating:0},
  {id:'r103',title:'Basural retirado de la calle',description:'Se habían acumulado bolsas y residuos en la esquina. El equipo limpió el espacio.',category:'Limpieza',status:'resolved',teamId:'centro',createdAt:Date.now()-172800000,supports:24,x:53,y:72,owner:'vecino',rating:5,arrivedAt:Date.now()-10800000,resolvedAt:Date.now()-7200000},
];
const seedNotifications = [
  {id:'n1',role:'citizen',reportId:'r103',title:'¡Problema resuelto!',body:'La limpieza terminó. Mirá el antes y después.',time:Date.now()-7200000,read:false},
  {id:'n2',role:'coordinator',reportId:'r101',title:'Nuevo reporte en tu municipio',body:'Luminaria apagada en la esquina',time:Date.now()-7200000,read:false},
  {id:'n3',role:'field',reportId:'r102',title:'Nueva tarea asignada',body:'Vereda rota junto a la plaza',time:Date.now()-3600000,read:false},
];
function fresh(){return {reports:structuredClone(SEED),notifications:structuredClone(seedNotifications)}}
function load(){try{const value=JSON.parse(localStorage.getItem(STORAGE_KEY));if(Array.isArray(value?.reports)&&Array.isArray(value?.notifications))return value}catch{}return fresh()}
let data=load();
let backendConnected=false;
const ui={role:'citizen',view:'home',filter:'Todos',selected:'r101',sheet:null,fieldTeam:'norte'};
const app=document.getElementById('app');
const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const report=id=>data.reports.find(item=>item.id===id);
const teamName=id=>TEAMS.find(team=>team.id===id)?.name||'Sin equipo';
const statusText={pending:'Pendiente',assigned:'Asignado',in_progress:'En curso',resolved:'Resuelto'};
const color={pending:'#dc7154',assigned:'#e09a3b',in_progress:'#d6ad3e',resolved:'#42aa70'};
const save=()=>{if(!backendConnected){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(data))}catch{}}};
function localAnalytics(){
  const byStatus={},byCategory={};
  for(const item of data.reports){byStatus[item.status]=(byStatus[item.status]||0)+1;byCategory[item.category]=(byCategory[item.category]||0)+1}
  const resolved=data.reports.filter(r=>r.resolvedAt);
  return {total:data.reports.length,supports:data.reports.reduce((sum,r)=>sum+r.supports,0),
    active:(byStatus.assigned||0)+(byStatus.in_progress||0),byStatus,
    byCategory:Object.entries(byCategory).map(([category,count])=>({category,count})).sort((a,b)=>b.count-a.count),
    avgResolutionHours:resolved.length?Math.round(resolved.reduce((sum,r)=>sum+(r.resolvedAt-r.createdAt)/3600000,0)/resolved.length*10)/10:null};
}
function applySnapshot(snapshot){
  if(!Array.isArray(snapshot?.reports)||!Array.isArray(snapshot?.notifications))return;
  data={reports:snapshot.reports,notifications:snapshot.notifications,analytics:snapshot.analytics};
  if(!report(ui.selected))ui.selected=data.reports[0]?.id||null;
  render();
}
async function refreshBackend(){const response=await fetch('/api/bootstrap',{cache:'no-store'});if(!response.ok)throw new Error('No se pudo leer la base de datos.');applySnapshot(await response.json())}
async function backendAction(payload){
  const response=await fetch('/api/actions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  const result=await response.json();
  if(!response.ok)throw new Error(result.error||'No se pudo guardar el cambio.');
  await refreshBackend();
  return result;
}
async function connectBackend(){
  try{
    await refreshBackend();backendConnected=true;
    document.querySelector('.preview-pill').textContent='● SQLITE · EN VIVO';
    document.querySelector('.studio-foot span').innerHTML='<i class="live-dot"></i> Datos sincronizados con SQLite';
    document.querySelector('.preview-caption').textContent='Los cambios se guardan en SQLite y aparecen en todas las pantallas abiertas.';
    const stream=new EventSource('/api/events');
    stream.onmessage=event=>{try{applySnapshot(JSON.parse(event.data))}catch{}};
    stream.onerror=()=>{document.querySelector('.preview-pill').textContent='● RECONECTANDO';};
    stream.onopen=()=>{document.querySelector('.preview-pill').textContent='● SQLITE · EN VIVO';};
  }catch{
    document.querySelector('.preview-pill').textContent='● DEMO SIN CONEXIÓN';
  }
}
function ago(time){const hours=Math.floor((Date.now()-time)/3600000);return hours<1?'Ahora':hours<24?`Hace ${hours} h`:`Hace ${Math.floor(hours/24)} d`}
function toast(message){const el=document.getElementById('toast');el.textContent=message;el.classList.add('show');clearTimeout(toast.timeout);toast.timeout=setTimeout(()=>el.classList.remove('show'),2700)}
function status(item){return `<span class="status ${item.status}">${statusText[item.status]}</span>`}
function header(title,subtitle='',back=false,right=''){return `<header class="app-header"><div class="header-left">${back?'<button class="icon-button" data-action="back" aria-label="Volver">‹</button>':''}<div>${subtitle?`<small>${esc(subtitle)}</small>`:''}<h2>${esc(title)}</h2></div></div>${right}</header>`}
function nav(){
  const items=ui.role==='citizen'?[['home','⌂','Mapa'],['reports','▤','Mis reportes'],['alerts','♧','Alertas'],['profile','◉','Perfil']]:ui.role==='coordinator'?[['home','▦','Panel'],['reports','☷','Reportes'],['alerts','♧','Alertas'],['profile','◉','Perfil']]:[['home','▤','Tareas'],['reports','✓','Hoy'],['alerts','♧','Alertas'],['profile','◉','Perfil']];
  return `<nav class="nav" aria-label="Navegación principal">${items.map(([view,symbol,label])=>`<button data-action="view" data-view="${view}" class="${ui.view===view?'active':''}"><strong>${symbol}</strong>${label}</button>`).join('')}</nav>`;
}
function mapMarkup(items,small=false){return `<div class="map ${small?'mini-map':''}"><div class="map-road road-one"></div><div class="map-road road-two"></div><div class="map-road road-three"></div><span class="map-label a">PLAZA DEL BARRIO</span><span class="map-label b">AV. PRINCIPAL</span>${items.map(r=>`<button class="map-pin ${r.id===ui.selected?'selected':''}" style="left:${r.x}%;top:${r.y}%;background:${color[r.status]}" data-action="pin" data-id="${r.id}" aria-label="Ver ${esc(r.title)}"><span>!</span></button>`).join('')}<div class="map-caption">◎ Barrio Centro · municipio demo</div></div>`}
function chips(values){return `<div class="chips">${values.map(label=>`<button class="chip ${ui.filter===label?'active':''}" data-action="filter" data-filter="${label}">${label}</button>`).join('')}</div>`}
function filtered(items){return ui.filter==='Todos'?items:items.filter(item=>statusText[item.status]===ui.filter||item.category===ui.filter)}
function card(item,coordinator=false){return `<article class="report-card"><button data-action="open" data-id="${item.id}"><div class="card-top"><span class="kicker">${esc(item.category)} · ${ago(item.createdAt)}</span>${status(item)}</div><h4>${esc(item.title)}</h4><p>${esc(item.description)}</p><div class="card-bottom"><span>◎ Barrio Centro</span><span>♥ ${item.supports} apoyos</span></div></button>${coordinator&&['pending','assigned'].includes(item.status)?`<div class="assignment"><span>${esc(teamName(item.teamId))}</span><button class="small-btn" data-action="assign" data-id="${item.id}">${item.teamId?'Reasignar':'Asignar equipo'} →</button></div>`:''}</article>`}
function citizenHome(){const items=filtered(data.reports);const selected=report(ui.selected)||items[0];return `${header('¿Qué pasa en tu barrio?','BUEN DÍA, VECINA',false,'<div class="avatar">VB</div>')}<div class="content"><section class="hero"><span class="eyebrow">PARTICIPACIÓN CIUDADANA</span><h3>Tu barrio mejora cuando participás.</h3><p>Reportá un problema y seguí cada paso hasta su solución.</p><button data-action="create">＋ Crear un reporte</button></section><div class="section-heading"><h3>Explorá tu zona</h3><button class="text-link" data-action="view" data-view="reports">Ver todos →</button></div>${chips(['Todos','Pendiente','Asignado','En curso','Resuelto'])}<div style="height:11px"></div>${mapMarkup(items)}<div class="legend"><span><i style="background:#dc7154"></i>Pendiente</span><span><i style="background:#e09a3b"></i>Asignado</span><span><i style="background:#42aa70"></i>Resuelto</span></div><div class="section-heading"><h3>Cerca tuyo</h3><span class="subtle">${items.length} reportes</span></div>${selected&&items.includes(selected)?card(selected):'<p class="list-empty">No hay reportes con este filtro.</p>'}</div><button class="fab" data-action="create">＋ Reportar</button>${nav()}`}
function citizenReports(){let items=data.reports.filter(r=>r.owner==='vecino');items=filtered(items);return `${header('Mis reportes','SEGUIMIENTO')}<div class="content">${chips(['Todos','Pendiente','Asignado','En curso','Resuelto'])}<div style="height:12px"></div>${items.length?items.map(r=>card(r)).join(''):'<div class="list-empty">Todavía no tenés reportes con ese estado.</div>'}</div>${nav()}`}
function coordinatorHome(){
  const all=data.reports,stats=data.analytics||localAnalytics();
  const pending=stats.byStatus.pending||0,active=stats.active||0,solved=stats.byStatus.resolved||0;
  const items=filtered(all),max=Math.max(1,...stats.byCategory.map(row=>row.count));
  const chart=stats.byCategory.map(row=>`<div class="chart-row"><span>${esc(row.category)}</span><div class="chart-track"><i style="width:${Math.round(row.count/max*100)}%"></i></div><b>${row.count}</b></div>`).join('');
  return `${header('Panel municipal','COORDINACIÓN',false,'<div class="avatar">CO</div>')}
    <div class="content">
      <div class="metric-grid"><div class="metric"><strong>${pending}</strong><span>PENDIENTES</span></div><div class="metric"><strong>${active}</strong><span>EN GESTIÓN</span></div><div class="metric highlight"><strong>${solved}</strong><span>RESUELTOS</span></div></div>
      <div class="analytics-panel"><div class="analytics-top"><div><strong>Pulso del municipio</strong><small>${backendConnected?'Actualización en tiempo real':'Vista de demostración'}</small></div><span class="analytics-live">● EN VIVO</span></div><div class="analytics-mini"><span><b>${stats.total}</b> casos</span><span><b>${stats.supports}</b> apoyos</span><span><b>${stats.avgResolutionHours??'—'} h</b> resolución prom.</span></div>${chart}</div>
      <div class="section-heading"><h3>Reportes del municipio</h3><span class="subtle">${all.length} en total</span></div>${chips(['Todos','Pendiente','Asignado','En curso','Resuelto'])}<div style="height:10px"></div>${items.length?items.map(r=>card(r,true)).join(''):'<div class="list-empty">No hay reportes con este filtro.</div>'}
    </div>${nav()}`;
}
function fieldHome(){const items=data.reports.filter(r=>r.teamId===ui.fieldTeam&&['assigned','in_progress','resolved'].includes(r.status));const shown=ui.view==='reports'?items.filter(r=>r.status==='resolved'):items.filter(r=>r.status!=='resolved');return `${header(ui.view==='reports'?'Resueltas hoy':'Mis tareas',teamName(ui.fieldTeam).toUpperCase(),false,'<div class="avatar">⚒</div>')}<div class="content"><div class="field-banner"><span class="big">⌁</span><div><strong>Tu trabajo transforma el barrio.</strong><small>Documentá cada etapa para que los vecinos vean el cambio.</small></div></div><div class="section-heading"><h3>Equipo simulado</h3></div><div class="chips">${TEAMS.map(team=>`<button class="chip ${ui.fieldTeam===team.id?'active':''}" data-action="field-team" data-team="${team.id}">${esc(team.name)}</button>`).join('')}</div><div class="section-heading"><h3>${ui.view==='reports'?'Tareas terminadas':'Asignadas a tu equipo'}</h3><span class="subtle">${shown.length} tareas</span></div>${shown.length?shown.map(r=>card(r)).join(''):'<div class="list-empty">No hay tareas en esta sección. Asigná un reporte desde Coordinación para probar el flujo.</div>'}</div>${nav()}`}
function alerts(){const items=data.notifications.filter(n=>n.role===ui.role).sort((a,b)=>b.time-a.time);return `${header('Notificaciones','ACTUALIZACIONES')}<div>${items.length?items.map(n=>`<div class="alert-card ${n.read?'':'unread'}"><span class="alert-icon">${n.role==='field'?'⚒':'✦'}</span><div><strong>${esc(n.title)}</strong><p>${esc(n.body)}</p><small>${ago(n.time)}</small><button class="text-link" data-action="notification" data-id="${n.id}">Ver reporte →</button></div></div>`).join(''):'<div class="list-empty">Sin notificaciones por ahora.</div>'}</div>${nav()}`}
function profile(){const who=ui.role==='citizen'?'Vecina del barrio':ui.role==='coordinator'?'Coordinación municipal':teamName(ui.fieldTeam);return `${header('Mi perfil','MODO DEMOSTRACIÓN')}<div class="content"><div class="field-banner"><span class="big">◉</span><div><strong>${who}</strong><small>Municipio demo · Barrio Centro</small></div></div><div class="section-heading"><h3>Acerca de esta maqueta</h3></div><div class="report-card"><p>${backendConnected?'Los reportes y avisos se guardan en SQLite y se sincronizan en tiempo real con las demás pantallas abiertas.':'Sin conexión al backend: esta pantalla usa datos locales de demostración.'} La cámara y las imágenes son simuladas.</p></div><button class="secondary-btn" data-action="reset">Reiniciar datos de ejemplo</button></div>${nav()}`}
function streetScene(category,after){const isLight=category==='Alumbrado',isWalk=category==='Infraestructura';const issue=isLight?(after?'<circle cx="458" cy="103" r="63" fill="#ffe6a0" opacity=".35"/><path d="M458 106 L399 279 L524 279Z" fill="#fff1a5" opacity=".36"/>':'<circle cx="458" cy="103" r="8" fill="#5c6474"/>'):(isWalk?(after?'<path d="M0 296 H600" stroke="#c5bfb3" stroke-width="4"/><path d="M58 295V400 M215 295V400 M370 295V400 M520 295V400" stroke="#c5bfb3" stroke-width="3"/>':'<path d="M80 320l65 15 40-10 42 25 68-7 32 22 67-6" fill="none" stroke="#736e6a" stroke-width="8" stroke-linejoin="round"/>'):(after?'':'<g fill="#505860"><path d="M345 295q18-37 38-3l9 28h-57z"/><path d="M383 300q20-43 48-5l9 31h-67z"/><path d="M438 307q13-28 31-2l8 22h-46z"/></g><path d="M362 293l8-16 9 14 M399 290l12-17 9 22" stroke="#343c42" stroke-width="5" fill="none"/>'));return `<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" role="img" aria-label="Ilustración ${after?'después':'antes'}"><rect width="600" height="400" fill="${after?'#c3e5de':'#cbd8df'}"/><circle cx="83" cy="62" r="35" fill="${after?'#fff0ae':'#e8edf0'}"/><rect y="210" width="600" height="95" fill="#c8d4c1"/><rect x="0" y="132" width="150" height="105" fill="#e7e1cc"/><rect x="21" y="159" width="55" height="60" fill="#8ba6a2"/><rect x="165" y="90" width="145" height="160" fill="#f2e8d9"/><rect x="181" y="110" width="39" height="44" fill="#91aba7"/><rect x="246" y="110" width="40" height="44" fill="#91aba7"/><rect x="220" y="181" width="51" height="69" fill="#a9806e"/><rect x="497" y="135" width="103" height="112" fill="#eadac4"/><rect x="513" y="158" width="47" height="46" fill="#89a8a6"/><path d="M0 275h600v125H0z" fill="#b6b7ae"/><path d="M0 330h600" stroke="#f7f0d9" stroke-width="5" stroke-dasharray="55 40"/><path d="M0 273h600" stroke="#e5dfce" stroke-width="10"/><path d="M458 110v164" stroke="#586a6d" stroke-width="8"/><path d="M458 107h42" stroke="#586a6d" stroke-width="7"/><circle cx="501" cy="107" r="10" fill="${after?'#ffe198':'#697883'}"/><path d="M76 263v-95" stroke="#6d795f" stroke-width="12"/><circle cx="74" cy="141" r="50" fill="#7ba985"/><circle cx="42" cy="163" r="33" fill="#71a17d"/><circle cx="105" cy="164" r="34" fill="#6e9b76"/>${issue}<rect width="600" height="400" fill="${after?'#ffffff':'#53636f'}" opacity="${after?'.03':'.10'}"/></svg>`}
function comparison(item){return `<div class="comparison" style="--split:50%"><div class="scene">${streetScene(item.category,false)}</div><div class="scene after-layer">${streetScene(item.category,true)}</div><div class="compare-line"></div><div class="compare-handle">⇆</div><span class="compare-tag before">ANTES</span><span class="compare-tag after">DESPUÉS</span><input type="range" min="5" max="95" value="50" aria-label="Deslizar comparación antes y después" data-action="compare"></div>`}
function detail(){const item=report(ui.selected);if(!item)return citizenHome();const resolved=item.status==='resolved';return `${header('Detalle del reporte','BARRIO CENTRO',true,'<button class="icon-button" data-action="support" aria-label="Apoyar reporte">♡</button>')}<div class="detail-hero">${streetScene(item.category,resolved)}<span class="photo-badge">◎ Evidencia del ${resolved?'resultado':'problema'}</span></div><div class="detail-head">${status(item)}<h3>${esc(item.title)}</h3><p>${esc(item.description)}</p><div class="card-bottom"><span>◈ ${esc(item.category)}</span><span>♥ ${item.supports} apoyos · ${ago(item.createdAt)}</span></div></div>${resolved?`<div class="detail-section"><h4>El cambio, a la vista</h4>${comparison(item)}<p class="subtle">Arrastrá el control para comparar el antes y el después.</p></div>`:''}<div class="detail-section"><h4>Seguimiento</h4><div class="timeline"><div class="timeline-item"><strong>Reporte recibido</strong>${ago(item.createdAt)}</div>${item.teamId?`<div class="timeline-item"><strong>Asignado a ${esc(teamName(item.teamId))}</strong>El municipio tomó el caso.</div>`:''}${item.arrivedAt?'<div class="timeline-item"><strong>Equipo en el lugar</strong>Se registró la llegada.</div>':''}${resolved?'<div class="timeline-item"><strong>Trabajo terminado</strong>Resolución documentada.</div>':''}</div></div>${resolved?`<div class="detail-section"><div class="notice"><strong>Respuesta oficial</strong>El trabajo fue realizado y documentado por ${esc(teamName(item.teamId))}.</div></div>`:''}${resolved&&item.owner==='vecino'?`<div class="detail-section"><h4>¿Cómo quedó el trabajo?</h4><div class="stars" aria-label="Calificar">${[1,2,3,4,5].map(n=>`<button data-action="rate" data-rating="${n}" class="${n>(item.rating||0)?'off':''}" aria-label="${n} estrellas">★</button>`).join('')}</div></div>`:''}<div class="detail-section"><button class="secondary-btn" data-action="support">♡ Apoyar este reporte</button></div>`}
function create(){return `${header('Nuevo reporte','CONTANOS QUÉ PASA',true)}<div class="content"><form id="report-form"><label class="form-field"><span>TÍTULO DEL PROBLEMA</span><input name="title" maxlength="80" required placeholder="Ej.: Bache en la esquina"></label><label class="form-field"><span>DESCRIPCIÓN</span><textarea name="description" maxlength="500" required placeholder="Contanos dónde está y qué ocurre..."></textarea></label><label class="form-field"><span>CATEGORÍA</span><select name="category"><option>Infraestructura</option><option>Alumbrado</option><option>Limpieza</option><option>Ambiente</option><option>Seguridad</option><option>Salud</option><option>Transporte</option></select></label><div class="photo-demo"><div><strong>▧</strong>Foto ilustrativa del problema<br><span class="subtle">La app real abre cámara o galería</span></div></div><div class="form-note">◎ Ubicación de ejemplo: Barrio Centro. En la app real se toma del mapa o GPS.</div><button class="primary-btn coral" type="submit">Publicar reporte →</button></form></div>`}
function fieldTask(){const item=report(ui.selected);if(!item)return fieldHome();return `${header('Detalle de tarea',teamName(item.teamId).toUpperCase(),true)}<div class="detail-hero">${streetScene(item.category,item.status==='resolved')}<span class="photo-badge">◎ Barrio Centro</span></div><div class="detail-head">${status(item)}<h3>${esc(item.title)}</h3><p>${esc(item.description)}</p></div><div class="detail-section"><h4>Ubicación</h4>${mapMarkup([item],true)}<p class="subtle">Equipo asignado: ${esc(teamName(item.teamId))}</p></div><div class="detail-section stack">${item.status==='assigned'?`<div class="form-note">Al llegar, registrá una foto del estado actual antes de empezar. Esta maqueta simula la cámara.</div><button class="primary-btn" data-action="arrive" data-id="${item.id}">◎ Estoy en el lugar · foto antes</button>`:item.status==='in_progress'?`<div class="timer"><strong data-timer="${item.arrivedAt||Date.now()}">00:00:00</strong><span>TIEMPO EN EL LUGAR</span></div><label class="form-field"><span>NOTA DEL TÉCNICO</span><textarea id="worker-note" maxlength="200" placeholder="¿Qué trabajo se realizó?"></textarea></label><button class="secondary-btn" data-action="progress-photo">＋ Foto del proceso (opcional) ${item.progressPhotos?'· '+item.progressPhotos:''}</button><button class="primary-btn green" data-action="finish" data-id="${item.id}">✓ Trabajo terminado · foto después</button>`:'<div class="notice"><strong>Tarea terminada</strong>La resolución ya está disponible para el vecino.</div>'}</div>`}
function renderSheet(){if(!ui.sheet)return '';const item=report(ui.sheet);if(!item)return '';return `<div class="sheet-backdrop" data-action="close-sheet"><div class="sheet" role="dialog" aria-modal="true" aria-label="Asignar equipo"><div class="sheet-handle"></div><h3>Asignar un equipo</h3><p>${esc(item.title)} · Elegí la cuadrilla responsable.</p>${TEAMS.map(team=>`<button class="team-option" data-action="team" data-team="${team.id}"><span class="team-icon">⚒</span><span><strong>${esc(team.name)}</strong><small>${esc(team.specialties.join(' · '))}</small></span><b>›</b></button>`).join('')}</div></div>`}
let lastView='home',lastRole='citizen';
function render(){
  const sameView=lastView===ui.view&&lastRole===ui.role,scroll=app.scrollTop;
  const draftTitle=sameView?document.querySelector('#report-form [name="title"]')?.value:null;
  const draftDescription=sameView?document.querySelector('#report-form [name="description"]')?.value:null;
  const draftCategory=sameView?document.querySelector('#report-form [name="category"]')?.value:null;
  const draftNote=sameView?document.getElementById('worker-note')?.value:null;
  document.querySelectorAll('[data-role]').forEach(button=>{button.classList.toggle('active',button.dataset.role===ui.role);button.setAttribute('aria-pressed',String(button.dataset.role===ui.role))});
  const content=ui.view==='detail'?detail():ui.view==='create'?create():ui.view==='task'?fieldTask():ui.view==='alerts'?alerts():ui.view==='profile'?profile():ui.role==='citizen'?(ui.view==='reports'?citizenReports():citizenHome()):ui.role==='coordinator'?coordinatorHome():fieldHome();
  app.innerHTML=`<div class="statusbar"><span>9:41</span><span>●●● ▰</span></div><div class="screen ${['detail','create','task'].includes(ui.view)?'full':''}">${content}</div>${renderSheet()}`;
  if(draftTitle!=null&&document.querySelector('#report-form [name="title"]')){document.querySelector('#report-form [name="title"]').value=draftTitle;document.querySelector('#report-form [name="description"]').value=draftDescription;document.querySelector('#report-form [name="category"]').value=draftCategory}
  if(draftNote!=null&&document.getElementById('worker-note'))document.getElementById('worker-note').value=draftNote;
  app.scrollTop=sameView?scroll:0;lastView=ui.view;lastRole=ui.role;updateTimers();
}
function notification(role,reportId,title,body){data.notifications.unshift({id:'n'+Math.random().toString(36).slice(2),role,reportId,title,body,time:Date.now(),read:false})}
document.addEventListener('click',async event=>{
  const roleButton=event.target.closest('[data-role]');if(roleButton){ui.role=roleButton.dataset.role;ui.view='home';ui.filter='Todos';ui.sheet=null;render();return}
  if(event.target.closest('#reset-demo')){
    try{if(backendConnected)await backendAction({action:'reset'});else{data=fresh();save()}ui.role='citizen';ui.view='home';ui.filter='Todos';ui.selected='r101';ui.sheet=null;render();toast('Demo reiniciada')}catch(issue){toast(issue.message)}return;
  }
  const target=event.target.closest('[data-action]');if(!target||!app.contains(target))return;
  const action=target.dataset.action,id=target.dataset.id;
  try{
  if(action==='view'){ui.view=target.dataset.view;ui.filter='Todos'}
  if(action==='filter'){ui.filter=target.dataset.filter}
  if(action==='field-team'){ui.fieldTeam=target.dataset.team}
  if(action==='pin'){ui.selected=id;ui.filter='Todos'}
  if(action==='open'){ui.selected=id;ui.view=ui.role==='field'?'task':'detail'}
  if(action==='create'){ui.view='create'}
  if(action==='back'){ui.view='home'}
  if(action==='assign'){ui.sheet=id;ui.selected=id}
  if(action==='close-sheet'){ui.sheet=null}
  if(action==='team'){
    const item=report(ui.sheet);if(item){
      if(backendConnected)await backendAction({action:'assign',id:item.id,teamId:target.dataset.team});
      else{item.teamId=target.dataset.team;item.status='assigned';notification('citizen',item.id,'Reporte asignado',item.title);notification('field',item.id,'Nueva tarea asignada',item.title);save()}
      toast('Equipo asignado y avisos generados');
    }ui.sheet=null;
  }
  if(action==='arrive'){
    const item=report(id);if(item?.status==='assigned'){
      if(backendConnected)await backendAction({action:'arrive',id});
      else{item.status='in_progress';item.arrivedAt=Date.now();notification('citizen',id,'Equipo en el lugar',item.title);save()}
      toast('Llegada y foto del antes registradas');
    }
  }
  if(action==='progress-photo'){
    const item=report(ui.selected);if(item){
      if(backendConnected)await backendAction({action:'progress_photo',id:item.id});
      else{item.progressPhotos=(item.progressPhotos||0)+1;save()}
      toast('Foto del proceso agregada (simulación)');
    }
  }
  if(action==='finish'){
    const item=report(id);if(item?.status==='in_progress'){
      const note=document.getElementById('worker-note')?.value.trim()||'';
      if(backendConnected)await backendAction({action:'finish',id,note});
      else{item.status='resolved';item.resolvedAt=Date.now();item.note=note;notification('citizen',id,'¡Problema resuelto!',`Mirá el antes y después de ${item.title.toLowerCase()}.`);save()}
      toast('Trabajo resuelto y vecino notificado');
    }
  }
  if(action==='support'){
    const item=report(ui.selected);if(item&&!item.supported){
      if(backendConnected)await backendAction({action:'support',id:item.id});
      else{item.supports++;item.supported=true;save()}
      toast('Gracias por apoyar este reporte');
    }else toast('Ya apoyaste este reporte');
  }
  if(action==='rate'){
    const item=report(ui.selected);if(item){
      const rating=Number(target.dataset.rating);
      if(backendConnected)await backendAction({action:'rate',id:item.id,rating});
      else{item.rating=rating;save()}
      toast('Gracias por calificar el trabajo');
    }
  }
  if(action==='notification'){
    const note=data.notifications.find(n=>n.id===id);if(note){
      if(backendConnected)await backendAction({action:'mark_read',id});
      else{note.read=true;save()}
      ui.selected=note.reportId;ui.view=ui.role==='field'?'task':'detail';
    }
  }
  if(action==='reset'){
    if(backendConnected)await backendAction({action:'reset'});
    else{data=fresh();save()}
    ui.view='home';ui.filter='Todos';ui.selected='r101';toast('Datos reiniciados');
  }
  render();
  }catch(issue){toast(issue.message||'No se pudo guardar el cambio.');render()}
});
app.addEventListener('submit',async event=>{
  if(event.target.id!=='report-form')return;event.preventDefault();
  const form=new FormData(event.target),title=String(form.get('title')||'').trim(),description=String(form.get('description')||'').trim(),category=String(form.get('category'));
  if(!title||!description)return;
  try{
    if(backendConnected){const result=await backendAction({action:'create',title,description,category});ui.selected=result.id}
    else{const item={id:'r'+Date.now(),title,description,category,status:'pending',teamId:null,createdAt:Date.now(),supports:0,x:26+Math.round(Math.random()*52),y:27+Math.round(Math.random()*43),owner:'vecino',rating:0};data.reports.unshift(item);notification('coordinator',item.id,'Nuevo reporte en tu municipio',title);save();ui.selected=item.id}
    ui.view='detail';render();toast('Reporte publicado · coordinación recibió un aviso');
  }catch(issue){toast(issue.message||'No se pudo publicar el reporte.')}
});
app.addEventListener('input',event=>{if(event.target.dataset.action==='compare'){event.target.closest('.comparison').style.setProperty('--split',`${event.target.value}%`)}});
function updateTimers(){document.querySelectorAll('[data-timer]').forEach(el=>{const seconds=Math.max(0,Math.floor((Date.now()-Number(el.dataset.timer))/1000));const h=String(Math.floor(seconds/3600)).padStart(2,'0'),m=String(Math.floor(seconds%3600/60)).padStart(2,'0'),s=String(seconds%60).padStart(2,'0');el.textContent=`${h}:${m}:${s}`})}
setInterval(updateTimers,1000);
render();
if(window.QPBTB_OFFLINE_DEMO){
  document.querySelector('.preview-pill').textContent='● DEMO PORTÁTIL';
  document.querySelector('.studio-foot span').innerHTML='<i class="live-dot"></i> Funciona sin servidor ni conexión';
  document.querySelector('.preview-caption').textContent='Una demostración interactiva para recorrer la experiencia completa.';
}else{
  connectBackend();
  if('serviceWorker' in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});
}
