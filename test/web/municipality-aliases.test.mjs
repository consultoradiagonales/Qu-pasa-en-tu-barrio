import test from 'node:test';
import assert from 'node:assert/strict';
import { municipalityAliases, sameMunicipality } from '../../web/admin/municipality-branding.js';

test('el código GeoRef y el código municipal histórico son el mismo ámbito', () => {
  assert.deepEqual(municipalityAliases('060707'), ['060707', 'georef_060707']);
  assert.deepEqual(municipalityAliases('georef_060707'), ['georef_060707', '060707']);
  assert.equal(sameMunicipality('060707', 'georef_060707'), true);
  assert.equal(sameMunicipality('060707', '060441'), false);
});
