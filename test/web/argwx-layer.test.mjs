// node --test test/web/argwx-layer.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { ARGWX_ID_BY_GEOREF } from '../../web/admin/argwx-municipalities.js';
import {
  argwxIdFor, argwxPartidos, buildWeatherView, coverageFor, dashboardUrlFor, describe, loadArgwxBlindspots,
  loadArgwxData, partidoWindows, resetArgwxCache,
} from '../../web/admin/argwx-layer.js';

const NOW = Date.parse('2026-11-06T13:00:00Z');
const square = (id, name) => ({ type: 'Feature', properties: { id, name }, geometry: { type: 'Polygon', coordinates: [[[0, 0], [1, 0], [1, 1], [0, 0]]] } });
const geo = { features: [square('la-plata', 'La Plata'), square('escobar', 'Escobar'), square('saladillo', 'Saladillo')] };
const alerts = (generated = '2026-11-06T12:12:43Z') => ({
  generated_at: generated,
  data_mode: 'live',
  models: Array(9).fill('M'),
  windows: {
    24: {
      label: 'Próximas 24 h',
      valid_to: '2026-11-07T12:00:00Z',
      municipios: [
        { id: 'la-plata', name: 'La Plata', alert_level: 'YELLOW', hazard: 'tormenta', confidence_label: 'Oficial SMN', lluvia_mm: 13.5, prob_lluvia: { 10: { probabilidad: 83.8, confiable: true } } },
        { id: 'escobar', name: 'Escobar', alert_level: 'GREEN', confidence_label: 'Alta', consensus: '9/9', lluvia_mm: 0.4 },
      ],
    },
  },
});

test('la tabla del panel coincide con la de la app (135 partidos)', () => {
  assert.equal(Object.keys(ARGWX_ID_BY_GEOREF).length, 135);
  assert.equal(new Set(Object.values(ARGWX_ID_BY_GEOREF)).size, 135);
  assert.equal(argwxIdFor('georef_060441'), 'la-plata');
  assert.equal(argwxIdFor('georef_06826'), 'trenque-lauquen');
  assert.equal(argwxIdFor('georef_140014'), null);
});

test('alcance: el municipio ve sólo su partido; Diagonales ve la provincia', () => {
  assert.deepEqual([...coverageFor({ type: 'municipality', municipalityId: 'georef_060441' }).ids], ['la-plata']);
  assert.deepEqual([...coverageFor({ type: 'locality', municipalityId: 'georef_060252', localityId: 'x' }).ids], ['escobar']);
  assert.equal(coverageFor({ type: 'all' }).ids, null);
  assert.equal(coverageFor({ type: 'province', provinceId: '06' }).ids, null);
  assert.equal(coverageFor({ type: 'province', provinceId: '14' }).mode, 'none');
  assert.equal(coverageFor({ type: 'municipality', municipalityId: 'georef_140014' }).mode, 'none');
});

test('un municipio sólo dibuja su propio partido', () => {
  const view = buildWeatherView({ alerts: alerts(), geo }, coverageFor({ type: 'municipality', municipalityId: 'georef_060441' }), '24', NOW);
  assert.deepEqual(view.features.map((f) => f.id), ['la-plata']);
  assert.equal(view.features[0].official, true);
  assert.equal(view.features[0].rainOver10, 83.8);
  assert.equal(describe(view.features[0]).head, 'Alerta amarilla por tormenta');
  assert.equal(describe(view.features[0]).source, 'Fuente: alerta oficial del SMN');
});

test('provincia: ordena por gravedad y un partido sin dato no queda verde', () => {
  const view = buildWeatherView({ alerts: alerts(), geo }, coverageFor({ type: 'all' }), '24', NOW);
  assert.deepEqual(view.features.map((f) => f.id), ['la-plata', 'escobar', 'saladillo']);
  assert.equal(view.withAlert.length, 1);
  assert.equal(view.official, 1);
  assert.equal(view.missing, 1);
  const saladillo = view.features.find((f) => f.id === 'saladillo');
  assert.equal(saladillo.level, 'UNKNOWN');
  assert.match(describe(saladillo).source, /no significa ausencia de riesgo/i);
});

test('ventana sin datos y datos viejos se señalan', () => {
  const view = buildWeatherView({ alerts: alerts('2026-11-06T06:00:00Z'), geo }, coverageFor({ type: 'all' }), '48', NOW);
  assert.equal(view.stale, true);
  assert.equal(view.missing, 3);
  assert.equal(view.withAlert.length, 0);
});

test('la descarga se reutiliza y un error del motor se informa', async () => {
  resetArgwxCache();
  let calls = 0;
  const ok = async (url) => { calls += 1; return { ok: true, json: async () => (url.endsWith('.geojson') ? geo : alerts()) }; };
  await loadArgwxData({ fetchImpl: ok, now: () => NOW });
  await loadArgwxData({ fetchImpl: ok, now: () => NOW + 60_000 });
  assert.equal(calls, 2); // avisos + límites, una sola vez
  resetArgwxCache();
  await assert.rejects(loadArgwxData({ fetchImpl: async () => ({ ok: false }), now: () => NOW }), /no disponibles/);
});

test('enfoque por partido: lista ordenada, tres ventanas y enlace al tablero', () => {
  assert.deepEqual(argwxPartidos({ geo }).map((p) => p.id), ['escobar', 'la-plata', 'saladillo']);
  const w = partidoWindows({ alerts: alerts() }, 'la-plata');
  assert.deepEqual(w.map((x) => x.key), ['24', '48', '72']);
  assert.equal(w[0].level, 'YELLOW');
  assert.equal(w[1].level, 'UNKNOWN'); // ventana sin datos: nunca verde
  assert.equal(dashboardUrlFor('la-plata'), 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/#partido=la-plata');
  assert.equal(dashboardUrlFor(''), 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/');
});

test('puntos ciegos: sin archivo publicado devuelve null, no un error', async () => {
  resetArgwxCache();
  assert.equal(await loadArgwxBlindspots({ fetchImpl: async () => ({ ok: false }), now: () => NOW }), null);
  resetArgwxCache();
  const data = { windows: { 24: { 'la-plata': { riesgo: 'Medio' } } } };
  const got = await loadArgwxBlindspots({ fetchImpl: async () => ({ ok: true, json: async () => data }), now: () => NOW });
  assert.equal(got.windows[24]['la-plata'].riesgo, 'Medio');
});
