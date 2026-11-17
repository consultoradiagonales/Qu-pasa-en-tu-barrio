'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveDashboardScope } = require('./management-dashboard');

test('gerencia central consulta el ámbito global, provincial y municipal aun sin municipio propio', () => {
  const manager = { role: 'field_manager', organizationId: 'diagonales', disabled: false };
  assert.deepEqual(resolveDashboardScope(manager, { scope: 'all' }), { municipalityId: '', provinceId: '' });
  assert.deepEqual(resolveDashboardScope(manager, { provinceId: '06' }), { municipalityId: '', provinceId: '06' });
  assert.deepEqual(resolveDashboardScope(manager, { municipalityId: 'georef_06001' }), { municipalityId: 'georef_06001', provinceId: '' });
});

test('la gerencia sin organización central conserva únicamente su propio municipio', () => {
  const local = { role: 'field_manager', municipalityId: '06001', disabled: false };
  assert.deepEqual(resolveDashboardScope(local, {}), { municipalityId: '06001', provinceId: '' });
  assert.deepEqual(resolveDashboardScope(local, { municipalityId: 'georef_06001' }), { municipalityId: '06001', provinceId: '' });
  for (const scope of [{ scope: 'all' }, { provinceId: '06' }, { municipalityId: '06002' }]) {
    assert.throws(() => resolveDashboardScope(local, scope), { code: 'permission-denied' });
  }
  assert.throws(() => resolveDashboardScope({ ...local, disabled: true }, {}), { code: 'permission-denied' });
  assert.throws(() => resolveDashboardScope({ role: 'field_manager', disabled: false }, {}), { code: 'permission-denied' });
});
