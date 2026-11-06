export function isCentralAdmin(profile) {
  return Boolean(profile && profile.disabled !== true &&
    profile.role === 'admin' && profile.organizationId === 'diagonales');
}
