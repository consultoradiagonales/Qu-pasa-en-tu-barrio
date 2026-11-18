'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  cleanAdText,
  validAdId,
  validHttpsUrl,
  cleanAdDismissMode,
  adDate,
  adImageBuffer,
} = require('./index');

test('normaliza los textos y las modalidades comerciales de un anuncio', () => {
  assert.equal(cleanAdText('  Feria\nlocal  '), 'Feria local');
  assert.equal(cleanAdDismissMode('wait_7_seconds'), 'wait_7_seconds');
  assert.equal(cleanAdDismissMode('otro-plan'), 'close_now');
});

test('acepta identificadores y enlaces seguros para anuncios', () => {
  assert.equal(validAdId('yX7Q3ftmwq5RR6w7sP12'), true);
  assert.equal(validAdId('ad/con/barra'), false);
  assert.equal(validHttpsUrl('https://comercio.example/oferta'), true);
  assert.equal(validHttpsUrl('http://comercio.example/oferta'), false);
  assert.equal(validHttpsUrl('https://usuario:clave@comercio.example/oferta'), false);
});

test('acepta sólo fechas de pauta dentro de un rango razonable', () => {
  assert.equal(adDate(Date.UTC(2026, 0, 1)) instanceof Date, true);
  assert.equal(adDate(Date.UTC(2019, 11, 31)), null);
  assert.equal(adDate('2026-01-01'), null);
});

test('valida tipo, firma y tamaño de la imagen publicitaria', () => {
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.deepEqual(adImageBuffer(png.toString('base64'), 'image/png'), png);
  assert.throws(() => adImageBuffer(Buffer.from('texto').toString('base64'), 'image/png'));
  assert.throws(() => adImageBuffer(png.toString('base64'), 'image/gif'));
});
