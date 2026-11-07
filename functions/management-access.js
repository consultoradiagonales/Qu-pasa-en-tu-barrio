'use strict';

// La organización del proveedor se provisiona sólo en servidor.
function isCentralAdmin(profile) {
  return Boolean(profile && profile.disabled !== true &&
    profile.role === 'admin' && profile.organizationId === 'diagonales');
}

function canManageMunicipality(profile, municipalityId) {
  return Boolean(profile && profile.disabled !== true &&
    ['admin', 'coordinator', 'moderator'].includes(profile.role) &&
    (isCentralAdmin(profile) || (typeof municipalityId === 'string' &&
      municipalityId.length > 0 && profile.municipalityId === municipalityId)));
}

module.exports = { isCentralAdmin, canManageMunicipality };
