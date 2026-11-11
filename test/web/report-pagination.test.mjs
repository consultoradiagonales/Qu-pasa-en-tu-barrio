import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { matchesReportStatus, reportStatusLabel } from '../../web/admin/report-status.js';

// Execute the real ADMIN functions without Firebase or a browser. The mocks
// represent paginated Firestore responses and just the DOM used by this view.
const app = readFileSync(new URL('../../web/admin/app.js', import.meta.url), 'utf8');
const filters = app.slice(app.indexOf('function reportFilterKey()'), app.indexOf('function priorityScore('));
const renderer = app.slice(app.indexOf('function renderReports()'), app.indexOf('function ensureMap()'));
assert.ok(filters && renderer, 'Las funciones de ADMIN deben poder localizarse.');

function node() {
  return {
    hidden: false, disabled: false, textContent: '', value: '', children: [], attributes: {},
    append(...children) { this.children.push(...children); },
    replaceChildren(...children) { this.children = children; },
    setAttribute(name, value) { this.attributes[name] = value; },
    focus() { this.focused = true; },
  };
}

function snapshot(rows) {
  return { size: rows.length, docs: rows.map(({ id, ...data }) => ({ id, data: () => data })) };
}

function reports(count, status, prefix, municipalityId = 'municipio-a') {
  return Array.from({ length: count }, (_, index) => ({
    id: `${prefix}-${index}`, status, municipalityId, title: `${prefix} ${index}`,
    category: 'lighting', priority: 1,
  }));
}

function deferred() {
  let resolve;
  const promise = new Promise(accept => { resolve = accept; });
  return { promise, resolve };
}

function harness({ initial = [], pages = [], fetchPage, overrides = {} } = {}) {
  const nodes = new Map();
  const getNode = id => {
    if (!nodes.has(id)) nodes.set(id, node());
    return nodes.get(id);
  };
  const elements = {
    reportCount: getNode('report-count'), reportsBody: getNode('reports-body'),
    reportsEmpty: getNode('reports-empty'), statusFilter: getNode('status-filter'),
    reportSearch: getNode('report-search'), priorityFilter: getNode('priority-filter'),
  };
  const state = {
    status: 'open', priority: 'all', search: '', scope: 'municipio-a',
    authVersion: 1, reportLoadGeneration: 1, currentView: 'reports',
    reports: [...initial], teams: [], reportCursor: { id: 'initial-cursor' },
    reportHasMore: true, reportLoadingMore: false, reportInitialLoading: false,
    reportExtraPages: [], ...overrides,
  };
  const calls = { queries: [], renders: [], toasts: [], views: [], drawersClosed: 0, scrolls: 0 };
  const context = vm.createContext({
    state, elements, matchesReportStatus, reportStatusLabel,
    document: { getElementById: getNode },
    window: { scrollTo() { calls.scrolls++; } },
    geographicReports: () => state.reports.filter(report => state.scope === 'all' || report.municipalityId === state.scope),
    isHigh: report => Number(report.priority) >= 4,
    reportName: report => report.title || report.id,
    categoryLabel: category => category,
    reportLocation: report => report.location?.address || '',
    element: () => node(), statusPill: () => node(), priorityPill: () => node(),
    formatDate: () => 'Fecha', openReport() {},
    reportsQuery: () => ({ scope: state.scope }),
    startAfter: cursor => ({ cursor }),
    query: (...args) => args,
    async getDocs(query) {
      calls.queries.push(query);
      return fetchPage ? fetchPage(query, calls.queries.length) : snapshot(pages.shift() || []);
    },
    renderAll() { context.renderReports(); },
    renderMap() {},
    toast(message) { calls.toasts.push(message); },
    firebaseErrorMessage: error => error.message,
    closeDrawer() { calls.drawersClosed++; },
    showView(view) { state.currentView = view; calls.views.push(view); context.fillReportPage(); },
  });
  vm.runInContext(filters + '\n' + renderer, context, { filename: 'ADMIN-report-pagination.js' });
  const actualRenderer = context.renderReports;
  context.renderReports = () => {
    actualRenderer();
    calls.renders.push({
      loading: state.reportLoadingMore || state.reportInitialLoading,
      emptyHidden: elements.reportsEmpty.hidden,
      count: context.filteredReports().length,
      hasMore: state.reportHasMore,
    });
  };
  return { state, elements, nodes, calls, context };
}

test('encuentra abiertos detrás de dos páginas sin coincidencias y completa 200 resultados', async () => {
  const h = harness({
    initial: reports(200, 'resolved', 'reciente'),
    pages: [reports(200, 'rejected', 'segunda'), reports(200, 'pending', 'antiguo')],
  });
  await h.context.fillReportPage();
  assert.equal(h.context.filteredReports().length, 200);
  assert.equal(h.calls.queries.length, 2);
  assert.equal(h.state.reports.length, 600);
  assert.equal(h.state.reportCursor.id, 'antiguo-199');
  assert.equal(h.state.reportHasMore, true);
  assert.equal(h.state.reportLoadingMore, false);
  assert.equal(h.elements.reportsEmpty.hidden, true);
});

test('cargar más completa otro bloque de coincidencias en vez de detenerse en una página de otro estado', async () => {
  const h = harness({
    initial: reports(200, 'pending', 'primero'),
    pages: [reports(200, 'closed', 'intermedio'), reports(200, 'assigned', 'anterior')],
  });
  await h.context.loadMoreReports();
  assert.equal(h.context.filteredReports().length, 400);
  assert.equal(h.calls.queries.length, 2);
  assert.equal(h.elements.reportsBody.children.length, 400);
  assert.equal(h.nodes.get('load-more-reports').hidden, false);
});

test('no presenta un falso vacío durante la búsqueda; sólo muestra vacío al agotar las páginas', async () => {
  const page = deferred();
  const h = harness({ initial: reports(200, 'closed', 'inicio'), fetchPage: () => page.promise });
  const loading = h.context.fillReportPage();
  assert.equal(h.state.reportLoadingMore, true);
  assert.equal(h.elements.reportsEmpty.hidden, true);
  assert.equal(h.elements.reportsBody.attributes['aria-busy'], 'true');
  assert.match(h.elements.reportCount.textContent, /Buscando en páginas anteriores/);
  page.resolve(snapshot(reports(15, 'resolved', 'final')));
  await loading;
  assert.equal(h.state.reportHasMore, false);
  assert.equal(h.state.reportLoadingMore, false);
  assert.equal(h.elements.reportsEmpty.hidden, false);
  assert.equal(h.elements.reportsBody.attributes['aria-busy'], 'false');
  assert.equal(h.nodes.get('load-more-reports').hidden, true);
  assert.ok(h.calls.renders.filter(render => render.loading).every(render => render.emptyHidden));
});

test('cada tarjeta limpia filtros previos y abre su grupo sin cambiar municipio', () => {
  for (const status of ['open', 'unassigned', 'field', 'resolved_week', 'resolution']) {
    const h = harness({ overrides: { search: 'consulta vieja', priority: 'high', status: 'rejected', currentView: 'overview', reportHasMore: false } });
    h.context.openReportStatus(status);
    assert.equal(h.state.scope, 'municipio-a');
    assert.equal(h.state.currentView, 'reports');
    assert.equal(h.state.status, status);
    assert.equal(h.state.search, '');
    assert.equal(h.state.priority, 'all');
    assert.equal(h.elements.statusFilter.value, status);
    assert.equal(h.elements.reportSearch.value, '');
    assert.equal(h.elements.priorityFilter.value, 'all');
    assert.equal(h.elements.statusFilter.focused, true);
    assert.equal(h.calls.drawersClosed, 1);
    assert.equal(h.calls.scrolls, 1);
    assert.deepEqual(h.calls.views, ['reports']);
  }
});

test('una respuesta del filtro anterior se descarta y la búsqueda continúa con el filtro nuevo', async () => {
  const pending = deferred();
  const h = harness({
    initial: reports(200, 'resolved', 'inicio'),
    fetchPage: (_query, count) => count === 1 ? pending.promise : Promise.resolve(snapshot(reports(1, 'in_progress', 'nuevo'))),
  });
  const oldLoad = h.context.fillReportPage();
  h.state.status = 'field';
  h.context.applyReportFilters();
  pending.resolve(snapshot(reports(200, 'pending', 'respuesta-vieja')));
  await oldLoad;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.calls.queries.length, 2);
  assert.equal(h.state.reports.some(report => report.id.startsWith('respuesta-vieja')), false);
  assert.equal(h.context.filteredReports().length, 1);
  assert.equal(h.context.filteredReports()[0].id, 'nuevo-0');
  assert.equal(h.state.reportLoadingMore, false);
});

for (const change of ['scope', 'authVersion', 'reportLoadGeneration']) {
  test(`descarta una página pendiente si cambia ${change}`, async () => {
    const page = deferred();
    const h = harness({ initial: reports(200, 'closed', 'inicio'), fetchPage: () => page.promise });
    const oldLoad = h.context.fillReportPage();
    if (change === 'scope') h.state.scope = 'municipio-b';
    else h.state[change]++;
    h.state.reports = reports(1, 'pending', 'nueva-sesion', 'municipio-b');
    h.state.reportCursor = { id: 'nuevo-cursor' };
    h.state.reportLoadingMore = false;
    page.resolve(snapshot(reports(200, 'pending', 'obsoleto')));
    await oldLoad;
    assert.equal(h.state.reports.length, 1);
    assert.equal(h.state.reports[0].id, 'nueva-sesion-0');
    assert.equal(h.state.reportCursor.id, 'nuevo-cursor');
    assert.equal(h.state.reportExtraPages.length, 0);
  });
}

test('el filtro mantiene el ámbito municipal y no cuenta reportes de otro municipio cargados', async () => {
  const h = harness({
    initial: [...reports(1, 'pending', 'propio'), ...reports(1, 'pending', 'otro', 'municipio-b')],
    pages: [reports(1, 'pending', 'anterior')],
  });
  await h.context.fillReportPage();
  assert.equal(h.context.filteredReports().length, 2);
  assert.ok(h.context.filteredReports().every(report => report.municipalityId === 'municipio-a'));
  assert.equal(h.calls.queries[0][0].scope, 'municipio-a');
});

test('un fallo conserva la opción de reintentar sin anunciar que no existen reportes', async () => {
  const h = harness({
    initial: reports(200, 'closed', 'inicio'),
    fetchPage: async () => { throw new Error('Sin conexión'); },
  });
  await h.context.fillReportPage();
  assert.equal(h.state.reportLoadingMore, false);
  assert.equal(h.state.reportHasMore, true);
  assert.equal(h.elements.reportsEmpty.hidden, true);
  assert.equal(h.nodes.get('load-more-reports').hidden, false);
  assert.equal(h.nodes.get('load-more-reports').disabled, false);
  assert.deepEqual(h.calls.toasts, ['Sin conexión']);
});

test('no inicia paginación durante la carga inicial ni al consultar otra vista', async () => {
  for (const overrides of [{ reportInitialLoading: true }, { currentView: 'map' }, { reportHasMore: false }]) {
    const h = harness({ overrides });
    await h.context.fillReportPage();
    assert.equal(h.calls.queries.length, 0);
  }
});
