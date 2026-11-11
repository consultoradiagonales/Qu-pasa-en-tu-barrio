'use strict';

// La organización del proveedor se provisiona sólo en servidor.
function isCentralAdmin(profile) {
  return Boolean(profile && profile.disabled !== true &&
    profile.role === 'admin' && profile.organizationId === 'diagonales');
}

function canonicalMunicipalityId(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  return id.replace(/^georef_/, '');
}

function municipalityAliases(value) {
  const id = typeof value === 'string' ? value.trim() : '';
  if (!id) return [];
  if (/^georef_\d+$/.test(id)) return [id, id.slice(7)];
  if (/^\d+$/.test(id)) return [id, `georef_${id}`];
  return [id];
}

function sameMunicipality(left, right) {
  const leftId = canonicalMunicipalityId(left);
  return Boolean(leftId && leftId === canonicalMunicipalityId(right));
}

function canManageMunicipality(profile, municipalityId) {
  return Boolean(profile && profile.disabled !== true &&
    ['admin', 'coordinator', 'moderator'].includes(profile.role) &&
    (isCentralAdmin(profile) || (typeof municipalityId === 'string' &&
      municipalityId.length > 0 && sameMunicipality(profile.municipalityId, municipalityId))));
}

module.exports = { canonicalMunicipalityId, municipalityAliases, sameMunicipality, isCentralAdmin, canManageMunicipality };
