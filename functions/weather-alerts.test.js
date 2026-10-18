'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { averageForecasts, evaluate, messageFor, summarize } = require('./weather-alerts');

test('promedia las fuentes disponibles e ignora valores nulos', () => {
  const avg = averageForecasts([
    { rain: 60, gust: 50, tmax: 30, tmin: 10 },
    { rain: 100, gust: null, tmax: 32, tmin: 12 },
  ]);
  assert.equal(avg.sources, 2);
  assert.equal(avg.rain, 80);
  assert.equal(avg.gust, 50);
  assert.equal(avg.tmax, 31);
  assert.equal(averageForecasts([]), null);
});

test('evalua umbrales de aviso y alerta, incluido el frio', () => {
  const threats = evaluate({ rain: 85, gust: 62, tmax: 25, tmin: -5 });
  const by = Object.fromEntries(threats.map((t) => [t.hazard, t.level]));
  assert.deepEqual(by, { rain: 2, wind: 1, cold: 2 });
  assert.deepEqual(evaluate({ rain: 5, gust: 20, tmax: 25, tmin: 8 }), []);
  assert.deepEqual(evaluate(null), []);
});

test('el mensaje nombra el municipio y aclara que es un promedio', () => {
  const message = messageFor('Azul', { hazard: 'rain', level: 2, value: 85 });
  assert.match(message.title, /^Alerta: lluvia intensa en Azul$/);
  assert.match(message.body, /85 mm/);
});

test('resume solo las proximas 24 horas', () => {
  const rain = Array.from({ length: 48 }, () => 1);
  assert.equal(summarize({ rain, gust: [], temp: [] }).rain, 24);
  assert.equal(summarize({ rain: [], gust: [], temp: [] }), null);
});

// ---------------------------------------------------------------------------
// SMN (feed CAP 1.2), concurrencia, dia argentino y dedupe. Sin red.
// ---------------------------------------------------------------------------
const w = require('./weather-alerts');

const POLYGON = '-37.0,-70.0 -37.0,-69.0 -38.0,-69.0 -38.0,-70.0 -37.0,-70.0';

function capXml({
  msgType = 'Alert', status = 'Actual', event = 'Lluvias', severity = 'Moderate', polygon = POLYGON,
  onset = '2026-10-19T15:00:00-03:00', expires = '2026-10-19T20:59:59-03:00', areaDesc = '',
} = {}) {
  return '<?xml version="1.0"?><alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">' +
    `<identifier>urn:oid:1</identifier><sender>smn@smn.gob.ar</sender><status>${status}</status>` +
    `<msgType>${msgType}</msgType><scope>Public</scope><info><language>es-AR</language>` +
    `<event>${event}</event><severity>${severity}</severity><onset>${onset}</onset>` +
    `<expires>${expires}</expires><headline>${event}</headline>` +
    '<description>El &#xE1;rea ser&#xE1; afectada. Valores entre 10 y 20 mm.</description>' +
    '<instruction>1- Evit&#xE1; salir.</instruction>' +
    `<area><areaDesc>${areaDesc}</areaDesc>${polygon ? `<polygon>${polygon}</polygon>` : ''}</area>` +
    '</info></alert>';
}

const NOW = new Date('2026-10-18T12:00:00Z');

test('el dia usa la zona horaria de Argentina y no UTC', () => {
  assert.equal(w.argentinaDay(new Date('2026-10-18T01:30:00Z')), '2026-10-17');
  assert.equal(w.argentinaDay(new Date('2026-10-18T02:59:59Z')), '2026-10-17');
  assert.equal(w.argentinaDay(new Date('2026-10-18T03:00:00Z')), '2026-10-18');
});

test('parseCapAlert lee el formato real del SMN y decodifica entidades', () => {
  const a = w.parseCapAlert(capXml());
  assert.equal(a.event, 'Lluvias');
  assert.equal(a.hazard, 'rain');
  assert.equal(a.level, 1);
  assert.equal(a.color, 'amarilla');
  assert.match(a.description, /^El área será afectada/);
  assert.equal(a.polygons.length, 1);
  assert.deepEqual(a.polygons[0][0], [-37, -70]);
  assert.equal(a.onset, Date.parse('2026-10-19T15:00:00-03:00'));
});

test('parseCapAlert mapea severidad, descarta Cancel/no Actual y XML invalido', () => {
  assert.equal(w.parseCapAlert(capXml({ severity: 'Severe' })).color, 'naranja');
  assert.equal(w.parseCapAlert(capXml({ severity: 'Extreme' })).level, 3);
  assert.equal(w.parseCapAlert(capXml({ msgType: 'Cancel' })), null);
  assert.equal(w.parseCapAlert(capXml({ status: 'Test' })), null);
  assert.equal(w.parseCapAlert(capXml({ severity: 'Minor' })), null);
  assert.equal(w.parseCapAlert('<html>503</html>'), null);
  assert.equal(w.parseCapAlert(null), null);
  assert.equal(w.parseCapAlert(capXml({ event: 'Tormentas' })).hazard, 'storm');
  assert.equal(w.parseCapAlert(capXml({ event: 'Nevadas' })).hazard, 'snow');
});

test('punto en poligono y filtrado por municipio, vigencia y horizonte', () => {
  const ring = w.parseCapAlert(capXml()).polygons[0];
  assert.equal(w.pointInRing(-37.5, -69.5, ring), true);
  assert.equal(w.pointInRing(-34.6, -58.4, ring), false);

  const alerts = [
    w.parseCapAlert(capXml({ onset: '2026-10-18T10:00:00-03:00', expires: '2026-10-19T00:00:00-03:00' })),
    // vencido
    w.parseCapAlert(capXml({ event: 'Nevadas', expires: '2026-10-17T00:00:00-03:00', onset: '2026-10-16T00:00:00-03:00' })),
    // demasiado lejano
    w.parseCapAlert(capXml({ event: 'Tormentas', onset: '2026-10-25T00:00:00-03:00', expires: '2026-10-26T00:00:00-03:00' })),
  ];
  const inside = w.matchCapAlerts(alerts, { name: 'Zapala', lat: -37.5, lng: -69.5 }, NOW);
  assert.deepEqual(inside.map((a) => a.hazard), ['rain']);
  assert.deepEqual(w.matchCapAlerts(alerts, { name: 'Azul', lat: -36.7, lng: -59.8 }, NOW), []);
});

test('sin poligono se compara areaDesc sin acentos ni mayusculas', () => {
  const a = w.parseCapAlert(capXml({ polygon: '', areaDesc: 'NEUQU&#xC9;N: Dpto. Zapala y Catan Lil' }));
  assert.equal(w.matchCapAlerts([a], { name: 'zapala', province: 'Neuquén' }, NOW).length, 1);
  assert.equal(w.matchCapAlerts([a], { name: 'ZAPALA', province: 'Neuquen' }, NOW).length, 1);
  assert.equal(w.matchCapAlerts([a], { name: 'Zapala', province: 'Mendoza' }, NOW).length, 0);
  assert.equal(w.matchCapAlerts([a], { name: 'Azul', province: 'Buenos Aires' }, NOW).length, 0);
  assert.equal(w.normalizeText('  ÁRea  Zápala '), 'area zapala');
});

test('smnAlertsToMessages deja un solo aviso por peligro, el de mayor nivel', () => {
  const msgs = w.smnAlertsToMessages([
    w.parseCapAlert(capXml()),
    w.parseCapAlert(capXml({ severity: 'Severe' })),
    w.parseCapAlert(capXml({ event: 'Tormentas' })),
  ]);
  const by = Object.fromEntries(msgs.map((m) => [m.hazard, m]));
  assert.equal(msgs.length, 2);
  assert.equal(by.rain.level, 2);
  assert.match(by.rain.title, /^Alerta naranja por lluvias$/);
  assert.match(by.rain.description, /Evitá salir/);
});

test('loadSmnCapAlerts lee el indice (RSS o HTML), reintenta y omite XML rotos', async () => {
  const base = 'https://ssl.smn.gob.ar/feeds/CAP/xml_generados/';
  const index = `<rss><item><link>${base}a.xml</link></item><item><link>${base}b.xml</link></item>` +
    `<a href="${base}c.xml">Ver XML CAP</a><guid>${base}a.xml</guid></rss>`;
  const calls = {};
  const getText = async (url) => {
    calls[url] = (calls[url] || 0) + 1;
    if (url.endsWith('AR.php')) return index;
    if (url.endsWith('a.xml')) {
      if (calls[url] === 1) throw new Error('HTTP 520'); // el reintento lo recupera
      return capXml();
    }
    if (url.endsWith('b.xml')) throw new Error('HTTP 500'); // falla siempre
    return capXml({ event: 'Nevadas' });
  };
  const alerts = await w.loadSmnCapAlerts(getText);
  assert.deepEqual(alerts.map((a) => a.hazard).sort(), ['rain', 'snow']);
  assert.equal(calls[`${base}a.xml`], 2);
  await assert.rejects(() => w.loadSmnCapAlerts(async () => { throw new Error('HTTP 503'); }), /503/);
});

test('mapWithConcurrency respeta el limite y el orden; withTimeout corta', async () => {
  let active = 0;
  let peak = 0;
  const out = await w.mapWithConcurrency([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    active++;
    peak = Math.max(peak, active);
    await new Promise((r) => setTimeout(r, 5));
    active--;
    return n * 2;
  });
  assert.deepEqual(out, [2, 4, 6, 8, 10, 12, 14]);
  assert.equal(peak, 3);
  assert.deepEqual(await w.mapWithConcurrency([], 3, async () => 1), []);
  await assert.rejects(() => w.withTimeout(new Promise(() => {}), 20, 'x'), /timeout x/);
  assert.equal(await w.withTimeout(Promise.resolve(7), 20, 'x'), 7);
});

test('buildAlerts separa peligros propios de los del SMN con claves por nivel', () => {
  const alerts = w.buildAlerts(
    { name: 'Azul' },
    [{ hazard: 'rain', level: 2, value: 90 }],
    [{ hazard: 'rain', level: 1, title: 'Alerta amarilla por lluvias', description: 'detalle' }],
  );
  assert.deepEqual(alerts.map((a) => a.key), ['rain_2', 'smn_rain_1']);
  assert.equal(alerts[1].title, 'SMN: Alerta amarilla por lluvias');
});

// ---- runWeatherAlerts con Firestore y fetch simulados ----------------------

function fakeDb({ users, geo }) {
  const store = new Map();
  const key = (c, id) => `${c}/${id}`;
  const docRef = (c, id) => ({
    id,
    async get() {
      const data = store.get(key(c, id));
      return { exists: data !== undefined, data: () => data, get: (f) => data?.[f] };
    },
    async create(data) {
      if (store.has(key(c, id))) throw Object.assign(new Error('exists'), { code: 6 });
      store.set(key(c, id), data);
    },
    async set(data, opts) {
      store.set(key(c, id), opts?.merge ? { ...(store.get(key(c, id)) || {}), ...data } : data);
    },
    async update(data) { store.set(key(c, id), { ...(store.get(key(c, id)) || {}), ...data }); },
    async delete() { store.delete(key(c, id)); },
  });
  for (const [id, data] of Object.entries(geo)) store.set(key('municipalityGeo', id), data);
  return {
    store,
    collection(c) {
      if (c === 'users') {
        const q = {
          where: () => q,
          async get() {
            return { forEach: (cb) => users.forEach((u) => cb({ id: u.uid, get: (f) => u[f] })) };
          },
        };
        return q;
      }
      return { doc: (id) => docRef(c, id) };
    },
  };
}

function mockFetch(handler) {
  const original = global.fetch;
  global.fetch = async (url) => {
    const body = await handler(String(url));
    return { ok: true, status: 200, json: async () => body, text: async () => String(body) };
  };
  return () => { global.fetch = original; };
}

const hourly = (mm) => ({
  hourly: {
    precipitation_ecmwf_ifs025: Array(48).fill(mm),
    precipitation_gfs_seamless: Array(48).fill(mm),
    precipitation_icon_seamless: Array(48).fill(mm),
  },
});

const forecastMock = (mm) => (url) => {
  if (url.includes('open-meteo')) return hourly(mm);
  throw new Error('HTTP 503');
};

const CITIZEN = (id, mun) => ({ uid: id, municipalityId: mun, role: 'citizen', disabled: false });
const GEO_A = { name: 'Zapala', province: 'Neuquén', lat: -37.5, lng: -69.5 };
const noSmn = { loadSmn: async () => [] };

test('runWeatherAlerts: dia argentino, dedupe, escalada de nivel 1 a 2 y sin vuelta atras', async () => {
  const db = fakeDb({ users: [CITIZEN('u1', 'georef_1')], geo: { georef_1: GEO_A } });
  // 01:30 UTC del 18 = 22:30 del 17 en Argentina.
  const late = new Date('2026-10-18T01:30:00Z');

  let restore = mockFetch(forecastMock(2)); // 2 mm/h * 24 = 48 mm -> aviso (nivel 1)
  try {
    assert.equal((await w.runWeatherAlerts(db, late, noSmn)).length, 1);
    assert.ok(db.store.has('weatherAlerts/georef_1_2026-10-17_rain_1'));
    assert.deepEqual(await w.runWeatherAlerts(db, late, noSmn), []); // repetida: nada nuevo
  } finally { restore(); }

  restore = mockFetch(forecastMock(4)); // 96 mm -> alerta (nivel 2): escalada, se avisa de nuevo
  try {
    assert.equal((await w.runWeatherAlerts(db, late, noSmn)).length, 1);
    assert.ok(db.store.has('weatherAlerts/georef_1_2026-10-17_rain_2'));
  } finally { restore(); }

  restore = mockFetch(forecastMock(2)); // vuelve a nivel 1: no se repite un aviso menor
  try {
    assert.deepEqual(await w.runWeatherAlerts(db, late, noSmn), []);
  } finally { restore(); }

  // Al dia siguiente (hora argentina) vuelve a avisar.
  restore = mockFetch(forecastMock(2));
  try {
    const out = await w.runWeatherAlerts(db, new Date('2026-10-18T04:00:00Z'), noSmn);
    assert.equal(out.length, 1);
    assert.ok(db.store.has('weatherAlerts/georef_1_2026-10-18_rain_1'));
  } finally { restore(); }
});

test('runWeatherAlerts: alerta del SMN por poligono; con el feed caido se sigue igual', async () => {
  const db = fakeDb({ users: [CITIZEN('u1', 'georef_1')], geo: { georef_1: GEO_A } });
  const restore = mockFetch(forecastMock(0));
  try {
    const smn = [w.parseCapAlert(capXml({ onset: '2026-10-18T10:00:00-03:00' }))];
    const out = await w.runWeatherAlerts(db, NOW, { loadSmn: async () => smn });
    assert.deepEqual(out.map((o) => o.alert), ['smn_rain_1']);
    const saved = db.store.get('weatherAlerts/georef_1_2026-10-18_smn_rain_1');
    assert.match(saved.title, /^SMN: Alerta amarilla por lluvias$/);

    const db2 = fakeDb({ users: [CITIZEN('u1', 'georef_1')], geo: { georef_1: GEO_A } });
    const down = await w.runWeatherAlerts(db2, NOW, { loadSmn: async () => { throw new Error('HTTP 503'); } });
    assert.deepEqual(down, []);
  } finally { restore(); }
});

test('runWeatherAlerts: un municipio que falla o se cuelga no aborta al resto', async () => {
  const db = fakeDb({
    users: [CITIZEN('u1', 'georef_1'), CITIZEN('u2', 'georef_2'), CITIZEN('u3', 'georef_3')],
    geo: {
      georef_1: GEO_A,
      georef_2: { name: 'Colgado', province: 'X', lat: 1, lng: 1 },
      georef_3: { name: 'Roto', province: 'X', lat: 2, lng: 2 },
    },
  });
  const restore = mockFetch((url) => {
    if (url.includes('open-meteo') && url.includes('latitude=1&')) return new Promise(() => {}); // nunca responde
    return forecastMock(4)(url);
  });
  try {
    const out = await w.runWeatherAlerts(db, NOW, {
      loadSmn: async () => [], municipalityTimeoutMs: 50, parallel: 2,
    });
    assert.deepEqual(out.filter((o) => o.alert).map((o) => o.municipalityId).sort(), ['georef_1', 'georef_3']);
    const errors = out.filter((o) => o.error);
    assert.deepEqual(errors.map((o) => o.municipalityId), ['georef_2']);
    assert.match(errors[0].error, /timeout/);
  } finally { restore(); }
});
