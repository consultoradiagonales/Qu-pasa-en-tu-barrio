'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const REGION = 'southamerica-east1';
const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const CONSENT_VERSION = 2;
const MIN_VISIBLE_CITY_USERS = 3;
const MAX_PERIOD_DAYS = 90;

function cleanText(value, max = 120) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function argentinaDateKey(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function dateRange(days, now = new Date()) {
  const total = Math.max(1, Math.min(MAX_PERIOD_DAYS, Math.trunc(Number(days) || 30)));
  const current = new Date(`${argentinaDateKey(now)}T12:00:00.000Z`);
  const result = [];
  for (let offset = total - 1; offset >= 0; offset -= 1) {
    const day = new Date(current);
    day.setUTCDate(day.getUTCDate() - offset);
    result.push(day.toISOString().slice(0, 10));
  }
  return result;
}

function territoryFromProfile(profile = {}) {
  const municipalityId = cleanText(profile.municipalityId, 120);
  const municipalityName = cleanText(profile.municipalityName, 120) || municipalityId;
  const locality = cleanText(profile.locality, 120);
  const city = locality || municipalityName;
  if (!municipalityId || !city) return null;
  return {
    municipalityId,
    municipalityName,
    localityId: cleanText(profile.localityId, 120),
    city,
    provinceId: cleanText(profile.provinceId, 120),
    province: cleanText(profile.province, 120),
  };
}

function cityDocumentId(territory) {
  return [territory.municipalityId, territory.localityId || territory.city]
    .map((value) => encodeURIComponent(value).replace(/%/g, '_'))
    .join('__')
    .slice(0, 145);
}

function validScopeValue(value) {
  return cleanText(value, 120);
}

function aggregateUsage(rows, { dayKeys, municipalityId = '', provinceId = '', localityId = '' } = {}) {
  const requestedDays = Array.isArray(dayKeys) ? dayKeys : [];
  const daily = new Map(requestedDays.map((day) => [day, 0]));
  const cities = new Map();

  for (const row of rows || []) {
    const data = typeof row?.data === 'function' ? row.data() : row;
    if (!data || !daily.has(data.date)) continue;
    if (municipalityId && data.municipalityId !== municipalityId) continue;
    if (provinceId && data.provinceId !== provinceId) continue;
    if (localityId && data.localityId !== localityId) continue;

    const activeUsers = Math.max(0, Math.trunc(Number(data.activeUsers) || 0));
    if (!activeUsers) continue;
    daily.set(data.date, daily.get(data.date) + activeUsers);

    const key = [data.municipalityId, data.localityId || data.city].join('|');
    const city = cities.get(key) || {
      city: cleanText(data.city, 120),
      municipalityId: cleanText(data.municipalityId, 120),
      municipalityName: cleanText(data.municipalityName, 120),
      province: cleanText(data.province, 120),
      sessions: 0,
      activeDays: 0,
      maxDailyUsers: 0,
    };
    city.sessions += activeUsers;
    city.activeDays += 1;
    city.maxDailyUsers = Math.max(city.maxDailyUsers, activeUsers);
    cities.set(key, city);
  }

  const allCities = [...cities.values()];
  const visibleCities = allCities
    .filter((city) => city.maxDailyUsers >= MIN_VISIBLE_CITY_USERS)
    .sort((a, b) => b.sessions - a.sessions || b.maxDailyUsers - a.maxDailyUsers || a.city.localeCompare(b.city));
  const series = requestedDays.map((date) => ({ date, activeUsers: daily.get(date) || 0 }));
  const totalSessions = series.reduce((sum, day) => sum + day.activeUsers, 0);

  return {
    totalSessions,
    activeUsersToday: series.at(-1)?.activeUsers || 0,
    trackedCities: allCities.length,
    visibleCities: visibleCities.length,
    suppressedCities: allCities.length - visibleCities.length,
    daily: series,
    cities: visibleCities.slice(0, 12),
  };
}

async function requireManager(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const db = getFirestore();
  const profileSnap = await db.collection('users').doc(uid).get();
  const profile = profileSnap.data();
  if (!profile || profile.disabled === true || !MANAGEMENT_ROLES.has(profile.role)) {
    throw new HttpsError('permission-denied', 'No tenés permisos para ver la analítica territorial.');
  }
  return { db, profile };
}

async function recordUsagePresenceHandler(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');

  const db = getFirestore();
  const [profileSnap, deviceSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('userDevices').doc(uid).get(),
  ]);
  const profile = profileSnap.data();
  if (!profile || profile.disabled === true) {
    throw new HttpsError('permission-denied', 'La cuenta no está disponible.');
  }
  const consent = deviceSnap.get('consent');
  if (consent?.given !== true || consent.version !== CONSENT_VERSION) {
    throw new HttpsError('failed-precondition', 'La medición territorial requiere consentimiento.');
  }
  const territory = territoryFromProfile(profile);
  if (!territory) return { ok: true, counted: false, reason: 'missing_territory' };

  const date = argentinaDateKey();
  const deviceRef = db.collection('userDevices').doc(uid);
  const dailyRef = db.collection('usageDaily').doc(date);
  const cityRef = dailyRef.collection('cities').doc(cityDocumentId(territory));
  let counted = false;

  await db.runTransaction(async (transaction) => {
    const freshDevice = await transaction.get(deviceRef);
    const freshConsent = freshDevice.get('consent');
    if (freshConsent?.given !== true || freshConsent.version !== CONSENT_VERSION) {
      throw new HttpsError('failed-precondition', 'La medición territorial requiere consentimiento.');
    }
    if (freshDevice.get('usageAnalytics.lastRecordedDate') === date) return;

    const citySnap = await transaction.get(cityRef);
    transaction.set(deviceRef, {
      usageAnalytics: {
        enabled: true,
        source: 'profile_territory',
        lastRecordedDate: date,
        updatedAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(dailyRef, {
      date,
      activeUsers: FieldValue.increment(1),
      sessions: FieldValue.increment(1),
      trackedCities: FieldValue.increment(citySnap.exists ? 0 : 1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (citySnap.exists) {
      transaction.update(cityRef, {
        activeUsers: FieldValue.increment(1),
        sessions: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      transaction.create(cityRef, {
        ...territory,
        date,
        activeUsers: 1,
        sessions: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    counted = true;
  });

  return { ok: true, counted, date };
}

async function getUsageSummaryHandler(request) {
  const { db, profile } = await requireManager(request);
  const data = request.data || {};
  const days = Math.max(7, Math.min(MAX_PERIOD_DAYS, Math.trunc(Number(data.days) || 30)));
  const dayKeys = dateRange(days);
  const requestedMunicipality = validScopeValue(data.municipalityId);
  const requestedProvince = validScopeValue(data.provinceId);
  const requestedLocality = validScopeValue(data.localityId);
  const isAdmin = require('./management-access').isCentralAdmin(profile);
  const municipalityId = isAdmin ? requestedMunicipality : validScopeValue(profile.municipalityId);
  if (!isAdmin && (!municipalityId || (requestedMunicipality && requestedMunicipality !== municipalityId) || requestedProvince)) {
    throw new HttpsError('permission-denied', 'Sólo podés consultar el municipio asignado.');
  }
  const provinceId = isAdmin && !municipalityId ? requestedProvince : '';
  const localityId = isAdmin && municipalityId ? requestedLocality : '';

  const snapshots = [];
  for (const day of dayKeys) {
    // Cada subcolección es pequeña y evita exponer una consulta directa a los
    // clientes o necesitar índices globales para el tablero.
    snapshots.push(await db.collection('usageDaily').doc(day).collection('cities').get());
  }
  const result = aggregateUsage(
    snapshots.flatMap((snapshot) => snapshot.docs),
    { dayKeys, municipalityId, provinceId, localityId },
  );
  return {
    ok: true,
    days,
    scope: {
      municipalityId: municipalityId || null,
      provinceId: provinceId || null,
      localityId: localityId || null,
    },
    ...result,
  };
}

const recordUsagePresence = onCall({ region: REGION }, recordUsagePresenceHandler);
const getUsageSummary = onCall({ region: REGION }, getUsageSummaryHandler);

module.exports = {
  CONSENT_VERSION,
  MIN_VISIBLE_CITY_USERS,
  aggregateUsage,
  argentinaDateKey,
  cityDocumentId,
  dateRange,
  getUsageSummary,
  getUsageSummaryHandler,
  recordUsagePresence,
  recordUsagePresenceHandler,
  territoryFromProfile,
};
