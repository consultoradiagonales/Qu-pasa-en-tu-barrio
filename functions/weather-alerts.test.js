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
