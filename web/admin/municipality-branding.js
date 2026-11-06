export function identityKey(value) {
  return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()
    .replace(/^georef[_-]/,'').replace(/^municipalidad de /,'').replace(/[^a-z0-9]/g,'');
}

export function findMunicipalityIdentity(catalog, id, name) {
  const candidates = catalog?.municipalities || [];
  const idKey = identityKey(id);
  const byId = candidates.find(item => [item.id,item.code,item.censusCode,item.key,item.name].some(alias => identityKey(alias) === idKey));
  if (byId) return byId;
  const nameKey = identityKey(name);
  return nameKey ? candidates.find(item => identityKey(item.name) === nameKey) || null : null;
}
