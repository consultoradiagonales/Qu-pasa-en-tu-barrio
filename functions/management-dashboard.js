'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldPath, Timestamp } = require('firebase-admin/firestore');
const { createHash, randomUUID } = require('node:crypto');
const { isCentralAdmin, canManageMunicipality } = require('./management-access');

const PAGE_SIZE = 500;
const MAX_REPORTS = 50000;
const CACHE_MS = 5 * 60000;
const CLOSED = new Set(['resolved', 'closed', 'rejected']);
const STATUSES = new Set(['pending', 'assigned', 'in_progress', 'resolved', 'closed', 'rejected']);

function millis(value) {
  const result = value?.toMillis?.() ?? value?.toDate?.()?.getTime?.() ?? (value instanceof Date ? value.getTime() : NaN);
  return Number.isFinite(result) ? result : null;
}

function emptyStats() {
  return { total: 0, open: 0, unassigned: 0, field: 0, resolvedWeek: 0, over72h: 0,
    highPriorityOpen: 0, unknownStatus: 0, byStatus: {}, categories: {},
    averageResolutionHours: null, medianResolutionHours: null, p90ResolutionHours: null };
}

function aggregateManagementReports(documents, now = new Date()) {
  const totals = emptyStats();
  const groups = new Map();
  const durations = new Map([[totals, []]]);
  function add(stats, report) {
    stats.total++;
    const status = STATUSES.has(report.status) ? report.status : 'unknown';
    stats.byStatus[status] = (stats.byStatus[status] || 0) + 1;
    const category = ['infrastructure','lighting','garbage','security','health','transport','environment','other'].includes(report.category) ? report.category : 'other';
    stats.categories[category] = (stats.categories[category] || 0) + 1;
    if (status === 'unknown') stats.unknownStatus++;
    const created = millis(report.createdAt);
    if (!CLOSED.has(status)) {
      stats.open++;
      if (!report.assignedTeamId) stats.unassigned++;
      if (Number(report.priority) >= 4) stats.highPriorityOpen++;
      if (created !== null && now.getTime() - created >= 72 * 3600000) stats.over72h++;
    }
    if (['assigned','in_progress'].includes(status)) stats.field++;
    const resolved = millis(report.resolvedAt) ?? millis(report.workFinishedAt);
    if (['resolved','closed'].includes(status) && resolved !== null) {
      if (resolved >= now.getTime() - 7 * 86400000 && resolved <= now.getTime()) stats.resolvedWeek++;
      if (created !== null && resolved >= created && resolved <= now.getTime()) durations.get(stats).push((resolved - created) / 3600000);
    }
  }
  for (const doc of documents) {
    const report = typeof doc.data === 'function' ? doc.data() : doc;
    if (report.hidden !== false) continue;
    const municipalityId = typeof report.municipalityId === 'string' && report.municipalityId ? report.municipalityId : '__unscoped__';
    let group = groups.get(municipalityId);
    if (!group) {
      group = { municipalityId, municipalityName: typeof report.municipalityName === 'string' ? report.municipalityName.slice(0, 160) : municipalityId, provinceId: typeof report.provinceId === 'string' ? report.provinceId : '', ...emptyStats() };
      groups.set(municipalityId, group);
      durations.set(group, []);
    }
    add(totals, report);
    add(group, report);
  }
  for (const [stats, values] of durations) {
    values.sort((a,b)=>a-b);
    if (values.length) {
      stats.averageResolutionHours = values.reduce((sum,value)=>sum+value,0) / values.length;
      const middle = Math.floor(values.length / 2);
      stats.medianResolutionHours = values.length % 2 ? values[middle] : (values[middle-1] + values[middle]) / 2;
      stats.p90ResolutionHours = values[Math.ceil(values.length * .9)-1];
    }
  }
  return { totals, municipalities: [...groups.values()].sort((a,b)=>b.open-a.open || a.municipalityId.localeCompare(b.municipalityId)), unscopedReports: groups.get('__unscoped__')?.total || 0 };
}

async function loadManagementReports(db, municipalityId) {
  let source = db.collection('reports').where('hidden','==',false);
  if (municipalityId) source = source.where('municipalityId','==',municipalityId);
  source = source.orderBy(FieldPath.documentId()).select('municipalityId','municipalityName','provinceId','status','category','priority','assignedTeamId','createdAt','resolvedAt','workFinishedAt','hidden');
  const docs=[];
  let cursor;
  while (true) {
    let page = source.limit(Math.min(PAGE_SIZE, MAX_REPORTS + 1 - docs.length));
    if (cursor) page = page.startAfter(cursor);
    const snapshot = await page.get();
    docs.push(...snapshot.docs);
    if (docs.length > MAX_REPORTS) throw new HttpsError('resource-exhausted', 'El volumen requiere agregación programada. No se mostrará un total parcial.');
    if (snapshot.size < PAGE_SIZE) break;
    cursor = snapshot.docs.at(-1);
  }
  return docs;
}

async function getManagementDashboardHandler(request, deps = {}) {
  const uid=request.auth?.uid;
  if(!uid) throw new HttpsError('unauthenticated','Tenés que iniciar sesión.');
  const db=deps.db || getFirestore();
  const profile=(await db.collection('users').doc(uid).get()).data();
  const central=isCentralAdmin(profile);
  const requested=request.data?.municipalityId;
  const provinceId=request.data?.provinceId || '';
  if(typeof provinceId!=='string' || (provinceId && !/^\d{2}$/.test(provinceId))) throw new HttpsError('invalid-argument','La provincia no es válida.');
  if(requested!==undefined && (typeof requested!=='string' || requested.length>128 || requested.includes('/'))) throw new HttpsError('invalid-argument','El ámbito no es válido.');
  if(requested && provinceId) throw new HttpsError('invalid-argument','Elegí un municipio o una provincia.');
  if(!central && (provinceId || request.data?.scope==='all' || (requested && requested!==profile?.municipalityId))) throw new HttpsError('permission-denied','Sólo podés consultar tu municipio.');
  const municipalityId=central ? requested || '' : profile?.municipalityId;
  if(!central && !canManageMunicipality(profile,municipalityId)) throw new HttpsError('permission-denied','No tenés permisos de gestión.');
  const now=deps.now || new Date();
  const key=createHash('sha256').update(municipalityId || (provinceId ? `province:${provinceId}` : '__all__')).digest('hex');
  const ref=db.collection('managementDashboardCache').doc(key);
  const lease=randomUUID();
  const reserved=await db.runTransaction(async tx=>{
    const cached=(await tx.get(ref)).data();
    if(cached?.result && millis(cached.expiresAt)>now.getTime()) return {result:cached.result};
    if(millis(cached?.leaseUntil)>now.getTime()) return {busy:true};
    tx.set(ref,{leaseOwner:lease,leaseUntil:Timestamp.fromMillis(now.getTime()+60000)},{merge:true});
    return {};
  });
  if(reserved.result) return {...reserved.result,cached:true};
  if(reserved.busy) throw new HttpsError('unavailable','El tablero se está actualizando. Volvé a intentar en unos segundos.');
  try {
    const docs=await loadManagementReports(db,municipalityId);
    const inferredProvince = doc => {
      const data=doc.data();
      if(typeof data.provinceId==='string' && /^\d{2}$/.test(data.provinceId)) return data.provinceId;
      const id=String(data.municipalityId || '').replace(/^georef_/, '');
      if(/^\d{5,6}$/.test(id)) return id.slice(0,2);
      return ['la-plata','saladillo','trenque-lauquen','escobar','rivadavia'].includes(id)?'06':'';
    };
    const selected=provinceId?docs.filter(doc=>inferredProvince(doc)===provinceId):docs;
    const result={...aggregateManagementReports(selected,now),scope:{municipalityId:municipalityId || null,provinceId:provinceId || null},complete:true,visibility:'reports_hidden_false',scannedReports:docs.length,unclassifiedProvinceReports:provinceId?docs.filter(doc=>!inferredProvince(doc)).length:0,generatedAt:new Date().toISOString(),cachedUntil:new Date(now.getTime()+CACHE_MS).toISOString()};
    await db.runTransaction(async tx=>{
      if((await tx.get(ref)).get('leaseOwner')===lease) tx.set(ref,{result,expiresAt:Timestamp.fromMillis(now.getTime()+CACHE_MS),leaseUntil:Timestamp.fromMillis(0)});
    });
    return {...result,cached:false};
  } catch(error) {
    await db.runTransaction(async tx=>{
      if((await tx.get(ref)).get('leaseOwner')===lease) tx.set(ref,{leaseUntil:Timestamp.fromMillis(0)},{merge:true});
    });
    throw error;
  }
}

const getManagementDashboard=onCall({region:'southamerica-east1',timeoutSeconds:120,memory:'512MiB',maxInstances:2},getManagementDashboardHandler);
module.exports={getManagementDashboard,getManagementDashboardHandler,aggregateManagementReports,loadManagementReports};
