/**
 * Carga datos de prueba en el emulador de Firebase para poder ver el panel
 * de gestión funcionando: un municipio, equipos, usuarios con distintos roles
 * y una tanda de reportes en todos los estados.
 *
 * Uso:  node scripts/sembrar-emulador.mjs
 *
 * Requiere el emulador corriendo (firebase emulators:start).
 * No toca Firebase real: apunta a localhost por las variables de entorno.
 */

// Tiene que ser el MISMO projectId que usa firebase_options.dart, si no la app
// escribe en un proyecto del emulador y el script en otro.
const PROJECT = process.env.FIREBASE_PROJECT || 'project-5fc9024a-e961-42b7-9ee';
const AUTH = 'http://localhost:9099/identitytoolkit.googleapis.com/v1';
const FS = `http://localhost:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const KEY = 'fake-api-key'; // el emulador no valida la clave

const MUNICIPIO = 'la-plata';

// ── helpers para el formato de Firestore REST ──────────────────────────────
const S = (v) => ({ stringValue: v });
const N = (v) => ({ integerValue: String(v) });
const B = (v) => ({ booleanValue: v });
const T = (d) => ({ timestampValue: d.toISOString().replace(/\.\d+Z$/, 'Z') });
const NUL = { nullValue: null };
// OJO: ReportModel espera 'location' como MAPA {lat, lng, geohash, address},
// no como geoPointValue. Si se manda un GeoPoint, el cast a Map explota y el
// stream entero falla con "No pudimos cargar los reportes".
const UBIC = (lat, lng, dir) => ({
  mapValue: {
    fields: {
      lat: { doubleValue: lat },
      lng: { doubleValue: lng },
      geohash: S(''),
      address: S(dir),
    },
  },
});
const ARR = (vals) => ({ arrayValue: { values: vals } });
const MAPA = (obj) => ({ mapValue: { fields: obj } });
const D = (v) => ({ doubleValue: v });

/// Crea la cuenta, o entra si ya existe, para que el script se pueda correr
/// las veces que haga falta sin tener que reiniciar el emulador.
async function crearUsuario(email, password) {
  const alta = await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (alta.ok) return (await alta.json()).localId;

  const ingreso = await fetch(`${AUTH}/accounts:signInWithPassword?key=${KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (ingreso.ok) return (await ingreso.json()).localId;

  throw new Error(`alta de ${email}: ${await alta.text()}`);
}

async function escribir(path, fields) {
  const r = await fetch(`${FS}/${path}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      // El emulador trata este token como administrador y saltea las reglas.
      // Es lo que permite sembrar datos que un usuario común no podría crear,
      // como el municipio o los equipos. Solo funciona contra el emulador.
      Authorization: 'Bearer owner',
    },
    body: JSON.stringify({ fields }),
  });
  if (!r.ok) throw new Error(`escritura en ${path}: ${await r.text()}`);
}

// ── datos ──────────────────────────────────────────────────────────────────
const CUENTAS = [
  { email: 'coordinador@condi.test', pass: 'Coordinador2026', rol: 'coordinator', nombre: 'Laura Giménez' },
  { email: 'admin@condi.test',       pass: 'Administrador2026', rol: 'admin',     nombre: 'Martín Sosa' },
  { email: 'operario@condi.test',    pass: 'Operario2026',    rol: 'field_worker', nombre: 'Diego Paz', equipo: 'equipo-vialidad' },
  { email: 'vecina@condi.test',      pass: 'Vecina20260101',  rol: 'citizen',     nombre: 'Ana Ruiz' },
  { email: 'vecino@condi.test',      pass: 'Vecino20260101',  rol: 'citizen',     nombre: 'Jorge Lema' },
];

const EQUIPOS = [
  { id: 'equipo-vialidad',  nombre: 'Cuadrilla de Vialidad',  categorias: ['infrastructure', 'transport'] },
  { id: 'equipo-alumbrado', nombre: 'Cuadrilla de Alumbrado', categorias: ['lighting'] },
  { id: 'equipo-higiene',   nombre: 'Higiene Urbana',         categorias: ['garbage', 'environment'] },
];

const REPORTES = [
  { cat: 'infrastructure', estado: 'pending',     titulo: 'Bache profundo en la calzada',        desc: 'Bache de casi medio metro en 7 entre 44 y 45. Ya se rompieron dos autos.', lat: -34.9205, lng: -57.9536, apoyos: 14 },
  { cat: 'lighting',       estado: 'pending',     titulo: 'Cuatro luminarias apagadas',          desc: 'Toda la cuadra de 60 entre 12 y 13 quedó a oscuras hace una semana.',     lat: -34.9280, lng: -57.9620, apoyos: 9 },
  { cat: 'garbage',        estado: 'pending',     titulo: 'Microbasural en la esquina',          desc: 'Se acumula basura hace un mes en 32 y 19. Hay olor y roedores.',          lat: -34.9150, lng: -57.9480, apoyos: 23 },
  { cat: 'infrastructure', estado: 'assigned',    titulo: 'Vereda levantada por raíces',         desc: 'La raíz del árbol levantó las baldosas. Una señora ya se cayó.',          lat: -34.9240, lng: -57.9570, apoyos: 7, equipo: 'equipo-vialidad' },
  { cat: 'lighting',       estado: 'in_progress', titulo: 'Semáforo intermitente',               desc: 'El semáforo de 1 y 60 quedó en amarillo intermitente.',                   lat: -34.9310, lng: -57.9410, apoyos: 31, equipo: 'equipo-alumbrado' },
  { cat: 'garbage',        estado: 'resolved',    titulo: 'Contenedor volcado',                  desc: 'El contenedor de 13 y 42 estaba volcado y la basura desparramada.',       lat: -34.9190, lng: -57.9550, apoyos: 5, equipo: 'equipo-higiene' },
  { cat: 'environment',    estado: 'resolved',    titulo: 'Rama caída sobre el cableado',        desc: 'Una rama grande quedó apoyada sobre los cables de 8 y 38.',               lat: -34.9225, lng: -57.9495, apoyos: 12, equipo: 'equipo-higiene' },
];

// ── siembra ────────────────────────────────────────────────────────────────
const ahora = new Date();
const haceDias = (d) => new Date(ahora.getTime() - d * 86400000);

console.log('Sembrando el emulador...\n');

// Municipio
await escribir(`municipalities/${MUNICIPIO}`, {
  name: S('La Plata'),
  province: S('Buenos Aires'),
  active: B(true),
  createdAt: T(haceDias(90)),
});
console.log('  municipio: La Plata');

// Equipos
for (const e of EQUIPOS) {
  await escribir(`teams/${e.id}`, {
    name: S(e.nombre),
    municipalityId: S(MUNICIPIO),
    categories: ARR(e.categorias.map(S)),
    active: B(true),
  });
  console.log(`  equipo: ${e.nombre}`);
}

// Usuarios
const uids = {};
for (const c of CUENTAS) {
  const uid = await crearUsuario(c.email, c.pass);
  uids[c.rol] = uid;
  await escribir(`users/${uid}`, {
    displayName: S(`Usuario #${uid.slice(0, 4).toUpperCase()}`),
    realName: S(c.nombre),
    email: S(c.email),
    photoURL: NUL,
    role: S(c.rol),
    teamId: c.equipo ? S(c.equipo) : NUL,
    municipalityId: S(MUNICIPIO),
    fcmToken: NUL,
    createdAt: T(haceDias(30)),
    lastReportAt: NUL,
    reportsCount: N(0),
    disabled: B(false),
  });
  console.log(`  usuario: ${c.email.padEnd(26)} ${c.rol}`);
}

// Reportes
const porEstado = { pending: 0, assigned: 0, in_progress: 0, resolved: 0 };
let i = 0;
for (const r of REPORTES) {
  i++;
  const id = `reporte-${String(i).padStart(3, '0')}`;
  const creado = haceDias(REPORTES.length - i + 1);
  porEstado[r.estado]++;

  const campos = {
    userId: S(i % 2 === 0 ? uids.citizen : uids.citizen),
    municipalityId: S(MUNICIPIO),
    category: S(r.cat),
    title: S(r.titulo),
    description: S(r.desc),
    location: UBIC(r.lat, r.lng, 'La Plata, Buenos Aires'),
    status: S(r.estado),
    priority: N(1),
    photosReport: ARR([]),
    photosBefore: ARR([]),
    photosProgress: ARR([]),
    photosAfter: ARR([]),
    supportCount: N(r.apoyos),
    flaggedCount: N(0),
    commentsCount: N(0),
    hidden: B(false),
    createdAt: T(creado),
    updatedAt: T(creado),
    assignedTeamId: r.equipo ? S(r.equipo) : NUL,
    assignedWorkerId: r.estado === 'in_progress' ? S(uids.field_worker) : NUL,
    resolvedAt: r.estado === 'resolved' ? T(haceDias(1)) : NUL,
    rating: NUL,
    ratingComment: NUL,
  };
  await escribir(`reports/${id}`, campos);
  console.log(`  reporte: ${r.titulo.slice(0, 38).padEnd(40)} ${r.estado}`);
}

// Estadísticas del municipio.
// El shape tiene que coincidir con MunicipalityStats.fromFirestore:
// statusCounts y categoryCounts son MAPAS, no campos sueltos.
const porCategoria = {};
for (const r of REPORTES) {
  porCategoria[r.cat] = (porCategoria[r.cat] ?? 0) + 1;
}
const apoyosTotales = REPORTES.reduce((a, r) => a + r.apoyos, 0);

await escribir(`municipalityStats/${MUNICIPIO}`, {
  total: N(REPORTES.length),
  supports: N(apoyosTotales),
  statusCounts: MAPA(Object.fromEntries(
    Object.entries(porEstado).map(([k, v]) => [k, N(v)]),
  )),
  categoryCounts: MAPA(Object.fromEntries(
    Object.entries(porCategoria).map(([k, v]) => [k, N(v)]),
  )),
  resolutionCount: N(porEstado.resolved),
  resolutionHoursSum: D(porEstado.resolved * 52.0),
  updatedAt: T(ahora),
});

console.log('\nListo.\n');
console.log('Entrá al panel con:');
console.log('  coordinador@condi.test / Coordinador2026');
console.log('  admin@condi.test       / Administrador2026');
console.log('\nY como vecina:');
console.log('  vecina@condi.test      / Vecina20260101');
