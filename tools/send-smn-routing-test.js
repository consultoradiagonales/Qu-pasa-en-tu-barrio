'use strict';

const crypto = require('node:crypto');
const path = require('node:path');
const { createRequire } = require('node:module');

const requireFromFunctions = createRequire(path.join(__dirname, '..', 'functions', 'package.json'));
const { applicationDefault, getApps, initializeApp } = requireFromFunctions('firebase-admin/app');
const { getFirestore } = requireFromFunctions('firebase-admin/firestore');

const weather = require('../functions/weather-alerts');
const { deliverToUsers } = require('../functions/push-delivery');

const PROJECT_ID = 'project-5fc9024a-e961-42b7-9ee';
const EXPECTED_CONNECTED_USERS = 2;

function clean(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function safeKey(value) {
  return String(value || '').replace(/[^A-Za-z0-9_-]+/g, '_').slice(0, 64) || 'municipio';
}

function signature(value) {
  return crypto.createHash('sha256').update(value).digest('hex').slice(0, 16);
}

async function connectedCitizens(db) {
  const snapshot = await db.collection('users')
    .where('role', '==', 'citizen')
    .where('disabled', '==', false)
    .get();
  return snapshot.docs
    .map((doc) => ({
      uid: doc.id,
      fcmToken: clean(doc.get('fcmToken')),
      municipalityId: clean(doc.get('municipalityId')),
      municipalityName: clean(doc.get('municipalityName')),
      province: clean(doc.get('province')),
    }))
    .filter((user) => user.fcmToken);
}

async function notificationFor(db, user, capAlerts, now, municipalityCache) {
  if (!user.municipalityId) {
    throw new Error('Un usuario conectado todavía no eligió su municipio.');
  }
  const center = await weather.municipalityCenter(db, user.municipalityId, {
    municipalityName: user.municipalityName,
    province: user.province,
  });
  if (!center) throw new Error(`No se pudo ubicar el municipio ${user.municipalityId}.`);

  let matched = weather.smnAlertsToMessages(weather.matchCapAlerts(capAlerts, center, now));
  if (matched.some((alert) => alert.polygons?.length)) {
    const catalog = await weather.provinceMunicipalities(center.province, municipalityCache);
    matched = matched.map((alert) => ({
      ...alert,
      affectedZones: weather.affectedMunicipalityNames(center, alert, catalog),
    }));
  }
  const alerts = weather.buildAlerts(center, [], matched)
    .sort((a, b) => b.level - a.level || (a.onset ?? Infinity) - (b.onset ?? Infinity));
  const selected = alerts[0];
  const checkedAt = weather.argentinaDateTime(now);
  const title = selected?.title || `SMN: sin alerta vigente en ${center.name}`;
  const body = selected?.body ||
    `Ciudad: ${center.name}, ${center.province}. Verificado con el SMN el ${checkedAt}. ` +
    'No hay una alerta oficial vigente para el municipio elegido ni su zona inmediata.';
  const affectedZones = selected?.affectedZones || [center.name];
  const identity = signature(JSON.stringify({
    municipalityId: user.municipalityId,
    title,
    onset: selected?.onset ?? null,
    expires: selected?.expires ?? null,
    affectedZones,
    day: weather.argentinaDay(now),
  }));

  return {
    municipality: center.name,
    province: center.province,
    officialAlertsMatched: matched.length,
    title,
    body,
    payload: {
      key: `smn_route_test_${safeKey(user.municipalityId)}_${identity}`,
      type: 'weather_alert',
      title,
      body,
      data: {
        source: 'SMN',
        routingTest: true,
        municipalityId: user.municipalityId,
        municipalityName: center.name,
        province: center.province,
        affectedZones,
        affectedArea: selected?.affectedArea || center.name,
        onset: selected?.onset ?? '',
        expires: selected?.expires ?? '',
        verifiedAt: now.toISOString(),
      },
    },
  };
}

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
  }
  const send = process.argv.includes('--send');
  const db = getFirestore();
  const users = await connectedCitizens(db);
  if (users.length !== EXPECTED_CONNECTED_USERS) {
    throw new Error(
      `Se esperaban ${EXPECTED_CONNECTED_USERS} usuarios conectados con token y hay ${users.length}; no se envía nada.`,
    );
  }

  const now = new Date();
  let capIndexDiagnostic = null;
  if (process.argv.includes('--debug-cap')) {
    const response = await fetch('https://ssl.smn.gob.ar/CAP/AR.php', {
      headers: { 'User-Agent': 'ConDi/1.0 (info.consultoradiagonales@gmail.com)' },
      signal: AbortSignal.timeout(15000),
    });
    const text = await response.text();
    const paths = [...new Set(
      [...text.matchAll(/\/feeds\/CAP\/[^"'<>\s]+\.xml/gi)].map((match) => match[0]),
    )];
    let firstXml = null;
    if (paths.length) {
      const xmlResponse = await fetch(`https://ssl.smn.gob.ar${paths[0]}`, {
        headers: { 'User-Agent': 'ConDi/1.0 (info.consultoradiagonales@gmail.com)' },
        signal: AbortSignal.timeout(15000),
      });
      const xml = await xmlResponse.text();
      firstXml = {
        url: `https://ssl.smn.gob.ar${paths[0]}`,
        status: xmlResponse.status,
        bytes: xml.length,
        preview: xml.slice(0, 120),
      };
    }
    capIndexDiagnostic = {
      status: response.status,
      bytes: text.length,
      paths: paths.length,
      preview: text.slice(0, 160),
      firstXml,
    };
  }
  const capAlerts = await weather.loadSmnCapAlerts();
  const municipalityCache = new Map();
  const results = [];
  for (const user of users) {
    const item = await notificationFor(db, user, capAlerts, now, municipalityCache);
    const delivery = send
      ? await deliverToUsers(db, [{ uid: user.uid, fcmToken: user.fcmToken }], item.payload)
      : null;
    results.push({
      municipality: item.municipality,
      province: item.province,
      officialAlertsMatched: item.officialAlertsMatched,
      title: item.title,
      body: item.body,
      delivery,
    });
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    mode: send ? 'send' : 'dry-run',
    checkedAt: now.toISOString(),
    officialCapAlertsLoaded: capAlerts.length,
    connectedUsers: users.length,
    ...(capIndexDiagnostic ? { capIndexDiagnostic } : {}),
    ...(process.argv.includes('--debug-cap') ? {
      capAlerts: capAlerts.map((alert) => ({
        identifier: alert.identifier,
        event: alert.event,
        level: alert.level,
        onset: alert.onset,
        expires: alert.expires,
        areaDesc: alert.areaDesc,
        polygons: alert.polygons?.length || 0,
      })),
    } : {}),
    results,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
