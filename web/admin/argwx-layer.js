// Capa "Clima y riesgos" del mapa operativo.
//
// Lee los JSON que publica el motor ARGWX (carpeta MOTOR METEOROLOGICO) y
// colorea los partidos según el aviso de la ventana elegida. Es sólo de
// consulta: no cambia estados, prioridades ni asignaciones de reportes, y no
// envía notificaciones. Un dato ausente o vencido nunca se muestra como
// "sin riesgo".
import { ARGWX_ID_BY_GEOREF } from './argwx-municipalities.js';

export const ARGWX_BASE = 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx';
export const ARGWX_DASHBOARD = `${ARGWX_BASE}/`;
export const STALE_AFTER_MS = 3 * 60 * 60 * 1000;
const CACHE_MS = 10 * 60 * 1000;

export const LEVELS = Object.freeze({
  GREEN: { label: 'Verde', meaning: 'Sin fenómenos significativos', color: '#2e9d4f', rank: 0 },
  YELLOW: { label: 'Amarilla', meaning: 'Posibles inconvenientes puntuales', color: '#f2c200', rank: 1 },
  ORANGE: { label: 'Naranja', meaning: 'Fenómenos potencialmente peligrosos', color: '#f07c00', rank: 2 },
  RED: { label: 'Roja', meaning: 'Fenómenos severos', color: '#d62828', rank: 3 },
  PURPLE: { label: 'Púrpura', meaning: 'Evento extremo', color: '#7b2cbf', rank: 4 },
  UNKNOWN: { label: 'Sin dato', meaning: 'No hay información para este período', color: '#6b7280', rank: -1 },
});

export function levelInfo(code) {
  return LEVELS[code] || LEVELS.UNKNOWN;
}

/** `georef_060441` (o `060441`, `06441`) → `la-plata`; null si no está cubierto. */
export function argwxIdFor(municipalityId) {
  let code = String(municipalityId || '').trim().replace(/^georef_/, '');
  if (/^06\d{3}$/.test(code)) code = `060${code.slice(2)}`;
  return ARGWX_ID_BY_GEOREF[code] || null;
}

/**
 * Qué partidos mostrar según el ámbito del panel. Un municipio ve sólo el
 * suyo; el alcance integral o la provincia de Buenos Aires ven los 135.
 */
export function coverageFor(scope) {
  if (!scope || scope.type === 'all') return { mode: 'province', ids: null };
  if (scope.type === 'province') {
    return scope.provinceId === '06'
      ? { mode: 'province', ids: null }
      : { mode: 'none', reason: 'El motor meteorológico cubre por ahora la provincia de Buenos Aires.' };
  }
  const id = argwxIdFor(scope.municipalityId);
  if (!id) return { mode: 'none', reason: 'Este municipio no está cubierto por el motor meteorológico (sólo provincia de Buenos Aires).' };
  return { mode: 'municipality', ids: new Set([id]) };
}

let cache = null;

/** Descarga avisos y límites de partidos; reutiliza la respuesta 10 minutos. */
export async function loadArgwxData({ fetchImpl = fetch, now = Date.now } = {}) {
  if (cache && now() - cache.at < CACHE_MS) return cache.data;
  const get = async (path) => {
    const response = await fetchImpl(`${ARGWX_BASE}/${path}`, { cache: 'no-cache' });
    if (!response.ok) throw new Error('Datos meteorológicos no disponibles por el momento.');
    return response.json();
  };
  const [alerts, geo] = await Promise.all([get('data/alertas_pba.json'), get('geo/municipios_pba.geojson')]);
  if (!alerts || typeof alerts !== 'object' || !geo || !Array.isArray(geo.features)) {
    throw new Error('Datos meteorológicos con formato inesperado.');
  }
  cache = { at: now(), data: { alerts, geo } };
  return cache.data;
}

export function resetArgwxCache() {
  cache = null;
  blindCache = null;
}

let blindCache = null;

/**
 * Puntos ciegos por partido (skill "sesgo del superviviente"): análisis en 7
 * pasos que publica el motor en data/sesgos_pba.json. Devuelve null si todavía
 * no está publicado; no es un error del panel.
 */
export async function loadArgwxBlindspots({ fetchImpl = fetch, now = Date.now } = {}) {
  if (blindCache && now() - blindCache.at < CACHE_MS) return blindCache.data;
  let data = null;
  try {
    const response = await fetchImpl(`${ARGWX_BASE}/data/sesgos_pba.json`, { cache: 'no-cache' });
    if (response.ok) {
      const json = await response.json();
      if (json && typeof json === 'object' && json.windows) data = json;
    }
  } catch (_) {
    data = null;
  }
  blindCache = { at: now(), data };
  return data;
}

/** Partidos del motor (id y nombre), ordenados por nombre. */
export function argwxPartidos({ geo } = {}) {
  return (geo?.features || [])
    .map((f) => ({ id: f?.properties?.id, name: f?.properties?.name || f?.properties?.id }))
    .filter((p) => p.id)
    .sort((a, b) => String(a.name).localeCompare(String(b.name), 'es'));
}

/** Nivel, consenso y lluvia de un partido en las tres ventanas. */
export function partidoWindows({ alerts } = {}, id) {
  return ['24', '48', '72'].map((key) => {
    const window = alerts?.windows?.[key];
    const m = (window?.municipios || []).find((x) => x.id === id) || null;
    const code = m && LEVELS[m.alert_level] ? m.alert_level : 'UNKNOWN';
    return {
      key,
      label: window?.label || `Próximas ${key} h`,
      level: code,
      info: levelInfo(code),
      hazard: m?.hazard || null,
      consensus: m?.consensus || null,
      rainMm: typeof m?.lluvia_mm === 'number' ? m.lluvia_mm : null,
      weighted: m?.ponderado || null,
      entry: m,
    };
  });
}

/** Tablero centrado en un partido. */
export function dashboardUrlFor(id) {
  return id ? `${ARGWX_DASHBOARD}#partido=${encodeURIComponent(id)}` : ARGWX_DASHBOARD;
}

/**
 * Arma lo que dibuja el mapa para una ventana (24, 48 o 72 h). Función pura:
 * no toca el DOM ni Leaflet, para poder probarla.
 */
export function buildWeatherView({ alerts, geo }, coverage, windowKey = '24', nowMs = Date.now()) {
  const generatedAt = Date.parse(alerts?.generated_at || '');
  const window = alerts?.windows?.[windowKey] || null;
  const byId = new Map((window?.municipios || []).map((m) => [m.id, m]));
  const features = [];
  for (const feature of geo?.features || []) {
    const id = feature?.properties?.id;
    if (!id || (coverage.ids && !coverage.ids.has(id))) continue;
    const m = byId.get(id);
    const code = m ? (LEVELS[m.alert_level] ? m.alert_level : 'UNKNOWN') : 'UNKNOWN';
    const info = levelInfo(code);
    const prob10 = m?.prob_lluvia?.['10'];
    features.push({
      feature,
      id,
      name: m?.name || feature.properties.name || id,
      level: code,
      label: info.label,
      color: info.color,
      meaning: info.meaning,
      hazard: m?.hazard || null,
      official: m?.confidence_label === 'Oficial SMN',
      consensus: m?.consensus || null,
      rainMm: typeof m?.lluvia_mm === 'number' ? m.lluvia_mm : null,
      rainOver10: prob10?.confiable === true && typeof prob10.probabilidad === 'number' ? prob10.probabilidad : null,
    });
  }
  features.sort((a, b) => levelInfo(b.level).rank - levelInfo(a.level).rank || a.name.localeCompare(b.name, 'es'));
  const withAlert = features.filter((f) => levelInfo(f.level).rank >= 1);
  return {
    features,
    withAlert,
    missing: features.filter((f) => f.level === 'UNKNOWN').length,
    official: withAlert.filter((f) => f.official).length,
    live: alerts?.data_mode === 'live',
    stale: !Number.isFinite(generatedAt) || nowMs - generatedAt > STALE_AFTER_MS,
    generatedAt: Number.isFinite(generatedAt) ? new Date(generatedAt) : null,
    windowLabel: window?.label || `Próximas ${windowKey} h`,
    validTo: window?.valid_to ? new Date(window.valid_to) : null,
    modelCount: Array.isArray(alerts?.models) ? alerts.models.length : 0,
  };
}

/** Texto corto para la descripción de un partido. */
export function describe(f) {
  const head = f.level === 'GREEN' ? 'Nivel verde'
    : f.level === 'UNKNOWN' ? 'Sin dato para este período'
      : `Alerta ${f.label.toLowerCase()}${f.hazard ? ` por ${f.hazard}` : ''}`;
  const source = f.level === 'UNKNOWN' ? 'No significa ausencia de riesgo.'
    : f.official ? 'Fuente: alerta oficial del SMN'
      : `Análisis ConDi · coinciden ${f.consensus || '-'} modelos`;
  const rain = f.rainMm === null ? '' : `Lluvia estimada ${f.rainMm.toFixed(1)} mm${f.rainOver10 === null ? '' : ` · ${Math.round(f.rainOver10)} % de superar 10 mm`}`;
  return { head, source, rain };
}
