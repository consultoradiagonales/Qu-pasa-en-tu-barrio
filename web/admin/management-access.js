export function isCentralAdmin(profile) {
  return Boolean(profile && profile.disabled !== true &&
    profile.role === 'admin' && profile.organizationId === 'diagonales');
}

export function hasGlobalOperationsAccess(profile) {
  return isCentralAdmin(profile) || Boolean(profile && profile.disabled !== true &&
    profile.role === 'field_manager' && profile.organizationId === 'diagonales');
}
