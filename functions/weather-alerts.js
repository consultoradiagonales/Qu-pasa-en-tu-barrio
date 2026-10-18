'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { deliverToUsers } = require('./push-delivery');

const REGION = 'southamerica-east1';
const USER_AGENT = 'ConDi/1.0 (info.consultoradiagonales@gmail.com)';
const HORIZON_HOURS = 24;

// Umbrales sobre el promedio de las fuentes, para las próximas 24 h.
// Nivel 1 = aviso, nivel 2 = alerta. Ajustables sin tocar el resto del código.
const THRESHOLDS = {
  rain: { label: 'Lluvia intensa', unit: 'mm', levels: [40, 80] },
  wind: { label: 'Ráfagas fuertes', unit: 'km/h', levels: [60, 90] },
  heat: { label: 'Calor extremo', unit: '°C', levels: [36, 40] },
  cold: { label: 'Frío extremo', unit: '°C', levels: [0, -4], below: true },
};

const mean = (values) => values.reduce((a, b) => a + b, 0) / values.length;
const finite = (list) => list.filter((n) => typeof n === 'number' && Number.isFinite(n));

async function fetchJson(url, headers = {}) {
  const response = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json', ...headers },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

/** Resume una serie horaria en { rain, gust, tmax, tmin } de las próximas horas. */
function summarize(series) {
  const rain = finite(series.rain).slice(0, HORIZON_HOURS);
  const gust = finite(series.gust).slice(0, HORIZON_HOURS);
  const temp = finite(series.temp).slice(0, HORIZON_HOURS);
  if (!temp.length && !rain.length && !gust.length) return null;
  return {
    rain: rain.reduce((a, b) => a + b, 0),
    gust: gust.length ? Math.max(...gust) : null,
    tmax: temp.length ? Math.max(...temp) : null,
    tmin: temp.length ? Math.min(...temp) : null,
  };
}

/**
 * Open-Meteo con varios modelos globales a la vez (ECMWF, GFS, ICON). Cada
 * modelo cuenta como una fuente independiente.
 */
async function fromOpenMeteo({ lat, lng }) {
  const models = ['ecmwf_ifs025', 'gfs_seamless', 'icon_seamless'];
  const url = 'https://api.open-meteo.com/v1/forecast' +
    `?latitude=${lat}&longitude=${lng}&hourly=precipitation,wind_gusts_10m,temperature_2m` +
    `&forecast_days=2&timezone=America%2FArgentina%2FBuenos_Aires&models=${models.join(',')}`;
  const json = await fetchJson(url);
  const hourly = json.hourly || {};
  const out = [];
  for (const model of models) {
    const summary = summarize({
      rain: hourly[`precipitation_${model}`] || [],
      gust: hourly[`wind_gusts_10m_${model}`] || [],
      temp: hourly[`temperature_2m_${model}`] || [],
    });
    if (summary) out.push({ source: `open-meteo:${model}`, ...summary });
  }
  return out;
}

/** MET Norway (yr.no): modelo distinto, gratuito, exige User-Agent. */
async function fromMetNo({ lat, lng }) {
  const json = await fetchJson(
    `https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat.toFixed(4)}&lon=${lng.toFixed(4)}`,
  );
  const steps = (json.properties?.timeseries || []).slice(0, HORIZON_HOURS);
  const summary = summarize({
    rain: steps.map((s) => s.data?.next_1_hours?.details?.precipitation_amount),
    gust: steps.map((s) => {
      const ms = s.data?.instant?.details?.wind_speed_of_gust ?? s.data?.instant?.details?.wind_speed;
      return typeof ms === 'number' ? ms * 3.6 : null;
    }),
    temp: steps.map((s) => s.data?.instant?.details?.air_temperature),
  });
  return summary ? [{ source: 'met.no', ...summary }] : [];
}

// ---------------------------------------------------------------------------
// Servicio Meteorológico Nacional (SMN): avisos oficiales.
//
// Evidencia (probado el 2026-10-17 desde la máquina de desarrollo, curl con
// headers de navegador y con el User-Agent de ConDi):
//   - https://ws.smn.gob.ar/alerts/type/AL (y /IC, /alerts, /map_items/*,
//     /v1/forecast/*, /geo/provinces, raíz): HTTP 503 de Cloudflare ("No server
//     is available"), también con reintentos; por http responde 301 -> https.
//     Su formato nunca se pudo verificar.
//   - https://ws1.smn.gob.ar/v1/*: HTTP 401 JSON (requiere token).
//   - https://www.smn.gob.ar/* (alertas, descarga-de-datos, cap, rss, feed):
//     HTTP 403 con desafío de Cloudflare ("Just a moment...").
//   - datos.gob.ar (CKAN): HTTP 200, pero solo datasets históricos; no hay
//     feed de avisos vigentes.
//   - https://ssl.smn.gob.ar/CAP/AR.php: HTTP 200 text/html. Es el feed CAP que
//     la OMM registra como autoridad de alertas de Argentina. Lista los avisos
//     vigentes como bloques HTML con un enlace "Ver XML CAP" a
//     https://ssl.smn.gob.ar/feeds/CAP/xml_generados/CAP_<fecha>_<evento>_<region>_alertas_alertas_<n>.xml
//     (HTTP 200 text/xml, CAP 1.2).
// Formato real de cada XML CAP 1.2: <alert> con <msgType> Alert|Update|Cancel,
// <status> Actual, <references> (en Update) y un <info> con <event> (Lluvias,
// Tormentas, Nevadas...), <severity> (Moderate/Severe/Extreme), <onset>,
// <expires>, <headline>, <description>, <instruction> y un <area> cuyo
// <areaDesc> viene VACIO y cuyo <polygon> trae pares "lat,lon". Por eso el
// filtrado por municipio es punto-en-polígono sobre el centroide del municipio;
// nombre/provincia solo sirven de respaldo si algún día viniera areaDesc.
// Solo se observó severity=Moderate (amarillo); Severe=naranja y Extreme=rojo
// son la correspondencia estándar de CAP y no se pudo confirmar con datos reales.
// ---------------------------------------------------------------------------
const SMN_CAP_INDEX = 'https://ssl.smn.gob.ar/CAP/AR.php';
const SMN_LEGACY_URL = 'https://ws.smn.gob.ar/alerts/type/AL';
const SMN_MAX_XML = 80;
const SMN_LOOKAHEAD_HOURS = 36;

// CAP severity -> nivel de color del SMN.
const SMN_LEVELS = {
  moderate: { level: 1, color: 'amarilla' },
  severe: { level: 2, color: 'naranja' },
  extreme: { level: 3, color: 'roja' },
};

const normalizeText = (s) => String(s || '')
  .normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

function decodeXml(s) {
  return String(s || '')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

const xmlTag = (xml, tag) => {
  const m = new RegExp(`<(?:\\w+:)?${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?${tag}>`, 'i').exec(xml);
  return m ? decodeXml(m[1]).trim() : '';
};

/** Tipo de peligro a partir del nombre del evento del SMN. */
function smnHazard(event) {
  const e = normalizeText(event);
  if (/tormenta/.test(e)) return 'storm';
  if (/lluvia|precipit/.test(e)) return 'rain';
  if (/viento|zonda/.test(e)) return 'wind';
  if (/nevad/.test(e)) return 'snow';
  if (/calor/.test(e)) return 'heat';
  if (/frio|helada/.test(e)) return 'cold';
  if (/niebla/.test(e)) return 'fog';
  return e.replace(/\s+/g, '_').slice(0, 20) || 'other';
}

/** Interpreta un XML CAP 1.2 del SMN. Devuelve null si no es un aviso utilizable. */
function parseCapAlert(xml) {
  if (typeof xml !== 'string' || !/<(?:\w+:)?alert[\s>]/i.test(xml)) return null;
  const msgType = xmlTag(xml, 'msgType').toLowerCase();
  const status = xmlTag(xml, 'status').toLowerCase();
  if (msgType === 'cancel' || (status && status !== 'actual')) return null;
  const info = xmlTag(xml, 'info');
  if (!info) return null;
  const mapped = SMN_LEVELS[xmlTag(info, 'severity').toLowerCase()];
  if (!mapped) return null;
  const event = xmlTag(info, 'event') || xmlTag(info, 'headline');
  const polygons = [];
  const polyRe = /<(?:\w+:)?polygon(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?polygon>/gi;
  let m;
  while ((m = polyRe.exec(info))) {
    const ring = decodeXml(m[1]).trim().split(/\s+/).map((pair) => {
      const [lat, lng] = pair.split(',').map(Number);
      return [lat, lng];
    }).filter(([lat, lng]) => Number.isFinite(lat) && Number.isFinite(lng));
    if (ring.length >= 3) polygons.push(ring);
  }
  const areaDesc = [];
  const descRe = /<(?:\w+:)?areaDesc(?:\s[^>]*)?>([\s\S]*?)<\/(?:\w+:)?areaDesc>/gi;
  while ((m = descRe.exec(info))) {
    const text = decodeXml(m[1]).trim();
    if (text) areaDesc.push(text);
  }
  const time = (tag) => {
    const t = Date.parse(xmlTag(info, tag));
    return Number.isFinite(t) ? t : null;
  };
  return {
    event,
    hazard: smnHazard(event),
    level: mapped.level,
    color: mapped.color,
    headline: xmlTag(info, 'headline') || event,
    description: xmlTag(info, 'description'),
    instruction: xmlTag(info, 'instruction'),
    onset: time('onset') ?? time('effective'),
    expires: time('expires'),
    polygons,
    areaDesc,
  };
}

/** Ray casting sobre un anillo [[lat, lng], ...]. */
function pointInRing(lat, lng, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [yi, xi] = ring[i];
    const [yj, xj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/**
 * Avisos CAP vigentes que alcanzan al municipio ({ name, province, lat, lng }).
 * Con polígonos: punto-en-polígono del centroide. Sin polígonos: coincidencia
 * por nombre y provincia (sin acentos ni mayúsculas) en areaDesc.
 */
function matchCapAlerts(alerts, center, now = new Date()) {
  const t = now.getTime();
  const limit = t + SMN_LOOKAHEAD_HOURS * 3600 * 1000;
  const place = normalizeText(center.name);
  const prov = normalizeText(center.province);
  const hasPoint = Number.isFinite(center.lat) && Number.isFinite(center.lng);
  return alerts.filter((a) => {
    if (!a) return false;
    if (a.expires != null && a.expires < t) return false;
    if (a.onset != null && a.onset > limit) return false;
    if (a.polygons.length) {
      return hasPoint && a.polygons.some((ring) => pointInRing(center.lat, center.lng, ring));
    }
    const area = normalizeText(a.areaDesc.join(' '));
    return Boolean(place && area && area.includes(place) && (!prov || area.includes(prov)));
  });
}

/** Elige, por peligro, el aviso de mayor nivel: [{ hazard, level, title, description }]. */
function smnAlertsToMessages(matched) {
  const best = new Map();
  for (const a of matched) {
    const prev = best.get(a.hazard);
    if (!prev || a.level > prev.level) best.set(a.hazard, a);
  }
  return [...best.values()].map((a) => ({
    hazard: a.hazard,
    level: a.level,
    title: `Alerta ${a.color} por ${normalizeText(a.event) || 'fenómeno meteorológico'}`.slice(0, 120),
    description: [a.description, a.instruction].filter(Boolean).join(' ').slice(0, 280),
  }));
}

async function fetchText(url, headers = {}) {
  const response = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,application/xml,text/xml,*/*', ...headers },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
}

/**
 * Descarga una sola vez por corrida el feed CAP del SMN y devuelve los avisos
 * interpretados. Un XML que falla se omite; si el índice falla, lanza.
 */
async function loadSmnCapAlerts(getText = fetchText) {
  const get = async (url) => {
    try {
      return await getText(url);
    } catch (_) {
      return getText(url); // un reintento: Cloudflare devuelve 5xx esporádicos
    }
  };
  const index = await get(SMN_CAP_INDEX);
  const urls = [...new Set(
    [...index.matchAll(/https:\/\/ssl\.smn\.gob\.ar\/feeds\/CAP\/[^"'<>\s]+\.xml/gi)].map((m) => m[0]),
  )].slice(0, SMN_MAX_XML);
  const parsed = await mapWithConcurrency(urls, 6, async (url) => {
    try {
      return parseCapAlert(await get(url));
    } catch (_) {
      return null;
    }
  });
  return parsed.filter(Boolean);
}

/** Respaldo: formato JSON legado de ws.smn.gob.ar (hoy 503, formato no verificado). */
function matchLegacyItems(json, { name, province }) {
  const items = Array.isArray(json) ? json : Array.isArray(json?.alerts) ? json.alerts : [];
  const place = normalizeText(name);
  const prov = normalizeText(province);
  return items
    .filter((item) => {
      const haystack = normalizeText(JSON.stringify(item));
      return place && haystack.includes(place) && (!prov || haystack.includes(prov));
    })
    .map((item) => ({
      hazard: 'legacy',
      level: 1,
      title: String(item.title || item.event || 'Alerta del SMN').slice(0, 120),
      description: String(item.description || item.text || '').slice(0, 280),
    }));
}

/**
 * Avisos oficiales del SMN para un municipio. `capAlerts` (ya descargados)
 * evita repetir la descarga por municipio. Orden: feed CAP -> JSON legado; si
 * ninguno responde lanza (el llamador lo tolera).
 */
async function fromSmnAlerts(center, { capAlerts, now = new Date() } = {}) {
  let capError;
  try {
    const alerts = capAlerts || await loadSmnCapAlerts();
    return smnAlertsToMessages(matchCapAlerts(alerts, center, now));
  } catch (error) {
    capError = error;
  }
  try {
    return matchLegacyItems(await fetchJson(SMN_LEGACY_URL), center);
  } catch (_) {
    throw capError;
  }
}

/** Promedia las fuentes disponibles. Devuelve null si no hay ninguna. */
function averageForecasts(sources) {
  if (!sources.length) return null;
  const pick = (field) => {
    const values = finite(sources.map((s) => s[field]));
    return values.length ? mean(values) : null;
  };
  return {
    sources: sources.length,
    rain: pick('rain'),
    gust: pick('gust'),
    tmax: pick('tmax'),
    tmin: pick('tmin'),
  };
}

/** Devuelve las amenazas que superan algún umbral: [{ hazard, level, value }]. */
function evaluate(avg) {
  if (!avg) return [];
  const readings = { rain: avg.rain, wind: avg.gust, heat: avg.tmax, cold: avg.tmin };
  const found = [];
  for (const [hazard, rule] of Object.entries(THRESHOLDS)) {
    const value = readings[hazard];
    if (typeof value !== 'number') continue;
    let level = 0;
    rule.levels.forEach((limit, index) => {
      if (rule.below ? value <= limit : value >= limit) level = index + 1;
    });
    if (level > 0) found.push({ hazard, level, value: Math.round(value * 10) / 10 });
  }
  return found;
}

function messageFor(municipalityName, threat) {
  const rule = THRESHOLDS[threat.hazard];
  const kind = threat.level === 2 ? 'Alerta' : 'Aviso';
  return {
    title: `${kind}: ${rule.label.toLowerCase()} en ${municipalityName}`,
    body: `Para las próximas 24 h se esperan ${threat.value} ${rule.unit} ` +
      '(promedio de varios servicios meteorológicos). Tomá precauciones.',
  };
}

async function municipalityCenter(db, municipalityId) {
  const cache = db.collection('municipalityGeo').doc(municipalityId);
  const cached = await cache.get();
  if (cached.exists && typeof cached.get('lat') === 'number') return cached.data();
  const id = municipalityId.replace(/^georef_/, '');
  const json = await fetchJson(
    `https://apis.datos.gob.ar/georef/api/municipios?id=${encodeURIComponent(id)}` +
    '&campos=nombre,provincia.nombre,centroide.lat,centroide.lon&max=1',
  );
  const found = json.municipios?.[0];
  if (!found?.centroide) return null;
  const data = {
    name: found.nombre,
    province: found.provincia?.nombre || '',
    lat: found.centroide.lat,
    lng: found.centroide.lon,
  };
  await cache.set(data);
  return data;
}

async function collectSources(center) {
  const settled = await Promise.allSettled([fromOpenMeteo(center), fromMetNo(center)]);
  return settled.flatMap((r) => (r.status === 'fulfilled' ? r.value : []));
}

const AR_TIMEZONE = 'America/Argentina/Buenos_Aires';
const MAX_PARALLEL_MUNICIPALITIES = 5;
const MUNICIPALITY_TIMEOUT_MS = 60000;
const RUN_BUDGET_MS = 240000; // la función tiene 300 s: no se arranca nada nuevo pasado este tiempo
const MAX_ALERT_LEVEL = 3;

const dayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: AR_TIMEZONE, year: 'numeric', month: '2-digit', day: '2-digit',
});

/** Fecha (AAAA-MM-DD) en hora de Argentina, no en UTC. */
function argentinaDay(now = new Date()) {
  return dayFormatter.format(now);
}

/** Corre fn sobre items con a lo sumo `limit` tareas simultáneas; conserva el orden. */
async function mapWithConcurrency(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await fn(items[index], index);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, worker));
  return results;
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout ${label} (${ms} ms)`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Arma las alertas de un municipio (propias + SMN) con su identidad de dedupe:
 * { hazard, level, key, title, body }. `hazard` lleva prefijo smn_ para las del SMN.
 */
function buildAlerts(center, threats, smn) {
  const alerts = threats.map((t) => ({
    hazard: t.hazard,
    level: t.level,
    key: `${t.hazard}_${t.level}`,
    ...messageFor(center.name, t),
  }));
  smn.forEach((a) => {
    const hazard = `smn_${String(a.hazard || 'aviso').replace(/\W+/g, '').slice(0, 24) || 'aviso'}`;
    const level = a.level || 1;
    alerts.push({
      hazard,
      level,
      key: `${hazard}_${level}`,
      title: `SMN: ${a.title}`,
      body: a.description || `El Servicio Meteorológico Nacional emitió una alerta para ${center.name}.`,
    });
  });
  return alerts;
}

/** Ya se envió hoy una alerta del mismo peligro de nivel igual o mayor. */
async function supersededToday(db, municipalityId, day, alert) {
  for (let level = MAX_ALERT_LEVEL; level > alert.level; level--) {
    const snap = await db.collection('weatherAlerts').doc(`${municipalityId}_${day}_${alert.hazard}_${level}`).get();
    if (snap.exists) return true;
  }
  return false;
}

async function processMunicipality(db, municipalityId, recipients, ctx) {
  const out = [];
  const center = await municipalityCenter(db, municipalityId);
  if (!center) return out;
  const avg = averageForecasts(await collectSources(center));
  const threats = evaluate(avg);
  // Si el feed del SMN no respondió (ctx.smnAlerts null) se sigue solo con los modelos.
  const smn = ctx.smnAlerts ? smnAlertsToMessages(matchCapAlerts(ctx.smnAlerts, center, ctx.now)) : [];

  for (const alert of buildAlerts(center, threats, smn)) {
    try {
      if (await supersededToday(db, municipalityId, ctx.day, alert)) continue;
      const alertKey = `${municipalityId}_${ctx.day}_${alert.key}`;
      const alertRef = db.collection('weatherAlerts').doc(alertKey);
      try {
        await alertRef.create({
          municipalityId,
          municipalityName: center.name,
          hazard: alert.hazard,
          level: alert.level,
          day: ctx.day,
          title: alert.title,
          body: alert.body,
          forecast: avg,
          createdAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (error?.code === 6 || error?.code === 'already-exists') continue; // ya enviada hoy
        throw error;
      }
      try {
        const delivered = await deliverToUsers(db, recipients, {
          key: `weather_${alertKey}`,
          type: 'weather_alert',
          title: alert.title,
          body: alert.body,
        });
        out.push({ municipalityId, alert: alert.key, ...delivered });
      } catch (error) {
        // Sin entrega no queda marcada como enviada: la próxima corrida reintenta.
        await alertRef.delete().catch(() => {});
        throw error;
      }
    } catch (error) {
      out.push({ municipalityId, alert: alert.key, error: String(error?.message || error) });
    }
  }
  return out;
}

async function runWeatherAlerts(db = getFirestore(), now = new Date(), options = {}) {
  const parallel = options.parallel || MAX_PARALLEL_MUNICIPALITIES;
  const timeoutMs = options.municipalityTimeoutMs || MUNICIPALITY_TIMEOUT_MS;
  const budgetMs = options.budgetMs || RUN_BUDGET_MS;
  const users = await db.collection('users')
    .where('role', '==', 'citizen')
    .where('disabled', '==', false)
    .get();
  const byMunicipality = new Map();
  users.forEach((doc) => {
    const municipalityId = doc.get('municipalityId');
    if (!municipalityId || !String(municipalityId).startsWith('georef_')) return;
    if (!byMunicipality.has(municipalityId)) byMunicipality.set(municipalityId, []);
    byMunicipality.get(municipalityId).push({ uid: doc.id, fcmToken: doc.get('fcmToken') });
  });

  const ctx = { day: argentinaDay(now), now, smnAlerts: null };
  try {
    // Una sola descarga del feed CAP del SMN para todos los municipios.
    ctx.smnAlerts = await (options.loadSmn || loadSmnCapAlerts)();
  } catch (_) {
    ctx.smnAlerts = null; // SMN fuera de servicio: las otras fuentes alcanzan
  }

  const started = Date.now();
  const summary = [];
  await mapWithConcurrency([...byMunicipality], parallel, async ([municipalityId, recipients]) => {
    if (Date.now() - started > budgetMs) {
      summary.push({ municipalityId, error: 'omitido: se agotó el tiempo de la corrida' });
      return;
    }
    try {
      const results = await withTimeout(
        processMunicipality(db, municipalityId, recipients, ctx), timeoutMs, municipalityId,
      );
      summary.push(...results);
    } catch (error) {
      summary.push({ municipalityId, error: String(error?.message || error) });
    }
  });
  return summary;
}

const weatherAlerts = onSchedule(
  {
    schedule: 'every 3 hours',
    region: REGION,
    timeZone: 'America/Argentina/Buenos_Aires',
    timeoutSeconds: 300,
  },
  async () => {
    const summary = await runWeatherAlerts();
    console.log('weatherAlerts', JSON.stringify(summary));
  },
);

module.exports = {
  weatherAlerts,
  runWeatherAlerts,
  averageForecasts,
  evaluate,
  messageFor,
  summarize,
  collectSources,
  THRESHOLDS,
  argentinaDay,
  mapWithConcurrency,
  withTimeout,
  buildAlerts,
  parseCapAlert,
  pointInRing,
  matchCapAlerts,
  smnAlertsToMessages,
  loadSmnCapAlerts,
  fromSmnAlerts,
  normalizeText,
};
