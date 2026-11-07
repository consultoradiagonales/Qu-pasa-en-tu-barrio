'use strict';

const { createHash } = require('node:crypto');
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

function stableHash(value, length = 16) {
  return createHash('sha256').update(String(value || '')).digest('hex').slice(0, length);
}

function capVersionKey(alert = {}) {
  return stableHash(JSON.stringify({
    identifier: alert.identifier || '',
    sent: alert.sent || null,
    event: alert.event || '',
    level: alert.level || 0,
    onset: alert.onset || null,
    expires: alert.expires || null,
    headline: alert.headline || '',
    description: alert.description || '',
    polygons: alert.polygons || [],
    areaDesc: alert.areaDesc || [],
  }));
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
  const alert = {
    identifier: xmlTag(xml, 'identifier'),
    sent: (() => {
      const parsed = Date.parse(xmlTag(xml, 'sent'));
      return Number.isFinite(parsed) ? parsed : null;
    })(),
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
  alert.versionKey = capVersionKey(alert);
  return alert;
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

/** Elige, por peligro, el aviso de mayor nivel sin perder su área oficial. */
function smnAlertsToMessages(matched, now = new Date()) {
  const best = new Map();
  const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
  const better = (candidate, previous) => {
    if (!previous || candidate.level !== previous.level) return !previous || candidate.level > previous.level;
    const candidateCurrent = candidate.onset == null || candidate.onset <= nowMs;
    const previousCurrent = previous.onset == null || previous.onset <= nowMs;
    if (candidateCurrent !== previousCurrent) return candidateCurrent;
    if (!candidateCurrent && candidate.onset !== previous.onset) {
      return (candidate.onset ?? Infinity) < (previous.onset ?? Infinity);
    }
    if (candidate.sent !== previous.sent) return (candidate.sent ?? 0) > (previous.sent ?? 0);
    if (candidate.expires !== previous.expires) return (candidate.expires ?? Infinity) < (previous.expires ?? Infinity);
    return String(candidate.identifier || '').localeCompare(String(previous.identifier || '')) > 0;
  };
  for (const a of matched) {
    const prev = best.get(a.hazard);
    if (better(a, prev)) best.set(a.hazard, a);
  }
  return [...best.values()].map((a) => ({
    hazard: a.hazard,
    level: a.level,
    title: `Alerta ${a.color} por ${normalizeText(a.event) || 'fenómeno meteorológico'}`.slice(0, 120),
    description: [a.description, a.instruction].filter(Boolean).join(' ').slice(0, 3200),
    onset: a.onset,
    expires: a.expires,
    polygons: a.polygons,
    areaDesc: a.areaDesc,
    versionKey: a.versionKey || capVersionKey(a),
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
  // El RSS del SMN mezcla enlaces absolutos, relativos y algunos malformados
  // como `https:///feeds/...`; tomar la ruta canónica evita perder los avisos
  // de corto plazo.
  const urls = [...new Set(
    [...index.matchAll(/\/feeds\/CAP\/[^"'<>\s]+\.xml/gi)]
      .map((m) => `https://ssl.smn.gob.ar${m[0]}`),
  )].slice(0, SMN_MAX_XML);
  let fetchedXml = 0;
  const parsed = await mapWithConcurrency(urls, 6, async (url) => {
    try {
      const xml = await get(url);
      fetchedXml += 1;
      return parseCapAlert(xml);
    } catch (_) {
      return null;
    }
  });
  if (urls.length && fetchedXml < Math.ceil(urls.length / 2)) {
    throw new Error(`SMN CAP incompleto: ${fetchedXml}/${urls.length} XML disponibles`);
  }
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
    return smnAlertsToMessages(matchCapAlerts(alerts, center, now), now);
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
    body: `Ciudad: ${municipalityName}. Zona monitoreada: ${municipalityName} y alrededores. ` +
      `Para las próximas 24 h se esperan ${threat.value} ${rule.unit} ` +
      '(promedio de varios servicios meteorológicos). Tomá precauciones.',
  };
}

function asText(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : '';
}

function canonicalMunicipalityId(value) {
  const id = asText(value);
  const numeric = /^(?:georef_)?(\d+)$/i.exec(id);
  return numeric ? `georef_${numeric[1]}` : id;
}

function coordinateFrom(value) {
  if (!value || typeof value !== 'object') return null;
  const lat = Number(value.lat ?? value.latitude ?? value._latitude);
  const lng = Number(value.lng ?? value.lon ?? value.longitude ?? value._longitude);
  return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
}

function hintsFrom(data = {}) {
  return {
    name: asText(data.name || data.displayName || data.municipalityName),
    province: asText(data.province || data.provinceName),
  };
}

async function municipalityCenter(db, municipalityId, profileHints = {}) {
  const cache = db.collection('municipalityGeo').doc(municipalityId);
  const cached = await cache.get();
  if (cached.exists && typeof cached.get('lat') === 'number') return cached.data();

  let municipalData = {};
  try {
    const municipality = await db.collection('municipalities').doc(municipalityId).get();
    if (municipality.exists) municipalData = municipality.data() || {};
  } catch (_) {
    // La geocodificación pública sigue disponible si la colección administrativa aún no existe.
  }
  const profileMetadata = hintsFrom(profileHints);
  const municipalMetadata = hintsFrom(municipalData);
  const metadata = {
    name: municipalMetadata.name || profileMetadata.name,
    province: municipalMetadata.province || profileMetadata.province,
  };
  const directPoint = coordinateFrom(
    municipalData.mapCenter ?? municipalData.center ?? municipalData.location ?? municipalData,
  );
  if (directPoint) {
    const data = {
      name: metadata.name || municipalityId,
      province: metadata.province,
      ...directPoint,
    };
    await cache.set(data);
    return data;
  }

  const id = String(municipalityId).replace(/^georef_/, '');
  let found = null;
  if (/^\d+$/.test(id)) {
    const json = await fetchJson(
      `https://apis.datos.gob.ar/georef/api/municipios?id=${encodeURIComponent(id)}` +
      '&campos=nombre,provincia.nombre,centroide.lat,centroide.lon&max=1',
    );
    found = json.municipios?.[0] || null;
  }
  if (!found && metadata.name) {
    const params = new URLSearchParams({
      nombre: metadata.name,
      campos: 'nombre,provincia.nombre,centroide.lat,centroide.lon',
      max: '20',
    });
    if (metadata.province) params.set('provincia', metadata.province);
    const json = await fetchJson(`https://apis.datos.gob.ar/georef/api/municipios?${params}`);
    const candidates = Array.isArray(json.municipios) ? json.municipios : [];
    const wantedName = normalizeText(metadata.name);
    const wantedProvince = normalizeText(metadata.province);
    found = candidates.find((item) => normalizeText(item?.nombre) === wantedName &&
      (!wantedProvince || normalizeText(item?.provincia?.nombre) === wantedProvince)) ||
      candidates.find((item) => normalizeText(item?.nombre) === wantedName) || null;
  }
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

/** Catálogo provincial de municipios para traducir el polígono del SMN a nombres. */
async function provinceMunicipalities(province, cache = new Map()) {
  const key = normalizeText(province);
  if (!key) return [];
  if (!cache.has(key)) {
    const request = (async () => {
      const params = new URLSearchParams({
        provincia: province,
        campos: 'nombre,provincia.nombre,centroide.lat,centroide.lon',
        max: '1000',
      });
      const json = await fetchJson(`https://apis.datos.gob.ar/georef/api/municipios?${params}`);
      return (Array.isArray(json.municipios) ? json.municipios : [])
        .map((item) => ({
          name: asText(item?.nombre),
          province: asText(item?.provincia?.nombre),
          lat: Number(item?.centroide?.lat),
          lng: Number(item?.centroide?.lon),
        }))
        .filter((item) => item.name && Number.isFinite(item.lat) && Number.isFinite(item.lng));
    })();
    cache.set(key, request);
  }
  return cache.get(key);
}

/**
 * Nombres de municipios cuyo centroide cae dentro del polígono oficial.
 * La ciudad del usuario siempre aparece primera y el resto se ordena por
 * cercanía, para que el texto corto del push muestre primero lo más útil.
 */
function affectedMunicipalityNames(center, alert, municipalities = [], limit = 8) {
  const polygons = Array.isArray(alert?.polygons) ? alert.polygons : [];
  const inside = polygons.length
    ? municipalities.filter((place) =>
      polygons.some((ring) => pointInRing(place.lat, place.lng, ring)))
    : [];
  inside.sort((a, b) => {
    const da = (a.lat - center.lat) ** 2 + (a.lng - center.lng) ** 2;
    const db = (b.lat - center.lat) ** 2 + (b.lng - center.lng) ** 2;
    return da - db;
  });

  const names = [];
  const seen = new Set();
  const add = (name) => {
    const value = asText(name);
    const key = normalizeText(value);
    if (value && key && !seen.has(key)) {
      seen.add(key);
      names.push(value);
    }
  };
  add(center.name);
  inside.forEach((place) => add(place.name));
  return names.slice(0, limit);
}

function affectedAreaText(center, alert) {
  const names = Array.isArray(alert?.affectedZones) ? alert.affectedZones.filter(Boolean) : [];
  const official = Array.isArray(alert?.areaDesc) ? alert.areaDesc.filter(Boolean).join('; ') : '';
  if (names.length > 1) {
    return names.join(', ');
  }
  if (official) return `${center.name}; ${official}`;
  return `${center.name} y zonas aledañas dentro del área oficial del SMN`;
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
const alertDateTimeFormatter = new Intl.DateTimeFormat('es-AR', {
  timeZone: AR_TIMEZONE,
  weekday: 'long',
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

/** Fecha (AAAA-MM-DD) en hora de Argentina, no en UTC. */
function argentinaDay(now = new Date()) {
  return dayFormatter.format(now);
}

function argentinaDateTime(value) {
  if (value == null || value === '') return '';
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) return '';
  const parts = Object.fromEntries(
    alertDateTimeFormatter.formatToParts(date).map((part) => [part.type, part.value]),
  );
  return `${parts.weekday} ${parts.day}/${parts.month} a las ${parts.hour}:${parts.minute}`;
}

function alertTimingText(alert) {
  const onset = argentinaDateTime(alert?.onset);
  const expires = argentinaDateTime(alert?.expires);
  if (onset && expires) return `Vigencia estimada: desde el ${onset} hasta el ${expires}.`;
  if (onset) return `Inicio estimado: ${onset}.`;
  if (expires) return `Vigente hasta el ${expires}.`;
  return '';
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
    municipalityName: center.name,
    province: asText(center.province),
    affectedZones: [center.name],
    affectedArea: `${center.name} y alrededores`,
    versionKey: 'daily',
    ...messageFor(center.name, t),
  }));
  smn.forEach((a) => {
    const hazard = `smn_${String(a.hazard || 'aviso').replace(/\W+/g, '').slice(0, 24) || 'aviso'}`;
    const level = a.level || 1;
    const affectedZones = Array.isArray(a.affectedZones) && a.affectedZones.length
      ? a.affectedZones
      : [center.name];
    const affectedArea = affectedAreaText(center, { ...a, affectedZones });
    const place = [center.name, asText(center.province)].filter(Boolean).join(', ');
    const description = a.description ||
      'El Servicio Meteorológico Nacional emitió una alerta para esta zona.';
    const timing = alertTimingText(a);
    alerts.push({
      hazard,
      level,
      key: `${hazard}_${level}`,
      municipalityName: center.name,
      province: asText(center.province),
      affectedZones,
      affectedArea,
      onset: Number.isFinite(a.onset) ? a.onset : null,
      expires: Number.isFinite(a.expires) ? a.expires : null,
      versionKey: a.versionKey || capVersionKey(a),
      title: `SMN: ${a.title} en ${center.name}`.slice(0, 120),
      body: (`Ciudad: ${place}. ${timing} Zonas afectadas: ${affectedArea}. ${description}`)
        .replace(/\s+/g, ' ').trim().slice(0, 4000),
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

async function processMunicipality(db, municipalityId, recipients, ctx, profileHints = {}) {
  const out = [];
  const center = await municipalityCenter(db, municipalityId, profileHints);
  if (!center) return out;
  const avg = averageForecasts(await collectSources(center));
  const threats = evaluate(avg);
  // Si el feed del SMN no respondió (ctx.smnAlerts null) se sigue solo con los modelos.
  let smn = ctx.smnAlerts ? smnAlertsToMessages(matchCapAlerts(ctx.smnAlerts, center, ctx.now), ctx.now) : [];
  if (smn.length) {
    let catalog = [];
    try {
      if (smn.some((alert) => alert.polygons?.length)) {
        catalog = await provinceMunicipalities(center.province, ctx.provinceMunicipalities);
      }
    } catch (_) {
      // Si GeoRef no responde, la ciudad y el área oficial siguen informadas.
    }
    smn = smn.map((alert) => ({
      ...alert,
      affectedZones: affectedMunicipalityNames(center, alert, catalog),
    }));
  }

  for (const alert of buildAlerts(center, threats, smn)) {
    try {
      if (await supersededToday(db, municipalityId, ctx.day, alert)) continue;
      const alertKey = `${municipalityId}_${ctx.day}_${alert.key}`;
      const alertRef = db.collection('weatherAlerts').doc(alertKey);
      const versionKey = alert.versionKey || 'daily';
      let useLegacyDeliveryKey = false;
      const record = {
        municipalityId,
        municipalityName: center.name,
        province: alert.province,
        affectedZones: alert.affectedZones,
        affectedArea: alert.affectedArea,
        onset: alert.onset ?? null,
        expires: alert.expires ?? null,
        versionKey,
        hazard: alert.hazard,
        level: alert.level,
        day: ctx.day,
        title: alert.title,
        body: alert.body,
        forecast: avg,
      };
      try {
        await alertRef.create({
          ...record,
          createdAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (error?.code === 6 || error?.code === 'already-exists') {
          const existing = await alertRef.get();
          // Corregida o anulada desde el panel: la corrida automática no la
          // pisa ni la vuelve a enviar.
          if (existing.get('adminEdited') === true) continue;
          const existingVersionKey = asText(existing.get('versionKey'));
          // Las alertas creadas antes del versionado ya usaron
          // `weather_${alertKey}`. Se conserva esa clave una vez para que los
          // destinatarios existentes no reciban un duplicado tras el despliegue,
          // mientras que un usuario nuevo sí puede recibir la alerta vigente.
          useLegacyDeliveryKey = !existingVersionKey;
          if (existingVersionKey !== versionKey) {
            await alertRef.set({ ...record, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
          }
        } else {
          throw error;
        }
      }
      try {
        const rawDeliveryKey = useLegacyDeliveryKey
          ? `weather_${alertKey}`
          : `weather_${alertKey}_${versionKey}`;
        const deliveryKey = /^[A-Za-z0-9_-]{1,180}$/.test(rawDeliveryKey)
          ? rawDeliveryKey
          : `weather_${stableHash(alertKey, 24)}_${versionKey}`;
        const delivered = await deliverToUsers(db, recipients, {
          key: deliveryKey,
          type: 'weather_alert',
          title: alert.title,
          body: alert.body,
          data: {
            municipalityId,
            municipalityName: alert.municipalityName,
            province: alert.province,
            affectedZones: alert.affectedZones,
            affectedArea: alert.affectedArea,
            onset: alert.onset ?? '',
            expires: alert.expires ?? '',
            versionKey,
          },
        });
        if (delivered.pushed + delivered.inApp > 0) {
          out.push({ municipalityId, alert: alert.key, ...delivered });
        }
      } catch (error) {
        // La próxima corrida reintenta por usuario; los ids de notificación son idempotentes.
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
    const municipalityId = canonicalMunicipalityId(doc.get('municipalityId'));
    if (!municipalityId) return;
    if (!byMunicipality.has(municipalityId)) {
      byMunicipality.set(municipalityId, {
        recipients: [],
        hints: {
          name: asText(doc.get('municipalityName')),
          province: asText(doc.get('province')),
        },
      });
    }
    const group = byMunicipality.get(municipalityId);
    if (!group.hints.name) group.hints.name = asText(doc.get('municipalityName'));
    if (!group.hints.province) group.hints.province = asText(doc.get('province'));
    group.recipients.push({ uid: doc.id, fcmToken: doc.get('fcmToken') });
  });

  const ctx = {
    day: argentinaDay(now),
    now,
    smnAlerts: null,
    provinceMunicipalities: new Map(),
  };
  try {
    // Una sola descarga del feed CAP del SMN para todos los municipios.
    ctx.smnAlerts = await (options.loadSmn || loadSmnCapAlerts)();
  } catch (_) {
    ctx.smnAlerts = null; // SMN fuera de servicio: las otras fuentes alcanzan
  }

  const started = Date.now();
  const summary = [];
  await mapWithConcurrency([...byMunicipality], parallel, async ([municipalityId, group]) => {
    if (Date.now() - started > budgetMs) {
      summary.push({ municipalityId, error: 'omitido: se agotó el tiempo de la corrida' });
      return;
    }
    try {
      const results = await withTimeout(
        processMunicipality(db, municipalityId, group.recipients, ctx, group.hints), timeoutMs, municipalityId,
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
    schedule: 'every 30 minutes',
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
  stableHash,
  runWeatherAlerts,
  averageForecasts,
  evaluate,
  messageFor,
  summarize,
  collectSources,
  THRESHOLDS,
  argentinaDay,
  argentinaDateTime,
  alertTimingText,
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
  canonicalMunicipalityId,
  municipalityCenter,
  provinceMunicipalities,
  affectedMunicipalityNames,
  affectedAreaText,
};
