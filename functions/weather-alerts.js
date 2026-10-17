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

/**
 * Servicio Meteorológico Nacional: alertas oficiales vigentes. No son números
 * sino avisos, así que se tratan aparte: si el SMN emitió algo que menciona el
 * municipio, la alerta sale aunque el promedio no llegue al umbral.
 * La respuesta se interpreta de forma tolerante porque el formato no está
 * documentado de manera estable.
 */
async function fromSmnAlerts({ name, province }) {
  const json = await fetchJson('https://ws.smn.gob.ar/alerts/type/AL');
  const items = Array.isArray(json) ? json : Array.isArray(json?.alerts) ? json.alerts : [];
  const norm = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const place = norm(name);
  const prov = norm(province);
  return items
    .filter((item) => {
      const haystack = norm(JSON.stringify(item));
      return place && haystack.includes(place) && (!prov || haystack.includes(prov));
    })
    .map((item) => ({
      title: String(item.title || item.event || 'Alerta del SMN').slice(0, 120),
      description: String(item.description || item.text || '').slice(0, 280),
    }));
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

async function runWeatherAlerts(db = getFirestore(), now = new Date()) {
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

  const day = now.toISOString().slice(0, 10);
  const summary = [];
  for (const [municipalityId, recipients] of byMunicipality) {
    try {
      const center = await municipalityCenter(db, municipalityId);
      if (!center) continue;
      const avg = averageForecasts(await collectSources(center));
      const threats = evaluate(avg);
      let smn = [];
      try {
        smn = await fromSmnAlerts(center);
      } catch (_) {
        // El SMN puede estar fuera de servicio: las otras fuentes alcanzan.
      }

      const alerts = threats.map((t) => ({ key: `${t.hazard}_${t.level}`, ...messageFor(center.name, t) }));
      smn.forEach((a, index) => alerts.push({
        key: `smn_${index}_${a.title.replace(/\W+/g, '').slice(0, 24)}`,
        title: `SMN: ${a.title}`,
        body: a.description || `El Servicio Meteorológico Nacional emitió una alerta para ${center.name}.`,
      }));

      for (const alert of alerts) {
        const alertKey = `${municipalityId}_${day}_${alert.key}`;
        const alertRef = db.collection('weatherAlerts').doc(alertKey);
        try {
          await alertRef.create({
            municipalityId,
            municipalityName: center.name,
            title: alert.title,
            body: alert.body,
            forecast: avg,
            createdAt: FieldValue.serverTimestamp(),
          });
        } catch (error) {
          if (error?.code === 6 || error?.code === 'already-exists') continue; // ya enviada hoy
          throw error;
        }
        const delivered = await deliverToUsers(db, recipients, {
          key: `weather_${alertKey}`,
          type: 'weather_alert',
          title: alert.title,
          body: alert.body,
        });
        summary.push({ municipalityId, alert: alert.key, ...delivered });
      }
    } catch (error) {
      summary.push({ municipalityId, error: String(error?.message || error) });
    }
  }
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
};
