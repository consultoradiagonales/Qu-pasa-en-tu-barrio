'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  cleanTeamText,
  cleanTeamMembers,
  cleanTeamCategories,
  validTeamId,
} = require('./index');

test('normaliza datos operativos de una cuadrilla', () => {
  assert.equal(cleanTeamText('  Zona\nNorte  '), 'Zona Norte');
  assert.deepEqual(cleanTeamMembers([' Ana ', 'Ana', '', 'Luis\nPérez']), ['Ana', 'Luis Pérez']);
  assert.deepEqual(
    cleanTeamCategories(['lighting', 'lighting', 'invalid', 'infrastructure']),
    ['lighting', 'infrastructure'],
  );
});

test('acepta sólo identificadores de cuadrilla seguros', () => {
  assert.equal(validTeamId('q2t5fc9024ae96142b7'), true);
  assert.equal(validTeamId('team/otro-municipio'), false);
  assert.equal(validTeamId('corto'), false);
});
