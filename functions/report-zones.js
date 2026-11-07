'use strict';

// Zonas de reportes: cada 30 minutos agrupa los reportes de cada municipio en
// una cuadrícula de ~500 m, calcula una prioridad por celda (verde, amarilla,
// naranja, roja) y redacta un análisis de evidencia ausente siguiendo el
// método "sesgo del superviviente" (7 pasos). El resultado queda en
// /reportZones/{municipalityId} y el panel lo dibuja como capa translúcida.
//
// Reglas del análisis: sólo cifras calculadas acá; si no hay datos para un
// paso se dice "No hay datos para estimarlo". Una celda sin reportes NO es una
// celda sin problemas: no se pinta de verde, queda sin color.

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const REGION = 'southamerica-east1';
const WINDOW_DAYS = 90;
const CELL_DEG_LAT = 0.0045;          // ~500 m
const MAX_CELLS = 1500;
const CLOSED = new Set(['resolved', 'closed', 'rejected']);
const CATEGORIES = ['infrastructure', 'lighting', 'garbage', 'security', 'health', 'transport', 'environment', 'other'];
const CATEGORY_LABELS = {
  infrastructure: 'infraestructura', lighting: 'alumbrado', garbage: 'residuos', security: 'seguridad',
  health: 'salud', transport: 'transporte', environment: 'ambiente', other: 'otros',
};
// Puntaje de una celda: reportes abiertos ponderados por prioridad y antigüedad.
// Umbrales del nivel (ajustables): verde < 3 <= amarilla < 6 <= naranja < 10 <= roja.
const LEVELS = [
  { level: 'RED', min: 10 },
  { level: 'ORANGE', min: 6 },
  { level: 'YELLOW', min: 3 },
  { level: 'GREEN', min: 0 },
];

const asText = (v) => (typeof v === 'string' && v.trim() ? v.trim() : '');

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function point(report) {
  const loc = report.location;
  if (!loc || typeof loc !== 'object' || loc.isManualAddress === true) return null;
  const lat = Number(loc.lat ?? loc.latitude ?? loc._latitude);
  const lng = Number(loc.lng ?? loc.lon ?? loc.longitude ?? loc._longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  if (lat === 0 && lng === 0) return null;
  return { lat, lng };
}

/** Celda fija de ~500 x 500 m. El paso en longitud se corrige por latitud (bandas de 1°). */
function cellFor({ lat, lng }) {
  const row = Math.floor(lat / CELL_DEG_LAT);
  const band = Math.floor(lat);
  const lngStep = CELL_DEG_LAT / Math.max(0.2, Math.cos(((band + 0.5) * Math.PI) / 180));
  const col = Math.floor(lng / lngStep);
  const south = row * CELL_DEG_LAT;
  const west = col * lngStep;
  return {
    id: `${row}_${col}`,
    bounds: [round6(south), round6(west), round6(south + CELL_DEG_LAT), round6(west + lngStep)],
  };
}

const round6 = (n) => Math.round(n * 1e6) / 1e6;
const round1 = (n) => Math.round(n * 10) / 10;

/** Peso de un reporte abierto: prioridad 4-5 cuenta doble; lo viejo pesa menos (mínimo 0,5). */
function reportWeight(report, nowMs) {
  const priority = Number(report.priority) >= 4 ? 2 : 1;
  const created = millis(report.createdAt);
  const ageDays = created ? Math.max(0, (nowMs - created) / 86400000) : WINDOW_DAYS;
  const decay = Math.max(0.5, 1 - ageDays / (WINDOW_DAYS * 2));
  const support = Math.min(1, Math.max(0, Number(report.supportCount) || 0) * 0.1);
  return priority * decay + support;
}

function levelFor(score) {
  return LEVELS.find((l) => score >= l.min).level;
}

function category(report) {
  return CATEGORIES.includes(report.category) ? report.category : 'other';
}

/**
 * Agrega los reportes de UN municipio. `residents` es la lista de vecinos
 * activos ({ localityId, locality }) para medir zonas silenciosas.
 */
function buildZones(reports, { nowMs = Date.now(), residents = [] } = {}) {
  const cells = new Map();
  const stats = {
    total: reports.length,
    open: 0,
    resolved: 0,
    rejected: 0,
    geolocated: 0,
    manualAddress: 0,
    categories: Object.fromEntries(CATEGORIES.map((c) => [c, { total: 0, open: 0, score: 0 }])),
    reporters: new Map(),
    localities: new Map(),
  };

  for (const report of reports) {
    const open = !CLOSED.has(report.status);
    const cat = category(report);
    const weight = open ? reportWeight(report, nowMs) : 0;
    if (open) stats.open++;
    if (report.status === 'resolved' || report.status === 'closed') stats.resolved++;
    if (report.status === 'rejected') stats.rejected++;
    stats.categories[cat].total++;
    if (open) { stats.categories[cat].open++; stats.categories[cat].score += weight; }
    const reporter = asText(report.userId);
    if (reporter) stats.reporters.set(reporter, (stats.reporters.get(reporter) || 0) + 1);
    const locality = asText(report.localityId) || asText(report.locality);
    if (locality) stats.localities.set(locality, (stats.localities.get(locality) || 0) + 1);

    const p = point(report);
    if (!p) { stats.manualAddress++; continue; }
    stats.geolocated++;
    const { id, bounds } = cellFor(p);
    const cell = cells.get(id) || {
      id, bounds, total: 0, open: 0, high: 0, resolved: 0, score: 0,
      categories: {}, reporters: new Set(), lastAt: 0,
    };
    cell.total++;
    if (open) cell.open++;
    if (open && Number(report.priority) >= 4) cell.high++;
    if (report.status === 'resolved' || report.status === 'closed') cell.resolved++;
    cell.score += weight;
    if (open) cell.categories[cat] = (cell.categories[cat] || 0) + 1;
    if (reporter) cell.reporters.add(reporter);
    cell.lastAt = Math.max(cell.lastAt, millis(report.createdAt) || 0);
    cells.set(id, cell);
  }

  const out = [...cells.values()].map((cell) => {
    const top = Object.entries(cell.categories).sort((a, b) => b[1] - a[1])[0];
    return {
      id: cell.id,
      bounds: cell.bounds,
      total: cell.total,
      open: cell.open,
      high: cell.high,
      resolved: cell.resolved,
      score: round1(cell.score),
      level: cell.open ? levelFor(cell.score) : 'GREEN',
      topCategory: top ? top[0] : null,
      categories: cell.categories,
      reporters: cell.reporters.size,
      // Una sola persona detrás de todos los reportes de la celda: el color
      // puede reflejar a quien reporta más que a la zona.
      singleSource: cell.total >= 3 && cell.reporters.size === 1,
      lastAt: cell.lastAt || null,
    };
  }).sort((a, b) => b.score - a.score).slice(0, MAX_CELLS);

  const priorities = CATEGORIES
    .map((c) => ({ category: c, label: CATEGORY_LABELS[c], ...stats.categories[c], score: round1(stats.categories[c].score) }))
    .filter((c) => c.total > 0)
    .sort((a, b) => b.score - a.score || b.open - a.open);

  const levels = { GREEN: 0, YELLOW: 0, ORANGE: 0, RED: 0 };
  out.forEach((c) => { levels[c.level]++; });

  return {
    cells: out,
    levels,
    priorities,
    analysis: survivorshipAnalysis(stats, out, residents),
    summary: {
      total: stats.total,
      open: stats.open,
      resolved: stats.resolved,
      rejected: stats.rejected,
      geolocated: stats.geolocated,
      manualAddress: stats.manualAddress,
      reporters: stats.reporters.size,
      cells: out.length,
    },
  };
}

const pct = (part, whole) => (whole ? Math.round((100 * part) / whole) : 0);
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/**
 * Análisis en 7 pasos (skill "sesgo del superviviente"): qué se observa, qué
 * falta, por qué, cómo distorsiona, qué dato falta, riesgo y conclusión
 * reformulada. Sólo usa cifras calculadas sobre los datos recibidos.
 */
function survivorshipAnalysis(stats, cells, residents) {
  if (!stats.total) {
    return {
      observed: 'No hay reportes en los últimos 90 días.',
      absent: 'No lo sé: sin reportes no se puede distinguir una zona sin problemas de una zona que no usa la app.',
      filter: 'No hay datos para estimarlo.',
      distortion: 'Un mapa vacío puede leerse como "todo en orden" cuando puede ser falta de uso de la app.',
      missing: 'Cantidad de vecinos activos por zona y reclamos recibidos por otros canales (teléfono, mostrador, redes).',
      risk: 'Alto',
      riskReason: 'Sin observaciones, cualquier conclusión sobre el estado del municipio es un supuesto.',
      conclusion: 'No hay evidencia para afirmar que el municipio no tenga problemas; sólo que no se reportaron por la app.',
      flags: { silentLocalities: [], concentration: null, manualAddress: 0, closedShare: 0 },
    };
  }

  // Localidades con vecinos registrados y ningún reporte: zonas silenciosas.
  const residentsByLocality = new Map();
  for (const r of residents) {
    const key = asText(r.localityId) || asText(r.locality);
    if (!key) continue;
    const entry = residentsByLocality.get(key) || { name: asText(r.locality) || key, count: 0 };
    entry.count++;
    residentsByLocality.set(key, entry);
  }
  const silent = [...residentsByLocality.entries()]
    .filter(([key]) => !stats.localities.has(key))
    .map(([, v]) => v)
    .sort((a, b) => b.count - a.count);

  // Concentración: qué parte de los reportes viene del 10 % de quienes más reportan.
  const counts = [...stats.reporters.values()].sort((a, b) => b - a);
  const topN = Math.max(1, Math.ceil(counts.length * 0.1));
  const topShare = counts.length >= 5 ? pct(counts.slice(0, topN).reduce((a, b) => a + b, 0), stats.total) : null;
  const singleSourceCells = cells.filter((c) => c.singleSource).length;
  const closedShare = pct(stats.resolved + stats.rejected, stats.total);

  const absent = [];
  if (silent.length) {
    absent.push(`${plural(silent.length, 'localidad', 'localidades')} con vecinos registrados no ${silent.length === 1 ? 'tiene' : 'tienen'} ningún reporte (${silent.slice(0, 4).map((s) => s.name).join(', ')}${silent.length > 4 ? '…' : ''}).`);
  }
  if (stats.manualAddress) absent.push(`${plural(stats.manualAddress, 'reporte', 'reportes')} sin ubicación geográfica no ${stats.manualAddress === 1 ? 'aparece' : 'aparecen'} en el mapa.`);
  absent.push('Vecinos que no usan la app, que reclaman por otros canales o que dejaron de reportar porque no vieron respuesta.');

  const filter = [
    'Sólo se ve a quien instaló la app, tiene conectividad y decidió reportar.',
    stats.manualAddress ? 'Los reportes con dirección escrita a mano quedan fuera de la cuadrícula.' : '',
    closedShare ? `El ${closedShare} % de los reportes ya está cerrado y no suma color: una zona atendida puede verse "verde" aunque tenga muchos problemas recurrentes.` : '',
  ].filter(Boolean).join(' ');

  const distortion = [];
  distortion.push('Las zonas sin color no son zonas sin problemas: pueden ser zonas sin usuarios.');
  if (topShare !== null && topShare >= 40) distortion.push(`El 10 % de quienes más reportan explica el ${topShare} % de los reportes: el mapa puede mostrar dónde viven los vecinos más activos.`);
  if (singleSourceCells) distortion.push(`${plural(singleSourceCells, 'celda', 'celdas')} con color ${singleSourceCells === 1 ? 'depende' : 'dependen'} de una sola persona.`);

  let riskPoints = 0;
  if (silent.length) riskPoints += 2;
  if (pct(stats.manualAddress, stats.total) >= 20) riskPoints += 1;
  if (topShare !== null && topShare >= 40) riskPoints += 1;
  if (singleSourceCells >= 3) riskPoints += 1;
  if (stats.total < 20) riskPoints += 2;
  const risk = riskPoints >= 3 ? 'Alto' : riskPoints >= 1 ? 'Medio' : 'Bajo';
  const riskReason = stats.total < 20
    ? `Hay ${plural(stats.total, 'reporte', 'reportes')} en 90 días: muestra chica para comparar zonas.`
    : silent.length
      ? 'Hay localidades con vecinos registrados y ningún reporte: la ausencia puede ser falta de uso, no falta de problemas.'
      : riskPoints
        ? 'La distribución de reportes depende de pocas personas o deja reportes fuera del mapa.'
        : 'Los reportes vienen de muchas personas y casi todos están geolocalizados.';

  const top = cells.filter((c) => c.level === 'RED' || c.level === 'ORANGE').length;
  const conclusion = `Supuesto: la app no llega a todos los vecinos por igual. ${top
    ? `Las ${plural(top, 'zona', 'zonas')} en naranja o rojo concentran la demanda reportada por la app`
    : 'No hay zonas en naranja o rojo entre las reportadas por la app'}, no necesariamente la demanda real del municipio${silent.length ? '; antes de priorizar conviene relevar las localidades silenciosas' : ''}.`;

  return {
    observed: `${plural(stats.total, 'reporte', 'reportes')} en 90 días de ${plural(stats.reporters.size, 'vecino', 'vecinos')}: ${stats.open} abiertos, ${stats.resolved} resueltos, ${stats.rejected} rechazados; ${stats.geolocated} con ubicación en el mapa.`,
    absent: absent.join(' '),
    filter,
    distortion: distortion.join(' '),
    missing: 'Vecinos activos por zona (no sólo por localidad), reclamos por teléfono, mostrador y redes, y reportes que la gente dejó de hacer tras no recibir respuesta.',
    risk,
    riskReason,
    conclusion,
    flags: {
      silentLocalities: silent.slice(0, 10),
      concentration: topShare,
      singleSourceCells,
      manualAddress: stats.manualAddress,
      closedShare,
    },
  };
}

async function runReportZones(db = getFirestore(), now = new Date()) {
  const nowMs = now.getTime();
  const since = new Date(nowMs - WINDOW_DAYS * 86400000);
  const snapshot = await db.collection('reports')
    .where('hidden', '==', false)
    .where('createdAt', '>=', since)
    .orderBy('createdAt', 'desc')
    .select('municipalityId', 'municipalityName', 'status', 'category', 'priority', 'location',
      'createdAt', 'userId', 'supportCount', 'localityId', 'locality')
    .get();
  const byMunicipality = new Map();
  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    const id = asText(data.municipalityId);
    if (!id) return;
    if (!byMunicipality.has(id)) byMunicipality.set(id, { name: asText(data.municipalityName), reports: [] });
    byMunicipality.get(id).reports.push(data);
  });

  const citizens = await db.collection('users')
    .where('role', '==', 'citizen')
    .where('disabled', '==', false)
    .select('municipalityId', 'localityId', 'locality')
    .get();
  const residents = new Map();
  citizens.docs.forEach((doc) => {
    const id = asText(doc.get('municipalityId'));
    if (!id) return;
    if (!residents.has(id)) residents.set(id, []);
    residents.get(id).push({ localityId: doc.get('localityId'), locality: doc.get('locality') });
  });

  const ids = new Set([...byMunicipality.keys(), ...residents.keys()]);
  const summary = [];
  for (const municipalityId of ids) {
    const group = byMunicipality.get(municipalityId) || { name: '', reports: [] };
    const zones = buildZones(group.reports, { nowMs, residents: residents.get(municipalityId) || [] });
    await db.collection('reportZones').doc(municipalityId).set({
      municipalityId,
      municipalityName: group.name,
      windowDays: WINDOW_DAYS,
      cellSizeM: 500,
      generatedAt: FieldValue.serverTimestamp(),
      generatedAtMs: nowMs,
      ...zones,
    });
    summary.push({ municipalityId, reports: group.reports.length, cells: zones.cells.length, risk: zones.analysis.risk });
  }
  return summary;
}

const reportZones = onSchedule(
  { schedule: 'every 30 minutes', region: REGION, timeZone: 'America/Argentina/Buenos_Aires', timeoutSeconds: 300 },
  async () => {
    const summary = await runReportZones();
    console.log('reportZones', JSON.stringify(summary));
  },
);

module.exports = {
  reportZones,
  runReportZones,
  buildZones,
  survivorshipAnalysis,
  cellFor,
  reportWeight,
  levelFor,
  WINDOW_DAYS,
};
