'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { GoogleAuth } = require('google-auth-library');

if (!getApps().length) initializeApp();

const db = getFirestore();
const PROJECT = 'project-5fc9024a-e961-42b7-9ee';
const REGION = 'southamerica-east1';
const MODEL = 'gemini-3.1-flash-lite';
const AI_SERVICE_ACCOUNT = `condi-ai@${PROJECT}.iam.gserviceaccount.com`;
const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});
const ROLES = ['coordinator', 'admin', 'moderator'];
const CLOSED_STATUSES = new Set(['resolved', 'closed', 'rejected']);

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    summary: { type: 'STRING' },
    priorities: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          title: { type: 'STRING' },
          evidence: { type: 'STRING' },
          action: { type: 'STRING' },
        },
        required: ['title', 'evidence', 'action'],
      },
    },
    strategies: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          title: { type: 'STRING' },
          objective: { type: 'STRING' },
          action: { type: 'STRING' },
          resourceImpact: { type: 'STRING' },
        },
        required: ['title', 'objective', 'action', 'resourceImpact'],
      },
    },
    risks: { type: 'ARRAY', items: { type: 'STRING' } },
    questions: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['summary', 'priorities', 'strategies', 'risks', 'questions'],
};

function clean(value, max) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f]/g, ' ').replace(/https?:\/\/\S+/gi, '[enlace omitido]').trim().slice(0, max)
    : '';
}

function cleanItems(value, fields, limit) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, limit).map((item) => {
    const result = {};
    for (const [name, max] of Object.entries(fields)) result[name] = clean(item?.[name], max);
    return result;
  }).filter((item) => Object.values(item).every(Boolean));
}

function normalize(value) {
  if (!value || typeof value.summary !== 'string' || !Array.isArray(value.priorities) ||
      !Array.isArray(value.strategies) || !Array.isArray(value.risks) || !Array.isArray(value.questions)) {
    throw new Error('invalid_response');
  }
  return {
    summary: clean(value.summary, 800),
    priorities: cleanItems(value.priorities, { title: 120, evidence: 220, action: 260 }, 5),
    strategies: cleanItems(value.strategies, {
      title: 120, objective: 220, action: 280, resourceImpact: 100,
    }, 4),
    risks: value.risks.slice(0, 5).map((item) => clean(item, 220)).filter(Boolean),
    questions: value.questions.slice(0, 5).map((item) => clean(item, 220)).filter(Boolean),
  };
}

function asDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  return null;
}

function number(value, fallback = 0) {
  const result = Number(value);
  return Number.isFinite(result) ? result : fallback;
}

function increment(object, key) {
  object[key] = (object[key] || 0) + 1;
}

function ordered(object) {
  return Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b)));
}

function leadingKey(object, fallback = 'other') {
  return Object.entries(object).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] || fallback;
}

// Agrupa localmente por cuadrículas de aproximadamente 1 km. Solo se devuelve
// a Gemini el volumen de cada zona, nunca coordenadas, direcciones ni textos.
function registerZone(zones, report, status, category) {
  const latitude = number(report.location?.lat, NaN);
  const longitude = number(report.location?.lng, NaN);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
  const key = `${Math.floor(latitude / 0.01)}:${Math.floor(longitude / 0.01)}`;
  const zone = zones.get(key) || {
    reports: 0, active: 0, highPriority: 0, support: 0, categories: {},
  };
  zone.reports += 1;
  if (!CLOSED_STATUSES.has(status)) zone.active += 1;
  if (!CLOSED_STATUSES.has(status) && number(report.priority, 1) >= 4) zone.highPriority += 1;
  zone.support += Math.max(0, Math.trunc(number(report.supportCount)));
  increment(zone.categories, category);
  zones.set(key, zone);
}

function aggregate(docs, now = new Date()) {
  const statuses = {};
  const categories = {};
  const daily = {};
  const aging = { under24h: 0, from24hTo72h: 0, over72h: 0 };
  const zones = new Map();
  let resolved = 0;
  let resolutionHours = 0;
  let pendingWithoutTeam = 0;
  let activeInField = 0;
  let highPriorityOpen = 0;
  let supportLoad = 0;
  let recent = 0;
  let previous = 0;

  for (const doc of docs) {
    const report = doc.data();
    const status = typeof report.status === 'string' ? report.status : 'pending';
    const category = typeof report.category === 'string' ? report.category : 'other';
    const created = asDate(report.createdAt);
    const closed = CLOSED_STATUSES.has(status);

    increment(statuses, status);
    increment(categories, category);
    supportLoad += Math.max(0, Math.trunc(number(report.supportCount)));
    registerZone(zones, report, status, category);

    if (status === 'pending' && !report.assignedTeamId) pendingWithoutTeam += 1;
    if (status === 'assigned' || status === 'in_progress') activeInField += 1;
    if (!closed && number(report.priority, 1) >= 4) highPriorityOpen += 1;

    if (created) {
      const day = created.toISOString().slice(0, 10);
      increment(daily, day);
      const ageHours = Math.max(0, (now - created) / 3600000);
      if (!closed) {
        if (ageHours < 24) aging.under24h += 1;
        else if (ageHours < 72) aging.from24hTo72h += 1;
        else aging.over72h += 1;
      }
      if (ageHours <= 7 * 24) recent += 1;
      else if (ageHours <= 14 * 24) previous += 1;
    }

    const finished = asDate(report.resolvedAt) || asDate(report.workFinishedAt);
    if ((status === 'resolved' || status === 'closed') && created && finished) {
      resolved += 1;
      resolutionHours += Math.max(0, (finished - created) / 3600000);
    }
  }

  const hotspots = [...zones.values()]
    .sort((a, b) => {
      const scoreA = a.active * 5 + a.highPriority * 4 + a.support + a.reports;
      const scoreB = b.active * 5 + b.highPriority * 4 + b.support + b.reports;
      return scoreB - scoreA || b.reports - a.reports;
    })
    .slice(0, 5)
    .map((zone, index) => ({
      label: `Zona de concentración ${index + 1}`,
      reports: zone.reports,
      active: zone.active,
      highPriority: zone.highPriority,
      support: zone.support,
      leadingCategory: leadingKey(zone.categories),
    }));

  return {
    total: docs.length,
    statuses: ordered(statuses),
    categories: ordered(categories),
    daily: ordered(daily),
    resolved,
    averageResolutionHours: resolved ? Math.round((resolutionHours / resolved) * 10) / 10 : null,
    operational: {
      pendingWithoutTeam,
      activeInField,
      highPriorityOpen,
      supportLoad,
    },
    aging,
    trend: {
      recent7Days: recent,
      previous7Days: previous,
      variation: recent - previous,
    },
    hotspots,
  };
}

function promptFor(aggregateData, periodDays) {
  return `Sos analista de gestión urbana para ConDi. Elaborá un informe breve para un equipo municipal en español argentino. Las recomendaciones son sugerencias para una decisión humana: no ordenes acciones automáticas ni prometas resultados. Usá exclusivamente los datos operativos agregados provistos. No inventes barrios, direcciones, causas, responsables, presupuestos, tendencias ni datos que no estén respaldados. No pidas ni infieras identidad de personas. Las zonas están anonimizadas y no incluyen coordenadas. Señalá claramente cuando la muestra sea pequeña. Priorizá seguridad operativa, tiempos de respuesta y uso eficiente de cuadrillas. Incluí entre una y cuatro estrategias con objetivo, acción y nivel de impacto de recursos. Devolvé JSON válido según el esquema. Datos agregados del período de ${periodDays} días: ${JSON.stringify(aggregateData)}`;
}

function emptyReport() {
  return {
    summary: 'No hay reportes en el período seleccionado para elaborar recomendaciones.',
    priorities: [],
    strategies: [],
    risks: [],
    questions: ['Verificá que el municipio tenga reportes geolocalizados y actualizados.'],
  };
}

async function askGemini(data, token) {
  const response = await fetch(`https://aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/global/publishers/google/models/${MODEL}:generateContent`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: promptFor(data.aggregate, data.periodDays) }] }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 1800,
        responseMimeType: 'application/json',
        responseSchema: SCHEMA,
      },
    }),
    signal: AbortSignal.timeout(40000),
  });
  if (!response.ok) throw new Error(`vertex_${response.status}`);
  const body = await response.json();
  const text = body.candidates?.[0]?.content?.parts
    ?.filter((part) => typeof part.text === 'string')
    .map((part) => part.text).join('');
  if (!text) throw new Error('model_unavailable');
  return normalize(JSON.parse(text));
}

async function generateMunicipalityReportHandler(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');

  const data = request.data || {};
  const profileSnap = await db.collection('users').doc(uid).get();
  const profile = profileSnap.data();
  if (!profile || profile.disabled === true || !ROLES.includes(profile.role)) {
    throw new HttpsError('permission-denied', 'No tenés permisos para generar informes.');
  }

  const requested = typeof data.municipalityId === 'string' ? data.municipalityId : '';
  const municipalityId = profile.role === 'admin' && requested ? requested : profile.municipalityId;
  if (!municipalityId) {
    throw new HttpsError('failed-precondition', 'El perfil no tiene municipio.');
  }

  const periodDays = Math.max(7, Math.min(90, Math.trunc(number(data.periodDays, 30))));
  const since = new Date(Date.now() - periodDays * 86400000);
  const snap = await db.collection('reports')
    .where('municipalityId', '==', municipalityId)
    .where('createdAt', '>=', Timestamp.fromDate(since))
    .limit(1000)
    .get();
  const aggregateData = aggregate(snap.docs);
  let generated;
  if (aggregateData.total === 0) {
    generated = emptyReport();
  } else {
    try {
      const token = await auth.getAccessToken();
      if (!token) throw new Error('missing_access_token');
      generated = await askGemini({ aggregate: aggregateData, periodDays }, token);
    } catch (error) {
      // El log no incluye reportes, coordenadas, tokens ni datos personales.
      console.warn('ConDi dashboard AI unavailable', { reason: clean(error?.message, 80) });
      throw new HttpsError('unavailable', 'El análisis no está disponible en este momento.');
    }
  }

  return {
    status: 'ready',
    periodDays,
    totalReports: aggregateData.total,
    ...generated,
  };
}

const generateMunicipalityReport = onCall({
  region: REGION,
  serviceAccount: AI_SERVICE_ACCOUNT,
  memory: '512MiB',
  timeoutSeconds: 60,
  maxInstances: 2,
  concurrency: 1,
}, generateMunicipalityReportHandler);

module.exports = {
  generateMunicipalityReport,
  generateMunicipalityReportHandler,
  aggregate,
  normalize,
  promptFor,
  emptyReport,
};
