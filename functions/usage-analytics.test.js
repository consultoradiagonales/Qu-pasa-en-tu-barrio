'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  MIN_VISIBLE_CITY_USERS,
  aggregateUsage,
  dateRange,
  territoryFromProfile,
} = require('./usage-analytics');

test('territorio de uso toma localidad y municipio del perfil, sin IP ni coordenadas', () => {
  const territory = territoryFromProfile({
    municipalityId: '060707',
    municipalityName: 'Saladillo',
    localityId: 'saladillo',
    locality: 'Saladillo',
    provinceId: '06',
    province: 'Buenos Aires',
    ip: '198.51.100.10',
    location: { lat: -35.6, lng: -59.7 },
  });
  assert.deepEqual(territory, {
    municipalityId: '060707',
    municipalityName: 'Saladillo',
    localityId: 'saladillo',
    city: 'Saladillo',
    provinceId: '06',
    province: 'Buenos Aires',
  });
  assert.ok(!JSON.stringify(territory).includes('198.51.100.10'));
  assert.ok(!JSON.stringify(territory).includes('lat'));
});

test('la analítica suma sesiones y oculta ciudades que no alcanzan el umbral diario', () => {
  const dayKeys = ['2026-10-15', '2026-10-16'];
  const result = aggregateUsage([
    {
      date: '2026-10-15', municipalityId: '060707', municipalityName: 'Saladillo',
      localityId: 'saladillo', city: 'Saladillo', provinceId: '06', province: 'Buenos Aires', activeUsers: 4,
    },
    {
      date: '2026-10-16', municipalityId: '060707', municipalityName: 'Saladillo',
      localityId: 'saladillo', city: 'Saladillo', provinceId: '06', province: 'Buenos Aires', activeUsers: 2,
    },
    {
      date: '2026-10-15', municipalityId: '06441', municipalityName: 'La Plata',
      localityId: 'la-plata', city: 'La Plata', provinceId: '06', province: 'Buenos Aires', activeUsers: 1,
    },
  ], { dayKeys });

  assert.equal(result.totalSessions, 7);
  assert.equal(result.activeUsersToday, 2);
  assert.equal(result.cities.length, 1);
  assert.equal(result.cities[0].city, 'Saladillo');
  assert.equal(result.cities[0].maxDailyUsers, 4);
  assert.equal(result.suppressedCities, 1);
  assert.equal(MIN_VISIBLE_CITY_USERS, 3);
});

test('el intervalo se limita a 90 días y entrega fechas ordenadas', () => {
  const range = dateRange(200, new Date('2026-10-17T12:00:00-03:00'));
  assert.equal(range.length, 90);
  assert.ok(range[0] < range.at(-1));
  assert.equal(range.at(-1), '2026-10-17');
});
