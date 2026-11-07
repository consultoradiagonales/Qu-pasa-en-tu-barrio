const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const { randomUUID } = require('node:crypto');
// FieldValue se importa del submódulo: en firebase-admin v12
// admin.firestore.FieldValue quedó undefined.
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();
const { isCentralAdmin } = require('./management-access');
exports.interpretCitizenReport = require('./ai-trigger').interpretCitizenReport;
exports.generateMunicipalityReport = require('./dashboard-ai').generateMunicipalityReport;
exports.getManagementDashboard = require('./management-dashboard').getManagementDashboard;
exports.reportLifecycleNotifications = require('./report-notifications').reportLifecycleNotifications;
const adminNotifications = require('./admin-notifications');
exports.setReportPriority = adminNotifications.setReportPriority;
exports.sendReportUpdate = adminNotifications.sendReportUpdate;
exports.weatherAlerts = require("./weather-alerts").weatherAlerts;
const weatherAdmin = require('./weather-admin');
exports.sendWeatherAlert = weatherAdmin.sendWeatherAlert;
exports.correctWeatherAlert = weatherAdmin.correctWeatherAlert;
const userMessaging = require("./user-messaging");
exports.sendCustomMessage = userMessaging.sendCustomMessage;
exports.saveDeviceProfile = userMessaging.saveDeviceProfile;
exports.deleteDeviceProfile = userMessaging.deleteDeviceProfile;
const usageAnalytics = require('./usage-analytics');
exports.recordUsagePresence = usageAnalytics.recordUsagePresence;
exports.getUsageSummary = usageAnalytics.getUsageSummary;
const appRelease = require('./app-release');
exports.getAppRelease = appRelease.getAppRelease;
exports.saveAppRelease = appRelease.saveAppRelease;

const ROLES_GESTION = ['coordinator', 'admin', 'moderator'];
const { assignReportTeamHandler } = require('./report-assignment');
const OWNER_EMAIL = 'info.consultoradiagonales@gmail.com';
const REGION = 'southamerica-east1';

/**
 * Alta única del propietario de ConDi. El correo está fijado al titular del
 * proyecto: ningún usuario registrado puede convertirse en administrador.
 */
exports.activateOwnerAdmin = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  const email = request.auth?.token?.email?.toLowerCase();
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  }
  if (email !== OWNER_EMAIL || request.auth.token.email_verified !== true) {
    throw new HttpsError('permission-denied', 'Solo el titular puede activar la administración.');
  }

  const owner = await db.collection('users').doc(uid).get();
  if (!owner.exists) {
    throw new HttpsError('failed-precondition', 'Completá primero el registro de tu cuenta.');
  }
  await owner.ref.update({
    role: 'admin',
    organizationId: 'diagonales',
    disabled: false,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/**
 * Asigna un reporte a un equipo del municipio.
 *
 * Vive acá y no en el cliente porque las reglas de Firestore no permiten que
 * nadie escriba `assignedTeamId` ni cambie el estado a 'assigned'
 * directamente: la asignación tiene que validarse contra el perfil de quien
 * la pide y contra el municipio del equipo, y eso no se puede expresar en las
 * reglas sin abrir la puerta a que un vecino se autoasigne reportes.
 */
exports.assignReportTeam = onCall({ region: REGION }, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  }

  const { activateOwnerAdmin } = request.data || {};
  if (activateOwnerAdmin === true) {
    const email = request.auth?.token?.email?.toLowerCase();
    if (email !== OWNER_EMAIL || request.auth.token.email_verified !== true) {
      throw new HttpsError('permission-denied', 'Solo el titular puede activar la administración.');
    }
    const owner = await db.collection('users').doc(uid).get();
    if (!owner.exists) {
      throw new HttpsError('failed-precondition', 'Completá primero el registro de tu cuenta.');
    }
    await owner.ref.update({
      role: 'admin',
      organizationId: 'diagonales',
      disabled: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, role: 'admin' };
  }
  return assignReportTeamHandler(request, db);
});

const TEAM_CATEGORIES = new Set([
  'infrastructure',
  'lighting',
  'garbage',
  'security',
  'health',
  'transport',
  'environment',
  'other',
]);
const AD_DISMISS_MODES = new Set(['close_now', 'wait_7_seconds']);
const AD_IMAGE_TYPES = new Map([
  ['image/jpeg', 'jpg'],
  ['image/png', 'png'],
  ['image/webp', 'webp'],
]);
const MAX_AD_IMAGE_BYTES = 5 * 1024 * 1024;

function cleanTeamText(value, max = 100) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function cleanTeamMembers(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .map((item) => cleanTeamText(item, 80))
    .filter(Boolean))]
    .slice(0, 30);
}

function cleanTeamCategories(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((item) => typeof item === 'string' && TEAM_CATEGORIES.has(item)))];
}

function validTeamId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,80}$/.test(value);
}

function cleanAdText(value, max = 180) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function validAdId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{12,80}$/.test(value);
}

function validHttpsUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && Boolean(url.hostname) && !url.username && !url.password;
  } catch (_) {
    return false;
  }
}

function cleanAdDismissMode(value) {
  return AD_DISMISS_MODES.has(value) ? value : 'close_now';
}

function validAdImageContent(buffer, contentType) {
  if (!Buffer.isBuffer(buffer)) return false;
  if (contentType === 'image/jpeg') {
    return buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  }
  if (contentType === 'image/png') {
    return buffer.length >= 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  }
  return contentType === 'image/webp' && buffer.length >= 12 &&
    buffer.subarray(0, 4).equals(Buffer.from('RIFF')) &&
    buffer.subarray(8, 12).equals(Buffer.from('WEBP'));
}

function adImageBuffer(base64, contentType) {
  if (!AD_IMAGE_TYPES.has(contentType)) {
    throw new HttpsError('invalid-argument', 'Usá una imagen JPG, PNG o WebP.');
  }
  if (typeof base64 !== 'string' || !base64) {
    throw new HttpsError('invalid-argument', 'No se recibió la imagen.');
  }
  const normalized = base64.replace(/\s/g, '');
  const maxBase64Length = Math.ceil(MAX_AD_IMAGE_BYTES * 4 / 3) + 8;
  if (normalized.length > maxBase64Length || !/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', 'La imagen no es válida o supera 5 MB.');
  }
  const buffer = Buffer.from(normalized, 'base64');
  if (!buffer.length || buffer.length > MAX_AD_IMAGE_BYTES || !validAdImageContent(buffer, contentType)) {
    throw new HttpsError('invalid-argument', 'La imagen no es válida o supera 5 MB.');
  }
  return buffer;
}

function adDate(value) {
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) || date.getUTCFullYear() < 2020 || date.getUTCFullYear() > 2100
    ? null
    : date;
}

async function managementProfile(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Tenés que iniciar sesión.');
  const profileSnap = await db.collection('users').doc(uid).get();
  if (!profileSnap.exists) throw new HttpsError('permission-denied', 'Tu usuario no tiene perfil.');
  const profile = profileSnap.data();
  if (profile.disabled === true || !ROLES_GESTION.includes(profile.role)) {
    throw new HttpsError('permission-denied', 'No podés gestionar cuadrillas.');
  }
  return { uid, profile };
}

async function adminProfile(request) {
  const { profile } = await managementProfile(request);
  if (!isCentralAdmin(profile)) {
    throw new HttpsError('permission-denied', 'Sólo la administración puede gestionar publicidad.');
  }
  return profile;
}

/**
 * Crea o actualiza una cuadrilla sin exponer escritura directa desde el
 * navegador. Un coordinador sólo puede operar en su municipio; el titular
 * administrador puede elegir el municipio de destino.
 */
exports.saveTeam = onCall({ region: REGION }, async (request) => {
  const { profile } = await managementProfile(request);
  const data = request.data || {};
  const requestedId = data.teamId;
  if (requestedId != null && !validTeamId(requestedId)) {
    throw new HttpsError('invalid-argument', 'La cuadrilla no es válida.');
  }

  const name = cleanTeamText(data.name, 80);
  if (name.length < 2) {
    throw new HttpsError('invalid-argument', 'Indicá un nombre para la cuadrilla.');
  }

  const existingRef = requestedId ? db.collection('teams').doc(requestedId) : null;
  const existingSnap = existingRef ? await existingRef.get() : null;
  if (existingSnap && !existingSnap.exists) {
    throw new HttpsError('not-found', 'La cuadrilla no existe.');
  }
  const existing = existingSnap?.data() || null;
  const isAdmin = isCentralAdmin(profile);
  const municipalityId = isAdmin
    ? cleanTeamText(data.municipalityId, 120)
    : cleanTeamText(profile.municipalityId, 120);
  const municipalityName = isAdmin
    ? cleanTeamText(data.municipalityName, 120)
    : cleanTeamText(profile.municipalityName, 120);
  if (!municipalityId) {
    throw new HttpsError('failed-precondition', 'Elegí el municipio de la cuadrilla.');
  }

  if (existing && !isAdmin && existing.municipalityId !== municipalityId) {
    throw new HttpsError('permission-denied', 'Sólo podés gestionar cuadrillas de tu municipio.');
  }
  if (existing && existing.municipalityId !== municipalityId) {
    const assignments = await db.collection('reports')
      .where('assignedTeamId', '==', requestedId)
      .limit(1)
      .get();
    if (!assignments.empty) {
      throw new HttpsError('failed-precondition', 'No se puede cambiar el municipio de una cuadrilla con reportes asignados.');
    }
  }

  const team = {
    name,
    municipalityId,
    municipalityName: municipalityName || municipalityId,
    zoneName: cleanTeamText(data.zoneName, 100),
    zoneManagerName: cleanTeamText(data.zoneManagerName, 100),
    maintenanceChiefName: cleanTeamText(data.maintenanceChiefName, 100),
    memberNames: cleanTeamMembers(data.memberNames),
    categories: cleanTeamCategories(data.categories),
    active: data.active !== false,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (existingRef) {
    await existingRef.update(team);
    return { ok: true, teamId: existingRef.id, created: false };
  }

  const createdRef = db.collection('teams').doc();
  await createdRef.create({
    ...team,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, teamId: createdRef.id, created: true };
});

/**
 * Crea o actualiza un banner local. La imagen se carga bajo reglas estrictas
 * de Storage y esta función conserva la validación de la pauta comercial,
 * incluyendo la modalidad de cierre elegida para el abono contratado.
 */
exports.saveLocalAd = onCall({ region: REGION }, async (request) => {
  await adminProfile(request);
  const data = request.data || {};
  const requestedId = data.adId;
  if (requestedId != null && !validAdId(requestedId)) {
    throw new HttpsError('invalid-argument', 'El anuncio no es válido.');
  }

  const municipalityId = cleanAdText(data.municipalityId, 120);
  const municipalityName = cleanAdText(data.municipalityName, 120);
  const business = cleanAdText(data.business, 80);
  const message = cleanAdText(data.message, 180);
  const imageUrl = cleanAdText(data.imageUrl, 2048);
  const link = cleanAdText(data.link, 2048);
  const startsAt = adDate(data.startsAt);
  const endsAt = adDate(data.endsAt);
  const dismissMode = cleanAdDismissMode(data.dismissMode);

  if (!municipalityId) throw new HttpsError('invalid-argument', 'Elegí el municipio del anuncio.');
  if (business.length < 2) throw new HttpsError('invalid-argument', 'Indicá el comercio anunciante.');
  if (!message) throw new HttpsError('invalid-argument', 'Indicá el mensaje del anuncio.');
  if (imageUrl && !validHttpsUrl(imageUrl)) throw new HttpsError('invalid-argument', 'La imagen debe usar una URL HTTPS válida.');
  if (!validHttpsUrl(link)) throw new HttpsError('invalid-argument', 'El enlace debe usar HTTPS.');
  if (!startsAt || !endsAt || endsAt <= startsAt) {
    throw new HttpsError('invalid-argument', 'La vigencia del anuncio no es válida.');
  }
  if (data.dismissMode != null && !AD_DISMISS_MODES.has(data.dismissMode)) {
    throw new HttpsError('invalid-argument', 'La modalidad de cierre no es válida.');
  }

  const ad = {
    municipalityId,
    municipalityName: municipalityName || municipalityId,
    business,
    message,
    imageUrl,
    link,
    startsAt,
    endsAt,
    dismissMode,
    active: data.active !== false,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const existingRef = requestedId ? db.collection('localAds').doc(requestedId) : null;
  if (existingRef) {
    const existing = await existingRef.get();
    if (!existing.exists) throw new HttpsError('not-found', 'El anuncio no existe.');
    await existingRef.update(ad);
    return { ok: true, adId: existingRef.id, created: false, dismissMode };
  }

  const createdRef = db.collection('localAds').doc();
  await createdRef.create({ ...ad, createdAt: FieldValue.serverTimestamp() });
  return { ok: true, adId: createdRef.id, created: true, dismissMode };
});

/**
 * Sube una imagen publicitaria desde un administrador autenticado. La subida
 * se ejecuta en el servidor para que el panel no dependa de permisos directos
 * de Storage y el archivo siempre quede validado antes de publicarse.
 */
exports.uploadLocalAdImage = onCall({ region: REGION }, async (request) => {
  await adminProfile(request);
  const data = request.data || {};
  const municipalityId = cleanAdText(data.municipalityId, 120);
  if (!municipalityId) {
    throw new HttpsError('invalid-argument', 'Elegí el municipio del anuncio.');
  }
  const contentType = typeof data.contentType === 'string' ? data.contentType.toLowerCase() : '';
  const image = adImageBuffer(data.imageBase64, contentType);
  const extension = AD_IMAGE_TYPES.get(contentType);
  const fileName = `advertising/${municipalityId}/${randomUUID()}.${extension}`;
  const token = randomUUID();
  const bucket = getStorage().bucket();
  await bucket.file(fileName).save(image, {
    resumable: false,
    metadata: {
      contentType,
      cacheControl: 'public,max-age=86400',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  return {
    ok: true,
    imageUrl: `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(fileName)}?alt=media&token=${token}`,
  };
});

module.exports.cleanTeamText = cleanTeamText;
module.exports.cleanTeamMembers = cleanTeamMembers;
module.exports.cleanTeamCategories = cleanTeamCategories;
module.exports.validTeamId = validTeamId;
module.exports.cleanAdText = cleanAdText;
module.exports.validAdId = validAdId;
module.exports.validHttpsUrl = validHttpsUrl;
module.exports.cleanAdDismissMode = cleanAdDismissMode;
module.exports.adDate = adDate;
module.exports.validAdImageContent = validAdImageContent;
module.exports.adImageBuffer = adImageBuffer;
