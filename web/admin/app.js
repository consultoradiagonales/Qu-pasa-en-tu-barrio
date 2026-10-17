import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js';
import {
  GoogleAuthProvider,
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js';
import {
  collection,
  doc,
  getDoc,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  where,
} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js';
import { getFunctions, httpsCallable } from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-functions.js';

const firebaseConfig = {
  apiKey: 'AIzaSyAq8vtaTmwWkYaJGSdXj6wtbhGwWLZm00Y',
  authDomain: 'project-5fc9024a-e961-42b7-9ee.firebaseapp.com',
  projectId: 'project-5fc9024a-e961-42b7-9ee',
  storageBucket: 'project-5fc9024a-e961-42b7-9ee.firebasestorage.app',
  messagingSenderId: '949079641355',
  appId: '1:949079641355:web:93b3655887afd98a94e60e',
  measurementId: 'G-QW4Q8449WR',
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const functions = getFunctions(app, 'southamerica-east1');
const assignReportTeam = httpsCallable(functions, 'assignReportTeam');
const setReportPriority = httpsCallable(functions, 'setReportPriority');
const sendReportUpdate = httpsCallable(functions, 'sendReportUpdate');
const generateMunicipalityReport = httpsCallable(functions, 'generateMunicipalityReport');
const saveTeam = httpsCallable(functions, 'saveTeam');
const saveLocalAd = httpsCallable(functions, 'saveLocalAd');
const uploadLocalAdImage = httpsCallable(functions, 'uploadLocalAdImage');
const getUsageSummary = httpsCallable(functions, 'getUsageSummary');
const getAppRelease = httpsCallable(functions, 'getAppRelease');
const saveAppRelease = httpsCallable(functions, 'saveAppRelease');

const OWNER_EMAIL = 'info.consultoradiagonales@gmail.com';
const MANAGEMENT_ROLES = new Set(['admin', 'coordinator', 'moderator']);
const CLOSED_STATUSES = new Set(['resolved', 'closed', 'rejected']);
const STATUS_LABELS = {
  pending: 'Pendiente',
  assigned: 'Asignado',
  in_progress: 'En curso',
  resolved: 'Resuelto',
  rejected: 'Rechazado',
  closed: 'Cerrado',
};
const CATEGORY_LABELS = {
  infrastructure: 'Infraestructura',
  lighting: 'Alumbrado',
  garbage: 'Residuos',
  security: 'Seguridad',
  health: 'Salud',
  transport: 'Transporte',
  environment: 'Ambiente',
  other: 'Otros',
};
const ROLE_LABELS = { admin: 'Administración', coordinator: 'Coordinación', moderator: 'Moderación' };
const VIEW_TITLES = {
  overview: ['OPERACIÓN MUNICIPAL', 'Resumen operativo'],
  reports: ['SEGUIMIENTO DE SOLUCIONES', 'Reportes y evidencia'],
  map: ['COBERTURA TERRITORIAL', 'Mapa operativo'],
  teams: ['CAPACIDAD OPERATIVA', 'Cuadrillas'],
  ads: ['PUBLICIDAD LOCAL', 'Banners para vecinos'],
  usage: ['USO TERRITORIAL', 'Uso de la app'],
  release: ['PUBLICACIÓN DE LA APP', 'Actualización obligatoria'],
  strategy: ['ASISTENCIA PARA LA DECISIÓN', 'Decisiones IA'],
};
// Centros de respaldo para los municipios actualmente operativos. Los datos
// cargados en /municipalities pueden definir mapCenter, mapBounds y mapZoom
// para reemplazarlos sin tocar el panel.
const MUNICIPALITY_VIEWPORTS = Object.freeze({
  'la-plata': { center: [-34.9205, -57.9536], zoom: 12 },
  'partido-de-la-plata': { center: [-34.9205, -57.9536], zoom: 12 },
  '06441': { center: [-34.9205, -57.9536], zoom: 12 },
  'georef-06441': { center: [-34.9205, -57.9536], zoom: 12 },
  'saladillo': { center: [-35.6384, -59.7779], zoom: 13 },
  '060707': { center: [-35.6384, -59.7779], zoom: 13 },
  'georef-060707': { center: [-35.6384, -59.7779], zoom: 13 },
});

const $ = (id) => document.getElementById(id);
const elements = {
  appLoading: $('app-loading'),
  authScreen: $('auth-screen'),
  accessDenied: $('access-denied'),
  adminShell: $('admin-shell'),
  loginForm: $('login-form'),
  loginEmail: $('login-email'),
  loginPassword: $('login-password'),
  loginMessage: $('login-message'),
  googleLogin: $('google-login'),
  deniedCopy: $('denied-copy'),
  deniedSignout: $('denied-signout'),
  municipalityWrap: $('municipality-wrap'),
  municipalitySelect: $('municipality-select'),
  pageKicker: $('page-kicker'),
  pageTitle: $('page-title'),
  profileInitial: $('profile-initial'),
  profileName: $('profile-name'),
  profileRole: $('profile-role'),
  profileEmail: $('profile-email'),
  profileMenu: $('profile-menu'),
  profilePopover: $('profile-popover'),
  signout: $('signout'),
  refreshData: $('refresh-data'),
  mobileMenu: $('mobile-menu'),
  navOpenCount: $('nav-open-count'),
  overviewHeading: $('overview-heading'),
  overviewSubtitle: $('overview-subtitle'),
  metricOpen: $('metric-open'),
  metricOpenDetail: $('metric-open-detail'),
  metricUnassigned: $('metric-unassigned'),
  metricField: $('metric-field'),
  metricResolved: $('metric-resolved'),
  metricResolvedDetail: $('metric-resolved-detail'),
  metricResolution: $('metric-resolution'),
  priorityList: $('priority-list'),
  categoryTotal: $('category-total'),
  categoryBars: $('category-bars'),
  hotspotList: $('hotspot-list'),
  riskList: $('risk-list'),
  reportSearch: $('report-search'),
  statusFilter: $('status-filter'),
  priorityFilter: $('priority-filter'),
  reportCount: $('report-count'),
  reportsBody: $('reports-body'),
  reportsEmpty: $('reports-empty'),
  mapSummary: $('map-summary'),
  mapHotspots: $('map-hotspots'),
  adsNav: $('ads-nav'),
  releaseNav: $('release-nav'),
  teamsSummary: $('teams-summary'),
  teamsGrid: $('teams-grid'),
  teamsEmpty: $('teams-empty'),
  newTeam: $('new-team'),
  teamEditor: $('team-editor'),
  teamEditorKicker: $('team-editor-kicker'),
  teamEditorTitle: $('team-editor-title'),
  teamForm: $('team-form'),
  teamId: $('team-id'),
  teamName: $('team-name'),
  teamMunicipality: $('team-municipality'),
  teamZone: $('team-zone'),
  teamZoneManager: $('team-zone-manager'),
  teamMaintenanceChief: $('team-maintenance-chief'),
  teamCategories: $('team-categories'),
  teamMembers: $('team-members'),
  teamActive: $('team-active'),
  saveTeam: $('save-team'),
  cancelTeam: $('cancel-team'),
  cancelTeamForm: $('cancel-team-form'),
  adsSummary: $('ads-summary'),
  adsGrid: $('ads-grid'),
  adsEmpty: $('ads-empty'),
  newAd: $('new-ad'),
  adEditor: $('ad-editor'),
  adEditorKicker: $('ad-editor-kicker'),
  adEditorTitle: $('ad-editor-title'),
  adForm: $('ad-form'),
  adId: $('ad-id'),
  adMunicipality: $('ad-municipality'),
  adBusiness: $('ad-business'),
  adMessage: $('ad-message'),
  adLink: $('ad-link'),
  adImageUrl: $('ad-image-url'),
  adImageFile: $('ad-image-file'),
  adDismissMode: $('ad-dismiss-mode'),
  adStartDate: $('ad-start-date'),
  adEndDate: $('ad-end-date'),
  adActive: $('ad-active'),
  saveAd: $('save-ad'),
  cancelAd: $('cancel-ad'),
  cancelAdForm: $('cancel-ad-form'),
  usageTotal: $('usage-total'),
  usageToday: $('usage-today'),
  usageCities: $('usage-cities'),
  usagePeriods: $('usage-periods'),
  usageCityList: $('usage-city-list'),
  usageNotice: $('usage-notice'),
  releaseForm: $('release-form'),
  releaseMinAndroidBuild: $('release-min-android-build'),
  releaseAndroidStoreUrl: $('release-android-store-url'),
  releaseAndroidMessage: $('release-android-message'),
  releaseStatus: $('release-status'),
  saveRelease: $('save-release'),
  aiPeriod: $('ai-period'),
  generateAi: $('generate-ai'),
  overviewAiButton: $('overview-ai-button'),
  aiState: $('ai-state'),
  aiResults: $('ai-results'),
  aiSummaryTitle: $('ai-summary-title'),
  aiSummaryText: $('ai-summary-text'),
  aiPriorities: $('ai-priorities'),
  aiStrategies: $('ai-strategies'),
  aiRisks: $('ai-risks'),
  aiQuestions: $('ai-questions'),
  drawer: $('report-drawer'),
  drawerBackdrop: $('drawer-backdrop'),
  drawerTitle: $('drawer-title'),
  drawerContent: $('drawer-content'),
  closeDrawer: $('close-drawer'),
  photoViewer: $('photo-viewer'),
  photoViewerBackdrop: $('photo-viewer-backdrop'),
  photoViewerImage: $('photo-viewer-image'),
  closePhotoViewer: $('close-photo-viewer'),
  toastRegion: $('toast-region'),
};

const state = {
  authVersion: 0,
  user: null,
  profile: null,
  reports: [],
  teams: [],
  ads: [],
  municipalities: [],
  scope: 'all',
  currentView: 'overview',
  search: '',
  status: 'all',
  priority: 'all',
  selectedReportId: null,
  unsubReports: null,
  unsubTeams: null,
  unsubAds: null,
  unsubMunicipalities: null,
  map: null,
  mapLayer: null,
  mapHasFitted: false,
  mapScopeKey: null,
  photoTrigger: null,
  editingTeamId: null,
  editingAdId: null,
  usage: null,
  usageLoading: false,
  usageError: '',
  usageScopeKey: '',
  appRelease: null,
  releaseLoading: false,
};

function element(tag, options = {}) {
  const node = document.createElement(tag);
  Object.entries(options).forEach(([key, value]) => {
    if (value == null) return;
    if (key === 'className') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key === 'htmlFor') node.htmlFor = value;
    else if (key === 'type') node.type = value;
    else if (key === 'value') node.value = value;
    else if (key === 'disabled') node.disabled = Boolean(value);
    else if (key === 'href') node.href = value;
    else if (key === 'target') node.target = value;
    else if (key === 'rel') node.rel = value;
    else if (key === 'placeholder') node.placeholder = value;
    else if (key === 'title') node.title = value;
    else if (key === 'ariaLabel') node.setAttribute('aria-label', value);
    else if (key === 'onClick') node.addEventListener('click', value);
    else if (key === 'onChange') node.addEventListener('change', value);
    else if (key === 'onInput') node.addEventListener('input', value);
    else if (key === 'dataset') Object.entries(value).forEach(([name, data]) => { node.dataset[name] = data; });
    else node.setAttribute(key, value);
  });
  return node;
}

function dateFrom(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function formatDate(value, options = {}) {
  const date = dateFrom(value);
  if (!date) return 'Sin fecha';
  return new Intl.DateTimeFormat('es-AR', {
    day: '2-digit', month: 'short', year: 'numeric', ...options,
  }).format(date);
}

function relativeAge(value) {
  const date = dateFrom(value);
  if (!date) return 'Sin fecha';
  const hours = Math.max(0, (Date.now() - date.getTime()) / 3600000);
  if (hours < 1) return 'Hace menos de 1 h';
  if (hours < 24) return `Hace ${Math.floor(hours)} h`;
  const days = Math.floor(hours / 24);
  return `Hace ${days} ${days === 1 ? 'día' : 'días'}`;
}

function hoursBetween(start, end) {
  const from = dateFrom(start);
  const to = dateFrom(end);
  if (!from || !to) return null;
  const hours = (to.getTime() - from.getTime()) / 3600000;
  return Number.isFinite(hours) && hours >= 0 ? hours : null;
}

function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function safeText(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function statusLabel(status) { return STATUS_LABELS[status] || 'Pendiente'; }
function categoryLabel(category) { return CATEGORY_LABELS[category] || CATEGORY_LABELS.other; }
function isOpen(report) { return !CLOSED_STATUSES.has(report.status); }
function isHigh(report) { return number(report.priority, 1) >= 4; }
function reportName(report) { return safeText(report.title, `${categoryLabel(report.category)} sin título`); }
function reportLocation(report) { return safeText(report.location?.address, 'Ubicación geolocalizada'); }
function roleLabel(role) { return ROLE_LABELS[role] || 'Gestión municipal'; }
function normalizedKey(value) {
  return safeText(value)
    .toLocaleLowerCase('es')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}
function validMapPoint(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -85 && lat <= 85 && lng >= -180 && lng <= 180;
}
function mapPoint(value) {
  if (Array.isArray(value) && value.length >= 2) {
    const lat = number(value[0], NaN);
    const lng = number(value[1], NaN);
    return validMapPoint(lat, lng) ? [lat, lng] : null;
  }
  if (!value || typeof value !== 'object') return null;
  const lat = number(value.lat ?? value.latitude ?? value._latitude, NaN);
  const lng = number(value.lng ?? value.longitude ?? value._longitude, NaN);
  return validMapPoint(lat, lng) ? [lat, lng] : null;
}
function mapBounds(value) {
  if (Array.isArray(value) && value.length === 2) {
    const southWest = mapPoint(value[0]);
    const northEast = mapPoint(value[1]);
    return southWest && northEast ? [southWest, northEast] : null;
  }
  if (Array.isArray(value) && value.length === 4) {
    const southWest = mapPoint([value[0], value[1]]);
    const northEast = mapPoint([value[2], value[3]]);
    return southWest && northEast ? [southWest, northEast] : null;
  }
  if (!value || typeof value !== 'object') return null;
  const southWest = mapPoint(value.southWest ?? [value.south ?? value.minLat, value.west ?? value.minLng]);
  const northEast = mapPoint(value.northEast ?? [value.north ?? value.maxLat, value.east ?? value.maxLng]);
  return southWest && northEast ? [southWest, northEast] : null;
}
function municipalityForScope(scope = scopeParts()) {
  if (!['municipality', 'locality'].includes(scope.type)) return null;
  return state.municipalities.find((item) => item.id === scope.municipalityId) ||
    municipalityChoices().find((item) => item.id === scope.municipalityId) || null;
}
function municipalityViewport(scope = scopeParts()) {
  const municipality = municipalityForScope(scope);
  if (!municipality) return null;
  const center = mapPoint(municipality.mapCenter);
  const bounds = mapBounds(municipality.mapBounds);
  const zoom = Math.max(8, Math.min(16, number(municipality.mapZoom, 13)));
  if (bounds) return { bounds, zoom };
  if (center) return { center, zoom };
  return MUNICIPALITY_VIEWPORTS[normalizedKey(municipality.id)] ||
    MUNICIPALITY_VIEWPORTS[normalizedKey(municipality.name)] || null;
}
function geographicPoint(report) {
  if (report?.location?.isManualAddress === true) return null;
  return mapPoint(report.location);
}
function squaredDistanceKm(a, b) {
  const latitudeKm = (a[0] - b[0]) * 111;
  const longitudeKm = (a[1] - b[1]) * 111 * Math.cos(((a[0] + b[0]) / 2) * Math.PI / 180);
  return (latitudeKm * latitudeKm) + (longitudeKm * longitudeKm);
}
function mapPointsFor(reports) {
  return reports.map(geographicPoint).filter(Boolean);
}
function focusedPoints(points) {
  if (points.length < 3) return points;
  let best = { point: points[0], count: -1, distance: Infinity };
  points.forEach((candidate) => {
    const nearby = points.filter((point) => squaredDistanceKm(candidate, point) <= 45 * 45);
    const distance = nearby.reduce((sum, point) => sum + squaredDistanceKm(candidate, point), 0);
    if (nearby.length > best.count || (nearby.length === best.count && distance < best.distance)) {
      best = { point: candidate, count: nearby.length, distance };
    }
  });
  return best.count >= 2
    ? points.filter((point) => squaredDistanceKm(best.point, point) <= 45 * 45)
    : points;
}
function focusMapOnScope(reports) {
  if (!state.map) return;
  const viewport = municipalityViewport();
  if (viewport?.bounds) {
    state.map.fitBounds(viewport.bounds, { padding: [32, 32], maxZoom: viewport.zoom, animate: true });
    return;
  }
  if (viewport?.center) {
    state.map.setView(viewport.center, viewport.zoom, { animate: true });
    return;
  }
  const points = focusedPoints(mapPointsFor(reports));
  if (points.length > 1) {
    state.map.fitBounds(points, { padding: [32, 32], maxZoom: 13, animate: true });
  } else if (points.length === 1) {
    state.map.setView(points[0], 15, { animate: true });
  }
}
function scopeParts(value = state.scope) {
  if (!value || value === 'all') return { type: 'all' };
  const [type, first = '', second = ''] = value.split('|');
  if (type === 'municipality') return { type, municipalityId: first };
  if (type === 'province') return { type, provinceId: first };
  if (type === 'locality') return { type, municipalityId: first, localityId: second };
  return { type: 'municipality', municipalityId: value };
}
function municipalityFor(report) {
  return state.municipalities.find((item) => item.id === report.municipalityId) || null;
}
function territoryFor(report) {
  const municipality = municipalityFor(report);
  const addressTerritory = safeText(report.location?.address).split('·')[0]?.trim() || '';
  const addressParts = addressTerritory.split(',').map((part) => part.trim()).filter(Boolean);
  const municipalityName = safeText(report.municipalityName, municipality?.name || report.municipalityId);
  const municipalityIndex = addressParts.findIndex((part) => normalizedKey(part) === normalizedKey(municipalityName));
  const derivedLocality = municipalityIndex > 0 ? addressParts[municipalityIndex - 1] : '';
  const provinceName = safeText(report.province, safeText(municipality?.province, addressParts.length > 1 ? addressParts[addressParts.length - 1] : ''));
  const localityName = safeText(report.locality, derivedLocality);
  return {
    municipalityId: report.municipalityId,
    municipalityName,
    provinceId: safeText(report.provinceId, safeText(municipality?.provinceId, normalizedKey(provinceName))),
    provinceName,
    localityId: safeText(report.localityId, normalizedKey(localityName)),
    localityName,
  };
}
function matchesScope(report, scope = scopeParts()) {
  if (scope.type === 'all') return true;
  const territory = territoryFor(report);
  if (scope.type === 'municipality') return territory.municipalityId === scope.municipalityId;
  if (scope.type === 'province') return territory.provinceId === scope.provinceId;
  if (scope.type === 'locality') return territory.municipalityId === scope.municipalityId && territory.localityId === scope.localityId;
  return true;
}
function geographicReports() { return state.reports.filter((report) => matchesScope(report)); }
function scopeName(value = state.scope) {
  const scope = scopeParts(value);
  if (scope.type === 'all') return 'Todos los reportes';
  if (scope.type === 'municipality') return municipalityChoices().find((item) => item.id === scope.municipalityId)?.name || scope.municipalityId;
  if (scope.type === 'province') return territoryOptions().provinces.find((item) => item.id === scope.provinceId)?.name || 'Provincia';
  if (scope.type === 'locality') return territoryOptions().localities.find((item) => item.municipalityId === scope.municipalityId && item.id === scope.localityId)?.label || 'Localidad';
  return 'Ámbito territorial';
}

function toast(message, kind = 'default') {
  const node = element('div', { className: `toast ${kind === 'error' ? 'error' : kind === 'success' ? 'success' : ''}`, text: message });
  elements.toastRegion.append(node);
  window.setTimeout(() => node.remove(), 5200);
}

function setLoginMessage(message = '') { elements.loginMessage.textContent = message; }
function setLoginBusy(busy) {
  const controls = elements.loginForm.querySelectorAll('button, input');
  controls.forEach((control) => { control.disabled = busy; });
}

function showOnly(screen) {
  elements.appLoading.hidden = true;
  elements.authScreen.hidden = screen !== 'auth';
  elements.accessDenied.hidden = screen !== 'denied';
  elements.adminShell.hidden = screen !== 'admin';
}

function firebaseErrorMessage(error) {
  const code = String(error?.code || '').toLowerCase();
  if (code.includes('invalid-credential') || code.includes('wrong-password') || code.includes('user-not-found')) return 'Correo o contraseña incorrectos.';
  if (code.includes('popup-closed')) return 'El inicio con Google fue cancelado.';
  if (code.includes('permission-denied')) return 'No tenés permisos para realizar esa acción.';
  if (code.includes('unavailable') || code.includes('network')) return 'No hay conexión con el servicio. Intentá nuevamente.';
  if (code.includes('failed-precondition')) return 'La operación no se puede realizar en el estado actual del reporte.';
  return safeText(error?.message, 'No se pudo completar la operación. Intentá nuevamente.');
}

async function resolveProfile(user) {
  const profileRef = doc(db, 'users', user.uid);
  let snap = await getDoc(profileRef);
  if (!snap.exists() && user.email?.toLowerCase() === OWNER_EMAIL) {
    await setDoc(profileRef, {
      displayName: safeText(user.displayName, 'Administración ConDi'),
      realName: safeText(user.displayName),
      email: user.email,
      photoURL: user.photoURL || null,
      role: 'admin',
      municipalityId: '',
      municipalityName: '',
      teamId: null,
      fcmToken: null,
      reportsCount: 0,
      disabled: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    snap = await getDoc(profileRef);
  }
  return snap.exists() ? snap.data() : null;
}

function cleanUpSubscriptions() {
  [state.unsubReports, state.unsubTeams, state.unsubAds, state.unsubMunicipalities].forEach((unsubscribe) => {
    if (typeof unsubscribe === 'function') unsubscribe();
  });
  state.unsubReports = null;
  state.unsubTeams = null;
  state.unsubAds = null;
  state.unsubMunicipalities = null;
}

function setupUserHeader() {
  const name = safeText(state.profile?.realName, safeText(state.profile?.displayName, state.user?.email || 'Gestión'));
  const initial = name.charAt(0).toUpperCase() || 'G';
  elements.profileInitial.textContent = initial;
  elements.profileName.textContent = name;
  elements.profileRole.textContent = roleLabel(state.profile?.role);
  elements.profileEmail.textContent = state.user?.email || '';
}

function municipalityChoices() {
  const source = state.municipalities.map((item) => ({ ...item }));
  const knownIds = new Set(source.map((item) => item.id));
  state.reports.forEach((report) => {
    const id = safeText(report.municipalityId);
    if (id && !knownIds.has(id)) {
      knownIds.add(id);
      const territory = territoryFor(report);
      source.push({ id, name: territory.municipalityName || id, province: territory.provinceName, provinceId: territory.provinceId });
    }
  });
  if (state.profile?.municipalityId && !knownIds.has(state.profile.municipalityId)) {
    source.push({ id: state.profile.municipalityId, name: state.profile.municipalityName || state.profile.municipalityId, province: state.profile.province || '', provinceId: state.profile.provinceId || '' });
  }
  return source.sort((a, b) => a.name.localeCompare(b.name, 'es'));
}

function territoryOptions() {
  const provinces = new Map();
  municipalityChoices().forEach((municipality) => {
    const name = safeText(municipality.province);
    const id = safeText(municipality.provinceId, normalizedKey(name));
    if (id && name) provinces.set(id, { id, name });
  });
  const localities = new Map();
  state.reports.forEach((report) => {
    const territory = territoryFor(report);
    if (territory.provinceId && territory.provinceName) provinces.set(territory.provinceId, { id: territory.provinceId, name: territory.provinceName });
    if (territory.localityId && territory.localityName) {
      const key = `${territory.municipalityId}|${territory.localityId}`;
      localities.set(key, {
        id: territory.localityId,
        municipalityId: territory.municipalityId,
        name: territory.localityName,
        label: `${territory.localityName} · ${territory.municipalityName}`,
      });
    }
  });
  return {
    provinces: [...provinces.values()].sort((a, b) => a.name.localeCompare(b.name, 'es')),
    localities: [...localities.values()].sort((a, b) => a.label.localeCompare(b.label, 'es')),
  };
}

function renderMunicipalityPicker() {
  const isAdmin = state.profile?.role === 'admin';
  elements.municipalityWrap.hidden = !isAdmin;
  if (!isAdmin) return;
  const previous = state.scope;
  elements.municipalitySelect.replaceChildren();
  elements.municipalitySelect.append(element('option', { value: 'all', text: 'Todos los reportes' }));
  const options = territoryOptions();
  if (options.provinces.length) {
    const group = element('optgroup', { label: 'Provincias' });
    options.provinces.forEach((province) => group.append(element('option', { value: `province|${province.id}`, text: `Provincia · ${province.name}` })));
    elements.municipalitySelect.append(group);
  }
  const municipalities = municipalityChoices();
  if (municipalities.length) {
    const group = element('optgroup', { label: 'Municipios' });
    municipalities.forEach((municipality) => group.append(element('option', { value: `municipality|${municipality.id}`, text: `Municipio · ${municipality.name}` })));
    elements.municipalitySelect.append(group);
  }
  if (options.localities.length) {
    const group = element('optgroup', { label: 'Localidades' });
    options.localities.forEach((locality) => group.append(element('option', { value: `locality|${locality.municipalityId}|${locality.id}`, text: `Localidad · ${locality.label}` })));
    elements.municipalitySelect.append(group);
  }
  const values = Array.from(elements.municipalitySelect.options).map((option) => option.value);
  state.scope = values.includes(previous) ? previous : 'all';
  elements.municipalitySelect.value = state.scope;
}

function subscribeMunicipalities() {
  state.unsubMunicipalities = onSnapshot(collection(db, 'municipalities'), (snapshot) => {
    state.municipalities = snapshot.docs.map((item) => {
      const data = item.data();
      const province = safeText(data.province);
      return {
        id: item.id,
        name: safeText(data.name, safeText(data.displayName, item.id)),
        province,
        provinceId: safeText(data.provinceId, normalizedKey(province)),
        mapCenter: data.mapCenter ?? data.center ?? data.location ??
          (Array.isArray(data.coordinates)
            ? { lat: data.coordinates[1], lng: data.coordinates[0] }
            : data.coordinates) ?? {
          lat: data.lat ?? data.latitude,
          lng: data.lng ?? data.longitude,
        },
        mapBounds: data.mapBounds ?? data.bounds ?? data.boundingBox,
        mapZoom: data.mapZoom ?? data.zoom,
      };
    });
    renderMunicipalityPicker();
    renderAll();
  }, () => {
    state.municipalities = [];
    renderMunicipalityPicker();
  });
}

function reportsQuery() {
  const constraints = [where('hidden', '==', false)];
  if (state.profile?.role !== 'admin') constraints.push(where('municipalityId', '==', state.profile?.municipalityId || ''));
  constraints.push(orderBy('createdAt', 'desc'), limit(2000));
  return query(collection(db, 'reports'), ...constraints);
}

function teamsQuery() {
  if (state.profile?.role === 'admin') return query(collection(db, 'teams'));
  return query(collection(db, 'teams'), where('municipalityId', '==', state.profile?.municipalityId || ''), where('active', '==', true));
}

function subscribeAds() {
  if (state.unsubAds) state.unsubAds();
  if (state.profile?.role !== 'admin') {
    state.ads = [];
    renderAds();
    return;
  }
  state.unsubAds = onSnapshot(collection(db, 'localAds'), (snapshot) => {
    state.ads = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
    renderAds();
  }, (error) => {
    state.ads = [];
    renderAds();
    toast(`No se pudo leer la publicidad: ${firebaseErrorMessage(error)}`, 'error');
  });
}

function subscribeOperationalData() {
  if (state.unsubReports) state.unsubReports();
  if (state.unsubTeams) state.unsubTeams();
  state.mapHasFitted = false;

  state.unsubReports = onSnapshot(reportsQuery(), (snapshot) => {
    state.reports = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
    renderMunicipalityPicker();
    renderAll();
    if (state.selectedReportId) renderDrawer();
  }, (error) => {
    state.reports = [];
    renderAll();
    toast(`No se pudieron leer los reportes: ${firebaseErrorMessage(error)}`, 'error');
  });

  state.unsubTeams = onSnapshot(teamsQuery(), (snapshot) => {
    state.teams = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
    renderTeams();
    if (state.selectedReportId) renderDrawer();
  }, (error) => {
    state.teams = [];
    renderTeams();
    toast(`No se pudieron leer las cuadrillas: ${firebaseErrorMessage(error)}`, 'error');
  });
}

function filteredReports() {
  const needle = state.search.trim().toLocaleLowerCase('es');
  return geographicReports().filter((report) => {
    if (state.status !== 'all' && report.status !== state.status) return false;
    if (state.priority === 'high' && !isHigh(report)) return false;
    if (state.priority === 'unassigned' && safeText(report.assignedTeamId)) return false;
    if (!needle) return true;
    const haystack = [reportName(report), categoryLabel(report.category), reportLocation(report), report.description]
      .filter(Boolean).join(' ').toLocaleLowerCase('es');
    return haystack.includes(needle);
  });
}

function priorityScore(report) {
  const age = Math.min(6, Math.floor(Math.max(0, Date.now() - (dateFrom(report.createdAt)?.getTime() || Date.now())) / 86400000));
  return (number(report.priority, 1) * 10) + Math.min(10, number(report.supportCount, 0)) + age + (report.status === 'pending' ? 5 : 0);
}

function operationalSummary(reports = geographicReports()) {
  const open = reports.filter(isOpen);
  const unassigned = open.filter((report) => !safeText(report.assignedTeamId));
  const field = reports.filter((report) => ['assigned', 'in_progress'].includes(report.status));
  const oneWeekAgo = Date.now() - (7 * 86400000);
  const resolvedWeek = reports.filter((report) => ['resolved', 'closed'].includes(report.status) && (dateFrom(report.resolvedAt || report.workFinishedAt)?.getTime() || 0) >= oneWeekAgo);
  const resolutionHours = reports
    .filter((report) => ['resolved', 'closed'].includes(report.status))
    .map((report) => hoursBetween(report.createdAt, report.resolvedAt || report.workFinishedAt))
    .filter((value) => value != null);
  const averageResolution = resolutionHours.length ? resolutionHours.reduce((sum, value) => sum + value, 0) / resolutionHours.length : null;
  const older72 = open.filter((report) => (Date.now() - (dateFrom(report.createdAt)?.getTime() || Date.now())) >= 72 * 3600000);
  return { open, unassigned, field, resolvedWeek, averageResolution, older72 };
}

function categoryTotals(reports = geographicReports()) {
  const totals = new Map();
  reports.forEach((report) => {
    const key = safeText(report.category, 'other');
    totals.set(key, (totals.get(key) || 0) + 1);
  });
  return [...totals.entries()].sort((a, b) => b[1] - a[1] || categoryLabel(a[0]).localeCompare(categoryLabel(b[0]), 'es'));
}

function hotspotGroups(reports = geographicReports()) {
  const groups = new Map();
  reports.forEach((report) => {
    const point = geographicPoint(report);
    if (!point) return;
    const [lat, lng] = point;
    const key = `${Math.floor(lat / .008)}:${Math.floor(lng / .008)}`;
    const group = groups.get(key) || { key, reports: [], lat: 0, lng: 0 };
    group.reports.push(report);
    group.lat += lat;
    group.lng += lng;
    groups.set(key, group);
  });
  return [...groups.values()].map((group) => {
    const count = group.reports.length;
    const active = group.reports.filter(isOpen).length;
    const high = group.reports.filter(isHigh).length;
    const support = group.reports.reduce((sum, report) => sum + number(report.supportCount, 0), 0);
    return {
      ...group,
      lat: group.lat / count,
      lng: group.lng / count,
      count,
      active,
      high,
      support,
      score: active * 5 + high * 4 + support + count,
    };
  }).sort((a, b) => b.score - a.score || b.count - a.count);
}

function resetContainer(container, children) { container.replaceChildren(...children); }

function statusPill(status) { return element('span', { className: `status-pill status-${status}`, text: statusLabel(status) }); }
function priorityPill(report) {
  return element('span', { className: `priority-pill ${isHigh(report) ? 'priority-high' : 'priority-normal'}`, text: `P${number(report.priority, 1)}` });
}

function renderOverview() {
  const scopedReports = geographicReports();
  const summary = operationalSummary(scopedReports);
  const scope = scopeName(state.scope);
  elements.overviewHeading.textContent = `${scope}: dónde actuar primero.`;
  elements.overviewSubtitle.textContent = `${scopedReports.length} reportes cargados en este ámbito. La vista se actualiza con novedades de vecinos y cuadrillas.`;
  elements.metricOpen.textContent = summary.open.length;
  elements.metricOpenDetail.textContent = summary.older72.length ? `${summary.older72.length} con más de 72 h` : 'Sin casos vencidos';
  elements.metricUnassigned.textContent = summary.unassigned.length;
  elements.metricField.textContent = summary.field.length;
  elements.metricResolved.textContent = summary.resolvedWeek.length;
  elements.metricResolvedDetail.textContent = summary.resolvedWeek.length ? 'Cierres de la última semana' : 'Sin cierres registrados';
  elements.metricResolution.textContent = summary.averageResolution == null ? '—' : summary.averageResolution < 48 ? `${Math.round(summary.averageResolution)} h` : `${(summary.averageResolution / 24).toFixed(1)} d`;
  elements.navOpenCount.textContent = String(summary.open.length);

  const queue = summary.open.slice().sort((a, b) => priorityScore(b) - priorityScore(a)).slice(0, 6);
  const priorityNodes = queue.length ? queue.map((report) => {
    const line = element('div', { className: `priority-indicator ${isHigh(report) ? 'high' : 'medium'}` });
    const copy = element('div');
    copy.append(element('b', { text: reportName(report) }), element('small', { text: `${categoryLabel(report.category)} · ${relativeAge(report.createdAt)} · ${reportLocation(report)}` }));
    const open = element('button', { className: 'priority-action', type: 'button', text: 'Gestionar', onClick: () => openReport(report.id) });
    const item = element('div', { className: 'priority-item' });
    item.append(line, copy, open);
    return item;
  }) : [emptyInline('No hay reportes abiertos para priorizar.')];
  resetContainer(elements.priorityList, priorityNodes);

  const categories = categoryTotals(scopedReports);
  elements.categoryTotal.textContent = `${scopedReports.length} reportes`;
  const categoryNodes = categories.slice(0, 6).map(([category, count]) => {
    const row = element('div', { className: 'category-row' });
    const track = element('div', { className: 'category-track' });
    const fill = element('div', { className: 'category-fill' });
    fill.style.width = `${scopedReports.length ? Math.max(7, (count / scopedReports.length) * 100) : 0}%`;
    track.append(fill);
    row.append(element('span', { text: categoryLabel(category) }), track, element('b', { text: count }));
    return row;
  });
  resetContainer(elements.categoryBars, categoryNodes.length ? categoryNodes : [emptyInline('Todavía no hay datos por categoría.')]);

  const hotspots = hotspotGroups(scopedReports).slice(0, 5);
  const hotspotNodes = hotspotNodesFor(hotspots, 'overview');
  resetContainer(elements.hotspotList, hotspotNodes.length ? hotspotNodes : [emptyInline('No hay reportes geolocalizados en este ámbito.')]);

  const risks = [];
  if (summary.unassigned.length) risks.push(`${summary.unassigned.length} reporte${summary.unassigned.length === 1 ? '' : 's'} abierto${summary.unassigned.length === 1 ? '' : 's'} aún no tiene${summary.unassigned.length === 1 ? '' : 'n'} cuadrilla asignada.`);
  if (summary.older72.length) risks.push(`${summary.older72.length} caso${summary.older72.length === 1 ? '' : 's'} abierto${summary.older72.length === 1 ? '' : 's'} supera${summary.older72.length === 1 ? '' : 'n'} las 72 horas.`);
  const highOpen = summary.open.filter(isHigh).length;
  if (highOpen) risks.push(`${highOpen} reporte${highOpen === 1 ? '' : 's'} de alta prioridad requiere${highOpen === 1 ? '' : 'n'} seguimiento directo.`);
  if (!risks.length) risks.push('La cola actual no presenta alertas críticas. Revisá el mapa para anticipar concentraciones.');
  resetContainer(elements.riskList, risks.map((risk) => {
    const item = element('div', { className: 'action-item' });
    item.append(element('span', { className: 'action-icon', text: '!' }), element('span', { text: risk }));
    return item;
  }));
}

function emptyInline(text) { return element('p', { className: 'muted', text }); }

function hotspotNodesFor(groups, origin) {
  return groups.map((group, index) => {
    const copy = element('div');
    const label = `Zona de concentración ${index + 1}`;
    copy.append(element('b', { text: label }), element('small', { text: `${group.active} abierto${group.active === 1 ? '' : 's'} · ${group.high} prioritario${group.high === 1 ? '' : 's'}` }));
    const button = element('button', { type: 'button', text: origin === 'map' ? 'Ver reportes' : 'Mapa', onClick: () => focusHotspot(group) });
    const item = element('div', { className: 'hotspot-item' });
    item.append(element('span', { className: 'hotspot-rank', text: String(index + 1) }), copy, button);
    return item;
  });
}

function renderReports() {
  const reports = filteredReports();
  elements.reportCount.textContent = `${reports.length} de ${geographicReports().length} reportes en este ámbito`;
  elements.reportsBody.replaceChildren();
  reports.slice(0, 250).forEach((report) => {
    const tr = element('tr');
    const name = element('div', { className: 'report-name' });
    name.append(element('b', { text: reportName(report) }), element('small', { text: `${categoryLabel(report.category)} · ${reportLocation(report)}` }));
    const team = state.teams.find((item) => item.id === report.assignedTeamId);
    const action = element('button', { className: 'row-action', type: 'button', text: 'Gestionar', onClick: () => openReport(report.id) });
    [name, statusPill(report.status), priorityPill(report), element('span', { text: team?.name || 'Sin asignar' }), element('span', { text: formatDate(report.createdAt) }), action]
      .forEach((content) => { const td = element('td'); td.append(content); tr.append(td); });
    elements.reportsBody.append(tr);
  });
  elements.reportsEmpty.hidden = reports.length > 0;
}

function ensureMap() {
  if (state.map || !window.L) return;
  state.map = window.L.map('operations-map', { zoomControl: false, preferCanvas: true }).setView([-34.6037, -58.3816], 11);
  window.L.control.zoom({ position: 'bottomright' }).addTo(state.map);
  window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '© OpenStreetMap contributors',
  }).addTo(state.map);
  state.mapLayer = window.L.layerGroup().addTo(state.map);
}

function renderMap() {
  ensureMap();
  if (!state.map || !state.mapLayer) {
    elements.mapSummary.textContent = 'El mapa no está disponible en este navegador.';
    return;
  }
  state.mapLayer.clearLayers();
  // El mapa nunca hereda los filtros de la tabla: muestra todos los reportes
  // del ámbito territorial elegido, incluidos los ya resueltos.
  const territoryReports = geographicReports();
  const reports = territoryReports.filter(geographicPoint);
  const groups = hotspotGroups(reports);
  elements.mapSummary.textContent = `${reports.length} de ${territoryReports.length} reportes del ámbito tienen ubicación.`;
  resetContainer(elements.mapHotspots, hotspotNodesFor(groups.slice(0, 7), 'map').length ? hotspotNodesFor(groups.slice(0, 7), 'map') : [emptyInline('No hay ubicaciones para mostrar.')]);
  groups.forEach((group) => {
    const icon = window.L.divIcon({
      className: '',
      html: `<span class="${group.count === 1 ? `report-marker ${group.high ? 'high' : ''}` : 'cluster-label'}">${group.count === 1 ? number(group.reports[0].priority, 1) : group.count}</span>`,
      iconSize: [35, 35], iconAnchor: [17, 17],
    });
    const marker = window.L.marker([group.lat, group.lng], { icon, keyboard: true });
    const popup = document.createElement('div');
    popup.style.minWidth = '170px';
    popup.append(element('b', { text: group.count === 1 ? reportName(group.reports[0]) : `${group.count} reportes cercanos` }));
    popup.append(document.createElement('br'));
    popup.append(element('small', { text: `${group.active} abiertos · ${group.high} de alta prioridad` }));
    const button = element('button', { type: 'button', text: group.count === 1 ? 'Gestionar reporte' : 'Abrir primer reporte', onClick: () => openReport(group.reports[0].id) });
    button.style.cssText = 'margin-top:8px;border:0;color:#1767d7;background:transparent;padding:0;font-weight:700;cursor:pointer;';
    popup.append(document.createElement('br'), button);
    marker.bindPopup(popup);
    marker.addTo(state.mapLayer);
  });
  if (!state.mapHasFitted || state.mapScopeKey !== state.scope) {
    focusMapOnScope(territoryReports);
    state.mapHasFitted = true;
    state.mapScopeKey = state.scope;
  }
  window.setTimeout(() => state.map.invalidateSize(), 50);
}

function focusHotspot(group) {
  showView('map');
  window.setTimeout(() => {
    ensureMap();
    if (state.map) {
      state.map.setView([group.lat, group.lng], 15, { animate: true });
      state.map.invalidateSize();
    }
  }, 80);
}

function teamMatchesScope(team, scope = scopeParts()) {
  if (scope.type === 'all') return true;
  if (scope.type === 'municipality' || scope.type === 'locality') return team.municipalityId === scope.municipalityId;
  if (scope.type === 'province') {
    return municipalityChoices().some((municipality) => municipality.id === team.municipalityId && municipality.provinceId === scope.provinceId);
  }
  return true;
}

function teamMunicipalityChoices(team = null) {
  const choices = municipalityChoices().slice();
  if (team?.municipalityId && !choices.some((item) => item.id === team.municipalityId)) {
    choices.push({ id: team.municipalityId, name: safeText(team.municipalityName, team.municipalityId) });
  }
  return choices.sort((a, b) => a.name.localeCompare(b.name, 'es'));
}

function preferredTeamMunicipalityId() {
  const scope = scopeParts();
  if (scope.type === 'municipality' || scope.type === 'locality') return scope.municipalityId;
  if (state.profile?.role !== 'admin') return safeText(state.profile?.municipalityId);
  const choices = teamMunicipalityChoices();
  return choices.length === 1 ? choices[0].id : '';
}

function renderTeamMunicipalityOptions(selectedId, team = null) {
  const choices = teamMunicipalityChoices(team);
  const isAdmin = state.profile?.role === 'admin';
  elements.teamMunicipality.replaceChildren();
  if (isAdmin) elements.teamMunicipality.append(element('option', { value: '', text: 'Seleccionar municipio' }));
  choices.forEach((municipality) => elements.teamMunicipality.append(element('option', { value: municipality.id, text: municipality.name })));
  const fallback = isAdmin ? '' : safeText(state.profile?.municipalityId);
  elements.teamMunicipality.value = choices.some((item) => item.id === selectedId) ? selectedId : fallback;
  elements.teamMunicipality.disabled = !isAdmin;
}

function closeTeamEditor() {
  state.editingTeamId = null;
  elements.teamForm.reset();
  elements.teamEditor.hidden = true;
}

function openTeamEditor(team = null) {
  state.editingTeamId = team?.id || null;
  elements.teamForm.reset();
  elements.teamId.value = team?.id || '';
  elements.teamName.value = safeText(team?.name);
  elements.teamZone.value = safeText(team?.zoneName);
  elements.teamZoneManager.value = safeText(team?.zoneManagerName);
  elements.teamMaintenanceChief.value = safeText(team?.maintenanceChiefName);
  elements.teamMembers.value = Array.isArray(team?.memberNames) ? team.memberNames.join('\n') : '';
  elements.teamActive.checked = team?.active !== false;
  const selectedId = team?.municipalityId || preferredTeamMunicipalityId();
  renderTeamMunicipalityOptions(selectedId, team);
  const categories = new Set(Array.isArray(team?.categories) ? team.categories : []);
  Array.from(elements.teamCategories.options).forEach((option) => { option.selected = categories.has(option.value); });
  elements.teamEditorKicker.textContent = team ? 'EDITAR CUADRILLA' : 'NUEVA CUADRILLA';
  elements.teamEditorTitle.textContent = team ? safeText(team.name, 'Editar cuadrilla') : 'Alta operativa';
  elements.saveTeam.textContent = team ? 'Guardar cambios' : 'Guardar cuadrilla';
  elements.teamEditor.hidden = false;
  window.requestAnimationFrame(() => elements.teamName.focus());
}

function teamMembersFromInput(value) {
  return [...new Set(safeText(value).split(/[\n,;]+/).map((name) => name.trim()).filter(Boolean))].slice(0, 30);
}

async function submitTeamForm(event) {
  event.preventDefault();
  if (!elements.teamForm.reportValidity()) return;
  const municipalityId = elements.teamMunicipality.value;
  const editingTeam = state.teams.find((team) => team.id === state.editingTeamId) || null;
  const municipality = teamMunicipalityChoices(editingTeam).find((item) => item.id === municipalityId);
  if (!municipalityId || !municipality) {
    toast('Elegí el municipio de la cuadrilla.', 'error');
    return;
  }
  const payload = {
    name: elements.teamName.value.trim(),
    municipalityId,
    municipalityName: municipality.name,
    zoneName: elements.teamZone.value.trim(),
    zoneManagerName: elements.teamZoneManager.value.trim(),
    maintenanceChiefName: elements.teamMaintenanceChief.value.trim(),
    categories: Array.from(elements.teamCategories.selectedOptions).map((option) => option.value),
    memberNames: teamMembersFromInput(elements.teamMembers.value),
    active: elements.teamActive.checked,
  };
  if (state.editingTeamId) payload.teamId = state.editingTeamId;
  await withButton(elements.saveTeam, async () => {
    const response = await saveTeam(payload);
    const created = response.data?.created === true;
    closeTeamEditor();
    toast(created ? 'Cuadrilla registrada.' : 'Cuadrilla actualizada.', 'success');
  });
}

function renderTeams() {
  const teams = state.teams
    .filter((team) => teamMatchesScope(team))
    .slice()
    .sort((a, b) => safeText(a.name, a.id).localeCompare(safeText(b.name, b.id), 'es'));
  const activeTeams = teams.filter((team) => team.active !== false);
  elements.teamsSummary.textContent = `${activeTeams.length} activas · ${teams.length} registradas`;
  elements.teamsGrid.replaceChildren();
  teams.forEach((team) => {
    const workload = state.reports.filter((report) => report.assignedTeamId === team.id && isOpen(report)).length;
    const card = element('article', { className: 'team-card' });
    const head = element('div', { className: 'team-card-head' });
    const stateBadge = element('span', { className: `team-state${team.active === false ? ' inactive' : ''}`, text: team.active === false ? 'Inactiva' : 'Activa' });
    const edit = element('button', { className: 'row-action', type: 'button', text: 'Editar', onClick: () => openTeamEditor(team) });
    const headActions = element('div', { className: 'team-card-actions' });
    headActions.append(stateBadge, edit);
    head.append(element('span', { className: 'team-icon', text: '♟' }), headActions);
    const categories = Array.isArray(team.categories) && team.categories.length ? team.categories.map(categoryLabel).join(' · ') : 'Cobertura general';
    const details = element('div', { className: 'team-details' });
    const detailRows = [
      ['Zona', safeText(team.zoneName, 'Cobertura municipal')],
      ['Encargado/a', safeText(team.zoneManagerName, 'Sin asignar')],
      ['Mantenimiento', safeText(team.maintenanceChiefName, 'Sin asignar')],
    ];
    if (Array.isArray(team.memberNames) && team.memberNames.length) detailRows.push(['Integrantes', team.memberNames.join(' · ')]);
    detailRows.forEach(([label, value]) => {
      const row = element('div');
      row.append(element('span', { text: label }), element('b', { text: value }));
      details.append(row);
    });
    const load = element('div', { className: 'team-load' });
    load.append(element('b', { text: workload }), element('span', { text: workload === 1 ? 'caso abierto asignado' : 'casos abiertos asignados' }));
    card.append(head, element('h3', { text: safeText(team.name, team.id) }), element('p', { text: categories }), details, load);
    elements.teamsGrid.append(card);
  });
  elements.teamsEmpty.hidden = teams.length > 0;
}

function adMatchesScope(ad, scope = scopeParts()) {
  if (scope.type === 'all') return true;
  if (scope.type === 'municipality' || scope.type === 'locality') {
    return ad.municipalityId === scope.municipalityId;
  }
  if (scope.type === 'province') {
    return municipalityChoices().some((municipality) =>
      municipality.id === ad.municipalityId && municipality.provinceId === scope.provinceId);
  }
  return true;
}

function adIsLive(ad, now = Date.now()) {
  const start = dateFrom(ad.startsAt)?.getTime();
  const end = dateFrom(ad.endsAt)?.getTime();
  return ad.active !== false && Number.isFinite(start) && Number.isFinite(end) && start <= now && now < end;
}

function adDismissModeLabel(value) {
  return value === 'wait_7_seconds' ? 'Cierre luego de 7 s' : 'Cierre inmediato';
}

function dateInputValue(value) {
  const date = dateFrom(value) || new Date();
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

function adMunicipalityChoices(ad = null) {
  const choices = municipalityChoices().slice();
  if (ad?.municipalityId && !choices.some((item) => item.id === ad.municipalityId)) {
    choices.push({ id: ad.municipalityId, name: safeText(ad.municipalityName, ad.municipalityId) });
  }
  return choices.sort((a, b) => a.name.localeCompare(b.name, 'es'));
}

function preferredAdMunicipalityId() {
  const scope = scopeParts();
  if (scope.type === 'municipality' || scope.type === 'locality') return scope.municipalityId;
  const choices = adMunicipalityChoices();
  return choices.length === 1 ? choices[0].id : '';
}

function renderAdMunicipalityOptions(selectedId, ad = null) {
  const choices = adMunicipalityChoices(ad);
  elements.adMunicipality.replaceChildren(element('option', { value: '', text: 'Seleccionar municipio' }));
  choices.forEach((municipality) => {
    elements.adMunicipality.append(element('option', { value: municipality.id, text: municipality.name }));
  });
  elements.adMunicipality.value = choices.some((item) => item.id === selectedId) ? selectedId : '';
}

function closeAdEditor() {
  state.editingAdId = null;
  elements.adForm.reset();
  elements.adEditor.hidden = true;
}

function openAdEditor(ad = null) {
  if (state.profile?.role !== 'admin') return;
  state.editingAdId = ad?.id || null;
  elements.adForm.reset();
  elements.adId.value = ad?.id || '';
  elements.adBusiness.value = safeText(ad?.business);
  elements.adMessage.value = safeText(ad?.message);
  elements.adLink.value = safeText(ad?.link);
  elements.adImageUrl.value = safeText(ad?.imageUrl);
  elements.adDismissMode.value = safeText(ad?.dismissMode, 'close_now');
  elements.adStartDate.value = dateInputValue(ad?.startsAt);
  elements.adEndDate.value = dateInputValue(ad?.endsAt || new Date(Date.now() + 30 * 86400000));
  elements.adActive.checked = ad?.active !== false;
  renderAdMunicipalityOptions(ad?.municipalityId || preferredAdMunicipalityId(), ad);
  elements.adEditorKicker.textContent = ad ? 'EDITAR BANNER' : 'NUEVO BANNER';
  elements.adEditorTitle.textContent = ad ? safeText(ad.business, 'Editar banner') : 'Pauta comercial';
  elements.saveAd.textContent = ad ? 'Guardar cambios' : 'Guardar banner';
  elements.adEditor.hidden = false;
  window.requestAnimationFrame(() => elements.adBusiness.focus());
}

function mimeForAdImage(file) {
  const declared = safeText(file?.type).toLowerCase();
  if (['image/jpeg', 'image/png', 'image/webp'].includes(declared)) return declared;
  const name = safeText(file?.name).toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return '';
}

async function uploadAdImage(file, municipalityId) {
  if (!file) return '';
  if (file.size > 5 * 1024 * 1024) throw new Error('La imagen supera 5 MB.');
  const contentType = mimeForAdImage(file);
  if (!contentType) throw new Error('Usá una imagen JPG, PNG o WebP.');
  const dataUrl = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('No se pudo leer la imagen.'));
    reader.onload = () => resolve(String(reader.result || ''));
    reader.readAsDataURL(file);
  });
  const imageBase64 = String(dataUrl).split(',', 2)[1] || '';
  const result = await uploadLocalAdImage({ municipalityId, contentType, imageBase64 });
  const imageUrl = safeText(result?.data?.imageUrl);
  if (!imageUrl) throw new Error('No se pudo guardar la imagen publicitaria.');
  return imageUrl;
}

async function submitAdForm(event) {
  event.preventDefault();
  if (state.profile?.role !== 'admin' || !elements.adForm.reportValidity()) return;
  const municipalityId = elements.adMunicipality.value;
  const ad = state.ads.find((item) => item.id === state.editingAdId) || null;
  const municipality = adMunicipalityChoices(ad).find((item) => item.id === municipalityId);
  if (!municipalityId || !municipality) {
    toast('Elegí el municipio del banner.', 'error');
    return;
  }
  const startsAt = new Date(`${elements.adStartDate.value}T00:00:00`).getTime();
  const endsAt = new Date(`${elements.adEndDate.value}T00:00:00`).getTime();
  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) || endsAt <= startsAt) {
    toast('La fecha de fin debe ser posterior al inicio.', 'error');
    return;
  }
  await withButton(elements.saveAd, async () => {
    const imageFile = elements.adImageFile.files?.[0];
    const imageUrl = imageFile
      ? await uploadAdImage(imageFile, municipalityId)
      : elements.adImageUrl.value.trim();
    await saveLocalAd({
      ...(state.editingAdId ? { adId: state.editingAdId } : {}),
      municipalityId,
      municipalityName: municipality.name,
      business: elements.adBusiness.value.trim(),
      message: elements.adMessage.value.trim(),
      link: elements.adLink.value.trim(),
      imageUrl,
      startsAt,
      endsAt,
      dismissMode: elements.adDismissMode.value,
      active: elements.adActive.checked,
    });
    closeAdEditor();
    toast(ad ? 'Banner actualizado.' : 'Banner registrado.', 'success');
  });
}

function renderAds() {
  const canManageAds = state.profile?.role === 'admin';
  elements.adsNav.hidden = !canManageAds;
  if (!canManageAds) return;
  const ads = state.ads
    .filter((ad) => adMatchesScope(ad))
    .slice()
    .sort((a, b) => (dateFrom(b.updatedAt)?.getTime() || 0) - (dateFrom(a.updatedAt)?.getTime() || 0));
  const live = ads.filter((ad) => adIsLive(ad)).length;
  elements.adsSummary.textContent = `${live} activas · ${ads.length} registradas`;
  elements.adsGrid.replaceChildren();
  ads.forEach((ad) => {
    const card = element('article', { className: 'ad-card' });
    const image = safeText(ad.imageUrl);
    if (image) {
      card.append(element('img', { className: 'ad-card-image', src: image, alt: `Imagen de ${safeText(ad.business, 'anuncio')}` }));
    } else {
      card.append(element('div', { className: 'ad-card-placeholder', text: '▤' }));
    }
    const body = element('div', { className: 'ad-card-body' });
    const head = element('div', { className: 'ad-card-head' });
    const stateBadge = element('span', { className: `team-state${adIsLive(ad) ? '' : ' inactive'}`, text: adIsLive(ad) ? 'En circulación' : ad.active === false ? 'Pausado' : 'Fuera de vigencia' });
    const edit = element('button', { className: 'row-action', type: 'button', text: 'Editar', onClick: () => openAdEditor(ad) });
    head.append(stateBadge, edit);
    const details = element('p', { className: 'ad-card-details', text: `${formatDate(ad.startsAt)} — ${formatDate(ad.endsAt)} · ${adDismissModeLabel(ad.dismissMode)}` });
    body.append(head, element('h3', { text: safeText(ad.business, 'Comercio local') }), element('p', { text: safeText(ad.message) }), details);
    card.append(body);
    elements.adsGrid.append(card);
  });
  elements.adsEmpty.hidden = ads.length > 0;
}

function renderAnalysisList(container, items, renderItem) {
  container.replaceChildren();
  if (!items?.length) {
    container.append(emptyInline('No se identificaron elementos para este apartado.'));
    return;
  }
  items.forEach((item) => container.append(renderItem(item)));
}

function renderAiResult(data) {
  elements.aiState.hidden = true;
  elements.aiResults.hidden = false;
  elements.aiSummaryTitle.textContent = `Análisis de ${data.totalReports || 0} reportes · ${data.periodDays || 30} días`;
  elements.aiSummaryText.textContent = safeText(data.summary, 'No fue posible generar una síntesis para este período.');
  renderAnalysisList(elements.aiPriorities, data.priorities, (item) => {
    const node = element('div', { className: 'analysis-item' });
    node.append(element('b', { text: safeText(item.title, 'Prioridad operativa') }), element('p', { text: safeText(item.evidence) }), element('small', { text: `Acción sugerida: ${safeText(item.action)}` }));
    return node;
  });
  renderAnalysisList(elements.aiStrategies, data.strategies, (item) => {
    const node = element('div', { className: 'analysis-item' });
    node.append(element('b', { text: safeText(item.title, 'Estrategia') }), element('p', { text: safeText(item.objective) }), element('small', { text: `${safeText(item.action)} · Recursos: ${safeText(item.resourceImpact)}` }));
    return node;
  });
  renderAnalysisList(elements.aiRisks, data.risks, (item) => element('div', { text: safeText(item) }));
  renderAnalysisList(elements.aiQuestions, data.questions, (item) => element('div', { text: safeText(item) }));
}

function usageScopePayload() {
  const scope = scopeParts();
  const payload = { days: 30 };
  if (scope.type === 'municipality' || scope.type === 'locality') payload.municipalityId = scope.municipalityId;
  if (scope.type === 'province') payload.provinceId = scope.provinceId;
  if (scope.type === 'locality') payload.localityId = scope.localityId;
  return payload;
}

function usageScopeKey() { return JSON.stringify(usageScopePayload()); }

async function loadUsageSummary() {
  if (!state.profile) return;
  const key = usageScopeKey();
  state.usageLoading = true;
  state.usageError = '';
  state.usageScopeKey = key;
  renderUsage();
  try {
    const response = await getUsageSummary(usageScopePayload());
    if (key !== usageScopeKey()) return;
    state.usage = response.data || null;
  } catch (error) {
    if (key !== usageScopeKey()) return;
    state.usage = null;
    state.usageError = firebaseErrorMessage(error);
  } finally {
    if (key === usageScopeKey()) {
      state.usageLoading = false;
      renderUsage();
    }
  }
}

function renderUsage() {
  if (!elements.usageTotal || !state.profile) return;
  const usage = state.usage;
  const loading = state.usageLoading;
  const cities = usage?.cities || [];
  const daily = usage?.daily || [];
  elements.usageTotal.textContent = loading ? '…' : String(number(usage?.totalSessions, 0));
  elements.usageToday.textContent = loading ? '…' : String(number(usage?.activeUsersToday, 0));
  elements.usageCities.textContent = loading ? '…' : String(number(usage?.visibleCities, 0));
  elements.usageNotice.textContent = state.usageError
    ? state.usageError
    : loading
      ? 'Actualizando la medición agregada…'
      : 'Solo se muestran ciudades con al menos tres usuarios activos el mismo día. No se almacenan direcciones IP.';

  const max = Math.max(1, ...daily.map((item) => number(item.activeUsers, 0)));
  const bars = daily.map((item) => {
    const node = element('div', { className: 'usage-bar', title: `${safeText(item.date)} · ${number(item.activeUsers, 0)} usuarios activos` });
    node.style.height = `${Math.max(5, (number(item.activeUsers, 0) / max) * 100)}%`;
    return node;
  });
  resetContainer(elements.usagePeriods, bars.length ? bars : [emptyInline(loading ? 'Cargando evolución…' : 'Todavía no hay actividad con consentimiento.')]);

  const cityNodes = cities.map((city, index) => {
    const copy = element('div');
    copy.append(
      element('b', { text: safeText(city.city, safeText(city.municipalityName, 'Ciudad')) }),
      element('small', { text: `${number(city.sessions, 0)} sesiones · ${number(city.activeDays, 0)} días con uso · ${safeText(city.province)}` }),
    );
    const item = element('div', { className: 'usage-city-item' });
    item.append(element('span', { className: 'hotspot-rank', text: String(index + 1) }), copy, element('b', { className: 'usage-city-total', text: String(number(city.sessions, 0)) }));
    return item;
  });
  if (usage?.suppressedCities) {
    cityNodes.push(element('p', { className: 'usage-suppressed', text: `${number(usage.suppressedCities, 0)} ámbito${number(usage.suppressedCities, 0) === 1 ? '' : 's'} con muestra insuficiente no se muestra.` }));
  }
  resetContainer(elements.usageCityList, cityNodes.length ? cityNodes : [emptyInline(loading ? 'Cargando ciudades…' : 'Aún no hay ciudades que alcancen el mínimo de privacidad.')]);
}

function renderAppRelease() {
  if (!elements.releaseNav || !state.profile) return;
  const isAdmin = state.profile.role === 'admin';
  elements.releaseNav.hidden = !isAdmin;
  if (!isAdmin) return;

  const android = state.appRelease?.android || {};
  const minimumBuild = number(android.minBuild, 14);
  const storeUrl = safeText(android.storeUrl, 'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi');
  const message = safeText(android.message, 'Hay una nueva versión de ConDi con mejoras importantes. Actualizá la app para continuar.');
  if (document.activeElement !== elements.releaseMinAndroidBuild) elements.releaseMinAndroidBuild.value = String(minimumBuild);
  if (document.activeElement !== elements.releaseAndroidStoreUrl) elements.releaseAndroidStoreUrl.value = storeUrl;
  if (document.activeElement !== elements.releaseAndroidMessage) elements.releaseAndroidMessage.value = message;
  elements.releaseStatus.textContent = state.releaseLoading
    ? 'Cargando configuración…'
    : `Se bloquearán compilaciones menores a ${minimumBuild}`;
}

async function loadAppRelease() {
  if (state.profile?.role !== 'admin') return;
  state.releaseLoading = true;
  renderAppRelease();
  try {
    const response = await getAppRelease();
    state.appRelease = response.data || null;
  } catch (error) {
    toast(`No se pudo cargar la actualización: ${firebaseErrorMessage(error)}`, 'error');
  } finally {
    state.releaseLoading = false;
    renderAppRelease();
  }
}

async function submitAppRelease(event) {
  event.preventDefault();
  if (state.profile?.role !== 'admin') return;
  const minAndroidBuild = Number(elements.releaseMinAndroidBuild.value);
  const androidStoreUrl = elements.releaseAndroidStoreUrl.value.trim();
  const androidMessage = elements.releaseAndroidMessage.value.trim();
  if (!Number.isSafeInteger(minAndroidBuild) || minAndroidBuild < 1 || !androidStoreUrl || !androidMessage) {
    toast('Completá una compilación mínima, el enlace oficial de Google Play y el mensaje.', 'error');
    return;
  }
  elements.saveRelease.disabled = true;
  try {
    const response = await saveAppRelease({ minAndroidBuild, androidStoreUrl, androidMessage });
    state.appRelease = response.data || null;
    renderAppRelease();
    toast(`Actualización obligatoria guardada desde la compilación ${minAndroidBuild}.`, 'success');
  } catch (error) {
    toast(`No se pudo guardar la actualización: ${firebaseErrorMessage(error)}`, 'error');
  } finally {
    elements.saveRelease.disabled = false;
  }
}

function renderAll() {
  if (!state.profile) return;
  renderOverview();
  renderReports();
  renderTeams();
  renderAds();
  renderUsage();
  renderAppRelease();
  if (state.currentView === 'map') renderMap();
}

function showView(view) {
  if (!VIEW_TITLES[view]) return;
  if (view === 'ads' && state.profile?.role !== 'admin') return;
  if (view === 'release' && state.profile?.role !== 'admin') return;
  state.currentView = view;
  document.querySelectorAll('[data-view-panel]').forEach((panel) => {
    const active = panel.dataset.viewPanel === view;
    panel.hidden = !active;
    panel.classList.toggle('active', active);
  });
  document.querySelectorAll('.nav-item[data-view]').forEach((button) => button.classList.toggle('active', button.dataset.view === view));
  const [kicker, title] = VIEW_TITLES[view];
  elements.pageKicker.textContent = kicker;
  elements.pageTitle.textContent = title;
  document.querySelector('.sidebar')?.classList.remove('open');
  if (view === 'map') window.setTimeout(renderMap, 20);
  if (view === 'usage' && state.usageScopeKey !== usageScopeKey()) loadUsageSummary();
  if (view === 'release') loadAppRelease();
}

function selectedReport() { return state.reports.find((report) => report.id === state.selectedReportId) || null; }

function closePhotoViewer({ restoreFocus = true } = {}) {
  if (elements.photoViewer.hidden) return;
  const trigger = state.photoTrigger;
  state.photoTrigger = null;
  elements.photoViewer.hidden = true;
  elements.photoViewer.setAttribute('aria-hidden', 'true');
  elements.photoViewerImage.removeAttribute('src');
  document.body.classList.remove('photo-viewer-open');
  if (restoreFocus && trigger?.isConnected) trigger.focus();
}

function openPhotoViewer(url, alt, trigger) {
  if (typeof url !== 'string' || !/^https:\/\//i.test(url)) return;
  state.photoTrigger = trigger || document.activeElement;
  elements.photoViewerImage.src = url;
  elements.photoViewerImage.alt = alt;
  elements.photoViewer.hidden = false;
  elements.photoViewer.setAttribute('aria-hidden', 'false');
  document.body.classList.add('photo-viewer-open');
  window.requestAnimationFrame(() => elements.closePhotoViewer.focus());
}

function photoGroup(title, photos) {
  const group = element('div', { className: 'photo-group' });
  group.append(element('h4', { text: title }));
  const urls = Array.isArray(photos) ? photos.filter((url) => typeof url === 'string' && /^https:\/\//i.test(url)) : [];
  if (!urls.length) {
    group.append(element('div', { className: 'photo-empty', text: 'Sin fotos registradas en esta etapa.' }));
    return group;
  }
  const grid = element('div', { className: 'photo-grid' });
  urls.forEach((url, index) => {
    const alt = `${title} ${index + 1}`;
    const button = element('button', {
      className: 'photo-thumb',
      type: 'button',
      title: 'Ampliar foto',
      ariaLabel: `Ampliar ${alt}`,
      onClick: (event) => openPhotoViewer(url, alt, event.currentTarget),
    });
    const image = element('img', { src: url, alt: `${title} ${index + 1}`, loading: 'lazy' });
    button.append(image); grid.append(button);
  });
  group.append(grid);
  return group;
}

function detailSection(title, content) {
  const section = element('section', { className: 'detail-section' });
  section.append(element('h3', { text: title }));
  if (typeof content === 'string') section.append(element('p', { text: content }));
  else section.append(content);
  return section;
}

function closeDrawer() {
  state.selectedReportId = null;
  elements.drawer.classList.remove('open');
  elements.drawer.setAttribute('aria-hidden', 'true');
  elements.drawerBackdrop.hidden = true;
}

function openReport(reportId) {
  state.selectedReportId = reportId;
  renderDrawer();
  elements.drawerBackdrop.hidden = false;
  elements.drawer.classList.add('open');
  elements.drawer.setAttribute('aria-hidden', 'false');
}

function renderDrawer() {
  const report = selectedReport();
  if (!report) { closeDrawer(); return; }
  elements.drawerTitle.textContent = reportName(report);
  const content = [];
  const meta = element('div', { className: 'detail-meta' });
  meta.append(statusPill(report.status), priorityPill(report), element('span', { className: 'panel-badge', text: categoryLabel(report.category) }));
  content.push(meta);
  content.push(detailSection('Descripción del reporte', safeText(report.description, 'Sin descripción adicional.')));
  const location = element('div', { className: 'detail-location' });
  location.append(element('span', { text: '⌖' }), element('p', { text: `${reportLocation(report)} · ${formatDate(report.createdAt, { hour: '2-digit', minute: '2-digit' })}` }));
  content.push(detailSection('Ubicación y registro', location));
  const evidence = element('section', { className: 'photo-section' });
  evidence.append(element('h3', { text: 'Evidencia fotográfica' }));
  evidence.append(photoGroup('Reporte del vecino', report.photosReport), photoGroup('Llegada de la cuadrilla', report.photosBefore), photoGroup('Avances de trabajo', report.photosProgress), photoGroup('Trabajo finalizado', report.photosAfter));
  content.push(evidence);

  if (['pending', 'assigned'].includes(report.status)) {
    const availableTeams = state.teams.filter((team) => team.municipalityId === report.municipalityId && team.active !== false);
    const select = element('select', { ariaLabel: 'Asignar cuadrilla' });
    select.append(element('option', { value: '', text: 'Seleccionar cuadrilla' }));
    availableTeams.forEach((team) => select.append(element('option', { value: team.id, text: safeText(team.name, team.id) })));
    if (report.assignedTeamId) select.value = report.assignedTeamId;
    const assign = element('button', { className: 'button primary', type: 'button', text: report.assignedTeamId ? 'Reasignar cuadrilla' : 'Asignar cuadrilla', disabled: !availableTeams.length, onClick: async () => {
      if (!select.value) { toast('Elegí una cuadrilla antes de asignar.', 'error'); return; }
      await withButton(assign, async () => {
        await assignReportTeam({ reportId: report.id, teamId: select.value });
        toast('La cuadrilla fue asignada y el vecino recibirá la actualización.', 'success');
      });
    } });
    const form = element('div', { className: 'drawer-form' });
    form.append(element('label', { text: 'Resolver con una cuadrilla' }), select, assign);
    if (!availableTeams.length) form.append(element('small', { text: 'No hay cuadrillas activas disponibles para este municipio.' }));
    content.push(detailSection('Asignación operativa', form));
  } else {
    const team = state.teams.find((item) => item.id === report.assignedTeamId);
    content.push(detailSection('Asignación operativa', team ? `Cuadrilla asignada: ${safeText(team.name, team.id)}.` : 'Este reporte no tiene una cuadrilla asignada.'));
  }

  if (isOpen(report)) {
    const prioritySelect = element('select', { ariaLabel: 'Definir prioridad del reporte' });
    for (let value = 1; value <= 5; value += 1) prioritySelect.append(element('option', { value: String(value), text: `Prioridad ${value}${value >= 4 ? ' · alta' : ''}` }));
    prioritySelect.value = String(Math.max(1, Math.min(5, number(report.priority, 1))));
    const savePriority = element('button', { className: 'button secondary', type: 'button', text: 'Guardar prioridad', onClick: async () => {
      await withButton(savePriority, async () => {
        await setReportPriority({ reportId: report.id, priority: Number(prioritySelect.value) });
        toast('La prioridad operativa fue actualizada.', 'success');
      });
    } });
    const priorityForm = element('div', { className: 'drawer-form' });
    priorityForm.append(element('label', { text: 'Prioridad definida por gestión' }), prioritySelect, savePriority);
    content.push(detailSection('Priorización', priorityForm));
  }

  const message = element('textarea', { placeholder: 'Escribí una actualización clara para la persona que reportó el problema.', ariaLabel: 'Mensaje de actualización al vecino', maxlength: '280' });
  const notify = element('button', { className: 'button primary', type: 'button', text: 'Enviar actualización al vecino', onClick: async () => {
    if (message.value.trim().length < 3) { toast('Escribí un mensaje de al menos 3 caracteres.', 'error'); return; }
    await withButton(notify, async () => {
      const requestId = window.crypto?.randomUUID ? window.crypto.randomUUID().replaceAll('-', '') : `${Date.now()}${Math.random().toString(16).slice(2)}`;
      const response = await sendReportUpdate({ reportId: report.id, message: message.value.trim(), requestId });
      message.value = '';
      const attached = response.data?.imageAttached ? ' Se adjuntó la última evidencia de la cuadrilla.' : '';
      const delivery = response.data?.delivery;
      const deliveryText = delivery === 'push'
        ? ' Notificación enviada al dispositivo del vecino.'
        : delivery === 'in_app'
          ? ' Actualización guardada en Alertas; el vecino debe habilitar notificaciones para recibirla en pantalla.'
          : ' Actualización registrada.';
      toast(`${deliveryText}${attached}`, 'success');
    });
  } });
  const updateForm = element('div', { className: 'drawer-form' });
  updateForm.append(element('label', { text: 'Notificación al vecino' }), message, element('small', { text: 'Si la cuadrilla ya cargó evidencia de avance o finalización, la actualización adjunta la última foto automáticamente.' }), notify);
  content.push(detailSection('Comunicación de la solución', updateForm));

  const mapButton = element('button', { className: 'button secondary', type: 'button', text: 'Ver ubicación en el mapa', onClick: () => {
    closeDrawer();
    showView('map');
    const lat = number(report.location?.lat, NaN); const lng = number(report.location?.lng, NaN);
    if (Number.isFinite(lat) && Number.isFinite(lng)) window.setTimeout(() => state.map?.setView([lat, lng], 16, { animate: true }), 80);
  } });
  content.push(mapButton);
  elements.drawerContent.replaceChildren(...content);
}

async function withButton(button, action) {
  const original = button.textContent;
  button.disabled = true;
  button.textContent = 'Procesando…';
  try { await action(); }
  catch (error) { toast(firebaseErrorMessage(error), 'error'); }
  finally { button.disabled = false; button.textContent = original; }
}

async function generateAiAnalysis() {
  const scope = scopeParts();
  if (scope.type !== 'municipality') {
    toast('Para generar el análisis elegí un municipio específico en el selector superior.', 'error');
    return;
  }
  const periodDays = Number(elements.aiPeriod.value);
  elements.generateAi.disabled = true;
  elements.generateAi.textContent = 'Analizando…';
  elements.aiState.hidden = false;
  elements.aiResults.hidden = true;
  elements.aiState.replaceChildren(element('span', { className: 'ai-mark', text: '✦' }), element('h3', { text: 'Analizando datos operativos…' }), element('p', { text: 'Se procesan métricas agregadas, sin datos personales ni ubicaciones exactas.' }));
  try {
    const response = await generateMunicipalityReport({ municipalityId: scope.municipalityId, periodDays });
    renderAiResult(response.data || {});
  } catch (error) {
    elements.aiState.replaceChildren(element('span', { className: 'ai-mark', text: '!' }), element('h3', { text: 'El análisis no está disponible ahora.' }), element('p', { text: firebaseErrorMessage(error) }));
    toast(firebaseErrorMessage(error), 'error');
  } finally {
    elements.generateAi.disabled = false;
    elements.generateAi.textContent = '✦ Generar análisis';
  }
}

function bindEvents() {
  elements.loginForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    setLoginMessage('');
    if (!elements.loginForm.reportValidity()) return;
    setLoginBusy(true);
    try { await signInWithEmailAndPassword(auth, elements.loginEmail.value.trim(), elements.loginPassword.value); }
    catch (error) { setLoginMessage(firebaseErrorMessage(error)); }
    finally { setLoginBusy(false); }
  });
  elements.googleLogin.addEventListener('click', async () => {
    setLoginMessage(''); setLoginBusy(true);
    try { await signInWithPopup(auth, new GoogleAuthProvider()); }
    catch (error) { setLoginMessage(firebaseErrorMessage(error)); }
    finally { setLoginBusy(false); }
  });
  elements.deniedSignout.addEventListener('click', () => signOut(auth));
  elements.signout.addEventListener('click', () => signOut(auth));
  elements.profileMenu.addEventListener('click', () => {
    const hidden = elements.profilePopover.hidden;
    elements.profilePopover.hidden = !hidden;
    elements.profileMenu.setAttribute('aria-expanded', String(hidden));
  });
  document.addEventListener('click', (event) => {
    if (!elements.profileMenu.contains(event.target) && !elements.profilePopover.contains(event.target)) {
      elements.profilePopover.hidden = true;
      elements.profileMenu.setAttribute('aria-expanded', 'false');
    }
  });
  elements.municipalitySelect.addEventListener('change', () => {
    state.scope = elements.municipalitySelect.value;
    state.mapHasFitted = false;
    state.mapScopeKey = null;
    renderAll();
    loadUsageSummary();
  });
  elements.releaseForm.addEventListener('submit', submitAppRelease);
  elements.refreshData.addEventListener('click', () => { subscribeOperationalData(); subscribeAds(); loadUsageSummary(); toast('Actualizando datos en tiempo real.'); });
  elements.reportSearch.addEventListener('input', () => { state.search = elements.reportSearch.value; renderReports(); if (state.currentView === 'map') renderMap(); });
  elements.statusFilter.addEventListener('change', () => { state.status = elements.statusFilter.value; renderReports(); if (state.currentView === 'map') renderMap(); });
  elements.priorityFilter.addEventListener('change', () => { state.priority = elements.priorityFilter.value; renderReports(); if (state.currentView === 'map') renderMap(); });
  elements.newTeam.addEventListener('click', () => openTeamEditor());
  elements.teamForm.addEventListener('submit', submitTeamForm);
  elements.cancelTeam.addEventListener('click', closeTeamEditor);
  elements.cancelTeamForm.addEventListener('click', closeTeamEditor);
  elements.newAd.addEventListener('click', () => openAdEditor());
  elements.adForm.addEventListener('submit', submitAdForm);
  elements.cancelAd.addEventListener('click', closeAdEditor);
  elements.cancelAdForm.addEventListener('click', closeAdEditor);
  elements.generateAi.addEventListener('click', generateAiAnalysis);
  elements.overviewAiButton.addEventListener('click', () => { showView('strategy'); generateAiAnalysis(); });
  document.querySelectorAll('[data-view]').forEach((button) => button.addEventListener('click', () => showView(button.dataset.view)));
  document.querySelectorAll('[data-go-view]').forEach((button) => button.addEventListener('click', () => showView(button.dataset.goView)));
  elements.mobileMenu.addEventListener('click', () => document.querySelector('.sidebar')?.classList.toggle('open'));
  elements.closeDrawer.addEventListener('click', closeDrawer);
  elements.drawerBackdrop.addEventListener('click', closeDrawer);
  elements.closePhotoViewer.addEventListener('click', closePhotoViewer);
  elements.photoViewerBackdrop.addEventListener('click', closePhotoViewer);
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!elements.photoViewer.hidden) closePhotoViewer();
    else closeDrawer();
  });
}

onAuthStateChanged(auth, async (user) => {
  const version = ++state.authVersion;
  cleanUpSubscriptions();
  state.user = user;
  state.profile = null;
  state.reports = [];
  state.teams = [];
  state.ads = [];
  state.usage = null;
  state.usageLoading = false;
  state.usageError = '';
  state.usageScopeKey = '';
  state.appRelease = null;
  state.releaseLoading = false;
  state.selectedReportId = null;
  closeDrawer();
  closeTeamEditor();
  closeAdEditor();
  if (!user) { showOnly('auth'); return; }
  try {
    const profile = await resolveProfile(user);
    if (version !== state.authVersion) return;
    if (!profile || profile.disabled === true || !MANAGEMENT_ROLES.has(profile.role) || (profile.role !== 'admin' && !safeText(profile.municipalityId))) {
      elements.deniedCopy.textContent = !profile
        ? 'Esta cuenta todavía no tiene un perfil de gestión. Pedí que la habiliten desde la administración municipal.'
        : profile.disabled === true
          ? 'Esta cuenta fue deshabilitada por la administración municipal.'
          : 'Tu cuenta no tiene un rol de gestión o un municipio asignado.';
      showOnly('denied');
      return;
    }
    state.profile = profile;
    state.scope = profile.role === 'admin' ? 'all' : `municipality|${profile.municipalityId}`;
    elements.adsNav.hidden = profile.role !== 'admin';
    setupUserHeader();
    showOnly('admin');
    subscribeMunicipalities();
    renderMunicipalityPicker();
    subscribeOperationalData();
    subscribeAds();
    loadUsageSummary();
    loadAppRelease();
  } catch (error) {
    if (version !== state.authVersion) return;
    elements.deniedCopy.textContent = firebaseErrorMessage(error);
    showOnly('denied');
  }
});

bindEvents();
