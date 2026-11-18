'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { residentDirectoryHandler } = require('./resident-directory');
const { FakeDb } = require('./test-helpers/fake-firestore');

const M = 'georef_060441';

function seed() {
  return new FakeDb({
    'users/central': { role: 'admin', organizationId: 'diagonales', disabled: false },
    'users/coord': { role: 'coordinator', municipalityId: M, disabled: false },
    'users/v1': { role: 'citizen', municipalityId: M, disabled: false, email: 'ana@x.com', realName: 'Ana' },
    'users/v2': { role: 'citizen', municipalityId: M, disabled: false },
    'users/v3': { role: 'citizen', municipalityId: 'otro', disabled: false, email: 'otro@x.com' },
    'users/v4': { role: 'citizen', municipalityId: M, disabled: true, email: 'baja@x.com' },
  });
}

function fakeAuth(calls = []) {
  return {
    async getUsers(ids) {
      calls.push(ids.map((i) => i.uid));
      return { users: ids.filter((i) => i.uid === 'v2').map(() => ({ uid: 'v2', email: 'jorge@x.com', displayName: 'Jorge' })) };
    },
  };
}

test('completa correo y nombre desde Auth sólo para quien no los tiene', async () => {
  const calls = [];
  const { residents } = await residentDirectoryHandler({ auth: { uid: 'coord' }, data: {} }, { db: seed(), auth: fakeAuth(calls) });
  assert.deepEqual(residents.map((r) => r.uid).sort(), ['v1', 'v2']);
  assert.deepEqual(residents.find((r) => r.uid === 'v2'), { uid: 'v2', email: 'jorge@x.com', name: 'Jorge' });
  assert.deepEqual(residents.find((r) => r.uid === 'v1'), { uid: 'v1', email: 'ana@x.com', name: 'Ana' });
  assert.deepEqual(calls, [['v2']]);
});

test('el personal no puede pedir otro municipio; la consultora sí', async () => {
  await assert.rejects(
    residentDirectoryHandler({ auth: { uid: 'coord' }, data: { municipalityId: 'otro' } }, { db: seed(), auth: fakeAuth() }),
    (error) => error.code === 'permission-denied',
  );
  const { residents } = await residentDirectoryHandler({ auth: { uid: 'central' }, data: { municipalityId: 'otro' } }, { db: seed(), auth: fakeAuth() });
  assert.deepEqual(residents.map((r) => r.email), ['otro@x.com']);
  await assert.rejects(
    residentDirectoryHandler({ auth: { uid: 'v1' }, data: {} }, { db: seed(), auth: fakeAuth() }),
    (error) => error.code === 'permission-denied',
  );
});
