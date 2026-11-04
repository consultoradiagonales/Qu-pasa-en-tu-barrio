/* ARGWX · Detección y seguimiento de tormentas por consenso multimodelo.
 *
 * 1. En cada modelo y cada hora se marcan los puntos de la grilla con tormenta
 *    (código WMO >= 95) o lluvia fuerte (>= 4 mm/h) y se agrupan en "celdas".
 * 2. Las celdas de los distintos modelos que caen en el mismo lugar forman un "sistema":
 *    probabilidad = modelos que lo muestran / modelos analizados (consenso).
 *    El círculo abarca la zona de todos los modelos: si los modelos difieren, el círculo crece.
 * 3. Los sistemas se encadenan hora a hora: trayectoria, velocidad, dirección y tendencia.
 *
 * Sin dependencias: se usa en el navegador (window.ARGWX_TRACKING) y en Node (tests).
 */
(function (root) {
  "use strict";
  const LEVELS = ["GREEN", "YELLOW", "ORANGE", "RED", "PURPLE"];
  const R = 6371.0088, RAD = Math.PI / 180;
  // Umbrales horarios iniciales propios de ARGWX (a calibrar con verificación).
  const HOURLY = {storm_mm: 4, orange_mm: 10, red_mm: 20, purple_mm: 40, orange_gust: 80, red_gust: 100, purple_gust: 120};
  const CARD = ["norte", "noreste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"];

  function hav(lat1, lon1, lat2, lon2) {
    const p1 = lat1 * RAD, p2 = lat2 * RAD, dp = (lat2 - lat1) * RAD, dl = (lon2 - lon1) * RAD;
    const h = Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
  }

  function bearing(lat1, lon1, lat2, lon2) {
    const p1 = lat1 * RAD, p2 = lat2 * RAD, dl = (lon2 - lon1) * RAD;
    const x = Math.sin(dl) * Math.cos(p2);
    const y = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
    return (Math.atan2(x, y) / RAD + 360) % 360;
  }

  const cardinal = deg => CARD[Math.round((((deg % 360) + 360) % 360) / 45) % 8];
  const isStorm = (p, c) => (c || 0) >= 95 || (p || 0) >= HOURLY.storm_mm;

  function cellLevel(p, c, g) {
    p = p || 0; c = c || 0; g = g || 0;
    let l = isStorm(p, c) ? 1 : 0;
    if (p >= HOURLY.orange_mm || g >= HOURLY.orange_gust || (c >= 96 && c <= 98)) l = Math.max(l, 2);
    if (p >= HOURLY.red_mm || g >= HOURLY.red_gust || c === 99) l = Math.max(l, 3);
    if (p >= HOURLY.purple_mm || g >= HOURLY.purple_gust) l = Math.max(l, 4);
    return l;
  }

  /* Ícono según la condición: tormenta (nube con rayo), lluvia fuerte (gotas grandes), lluvia débil (gotitas). */
  function condition(p, c) {
    p = p || 0; c = c || 0;
    if (c >= 95) return "storm";
    if (p >= 4 || c === 65 || c === 67 || c === 82) return "heavy";
    if (p >= 0.2 || (c >= 51 && c <= 63) || c === 66 || c === 80 || c === 81) return "light";
    return null;
  }

  /* Grilla regular: filas de norte a sur, columnas de oeste a este (mismo orden que el servidor). */
  function makeGrid(spec) {
    const lats = [], lons = [];
    for (let la = spec.latN; la >= spec.latS - 1e-9; la -= spec.step) lats.push(+la.toFixed(4));
    for (let lo = spec.lonW; lo <= spec.lonE + 1e-9; lo += spec.step) lons.push(+lo.toFixed(4));
    const points = [];
    lats.forEach((la, r) => lons.forEach((lo, c) => points.push({r, c, lat: la, lon: lo})));
    return {spec, lats, lons, points, nLat: lats.length, nLon: lons.length};
  }

  /* Respuesta multimodelo de Open-Meteo -> {times, models: {modelo: {P, C, G}}} con matrices [hora][punto]. */
  function parseModels(resp, models) {
    const locs = Array.isArray(resp) ? resp : [resp];
    const times = locs[0].hourly.time, H = times.length, N = locs.length, out = {times, models: {}};
    for (const m of models) {
      const P = [], C = [], G = [];
      for (let h = 0; h < H; h++) { P.push(new Array(N).fill(null)); C.push(new Array(N).fill(null)); G.push(new Array(N).fill(null)); }
      let any = false;
      locs.forEach((loc, i) => {
        const hr = loc.hourly || {}, p = hr["precipitation_" + m], c = hr["weather_code_" + m], g = hr["wind_gusts_10m_" + m];
        for (let h = 0; h < H; h++) {
          if (p && p[h] != null) { P[h][i] = p[h]; any = true; }
          if (c) C[h][i] = c[h];
          if (g) G[h][i] = g[h];
        }
      });
      if (any) out.models[m] = {P, C, G};
    }
    return out;
  }

  function clustersFor(grid, P, C, G) {
    const N = grid.points.length, storm = new Uint8Array(N), seen = new Uint8Array(N), out = [];
    for (let i = 0; i < N; i++) storm[i] = isStorm(P[i], C[i]) ? 1 : 0;
    const half = grid.spec.step * 111.2 / 2;
    for (let i = 0; i < N; i++) {
      if (!storm[i] || seen[i]) continue;
      const comp = [], queue = [i];
      seen[i] = 1;
      while (queue.length) {
        const k = queue.pop(), r = Math.floor(k / grid.nLon), c = k % grid.nLon;
        comp.push(k);
        for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
          const rr = r + dr, cc = c + dc;
          if (rr < 0 || cc < 0 || rr >= grid.nLat || cc >= grid.nLon) continue;
          const j = rr * grid.nLon + cc;
          if (storm[j] && !seen[j]) { seen[j] = 1; queue.push(j); }
        }
      }
      for (const part of split(grid, comp, MAX_CELLS)) out.push(describe(grid, part, P, C, G, half));
    }
    return out;
  }

  /* Un área de tormenta muy grande se parte en celdas de hasta MAX_CELLS puntos (k-medias simple),
     para que cada círculo represente una tormenta y no media provincia o medio país. */
  const MAX_CELLS = 5;
  function split(grid, comp, maxCells) {
    if (comp.length <= maxCells) return [comp];
    const k = Math.ceil(comp.length / maxCells), pts = comp.map(i => grid.points[i]);
    const seeds = [pts[0]];
    while (seeds.length < k) {
      let best = null, bd = -1;
      for (const p of pts) { const d = Math.min(...seeds.map(s => hav(p.lat, p.lon, s.lat, s.lon))); if (d > bd) { bd = d; best = p; } }
      seeds.push(best);
    }
    let centers = seeds.map(s => ({lat: s.lat, lon: s.lon})), groups = [];
    for (let it = 0; it < 8; it++) {
      groups = centers.map(() => []);
      comp.forEach((i, j) => {
        const p = pts[j];
        let bi = 0, bd = Infinity;
        centers.forEach((c, ci) => { const d = hav(p.lat, p.lon, c.lat, c.lon); if (d < bd) { bd = d; bi = ci; } });
        groups[bi].push(i);
      });
      centers = groups.map((g, gi) => g.length ? {lat: g.reduce((s, i) => s + grid.points[i].lat, 0) / g.length,
                                                  lon: g.reduce((s, i) => s + grid.points[i].lon, 0) / g.length} : centers[gi]);
    }
    return groups.filter(g => g.length);
  }

  function describe(grid, comp, P, C, G, half) {
    let wsum = 0, lat = 0, lon = 0, level = 0, pmax = 0, thunder = 0;
    for (const k of comp) {
      const w = Math.max(1, P[k] || 0), pt = grid.points[k];
      wsum += w; lat += pt.lat * w; lon += pt.lon * w;
      level = Math.max(level, cellLevel(P[k], C[k], G ? G[k] : 0));
      pmax = Math.max(pmax, P[k] || 0);
      if ((C[k] || 0) >= 95) thunder++;
    }
    lat /= wsum; lon /= wsum;
    // Radio equivalente: el de un círculo con la misma superficie que los puntos con tormenta.
    const cellKm2 = (grid.spec.step * 111.2) ** 2 * Math.cos(lat * RAD);
    const radius = Math.max(half, Math.sqrt(comp.length * cellKm2 / Math.PI));
    return {lat, lon, radius, cells: comp.length, level, pmax, thunder};
  }

  function systemsAt(grid, data, h, nModels) {
    const items = [];
    for (const [m, d] of Object.entries(data.models)) {
      for (const cl of clustersFor(grid, d.P[h], d.C[h], d.G[h])) items.push(Object.assign(cl, {model: m}));
    }
    const parent = items.map((_, i) => i);
    const find = i => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    const gap = 1.5 * grid.spec.step * 111.2;
    for (let a = 0; a < items.length; a++) for (let b = a + 1; b < items.length; b++) {
      const d = hav(items[a].lat, items[a].lon, items[b].lat, items[b].lon);
      if (d <= gap) parent[find(a)] = find(b);
    }
    const groups = {};
    items.forEach((it, i) => { const k = find(i); (groups[k] = groups[k] || []).push(it); });
    return Object.values(groups).map(g => {
      const w = g.reduce((s, x) => s + x.cells, 0);
      const lat = g.reduce((s, x) => s + x.lat * x.cells, 0) / w, lon = g.reduce((s, x) => s + x.lon * x.cells, 0) / w;
      // Círculo probabilístico: tamaño típico de la tormenta + dispersión entre modelos (incertidumbre).
      const spread = Math.sqrt(g.reduce((s, x) => s + hav(lat, lon, x.lat, x.lon) ** 2, 0) / g.length);
      const radius = Math.min(g.reduce((s, x) => s + x.radius * x.cells, 0) / w + spread, 2.5 * grid.spec.step * 111.2);
      const byModel = {};
      g.forEach(x => { byModel[x.model] = Math.max(byModel[x.model] || 0, x.level); });
      const models = Object.keys(byModel), lv = Object.values(byModel);
      let level = 0;
      for (let L = 4; L >= 1; L--) if (lv.filter(v => v >= L).length >= 2) { level = L; break; }
      if (!level) level = Math.max(...lv);
      return {h, lat, lon, radius, models, prob: models.length / nModels, level,
              pmax: Math.max(...g.map(x => x.pmax)), thunder: g.some(x => x.thunder > 0)};
    });
  }

  function summarize(t, times) {
    const pts = t.points, a = pts[0], z = pts[pts.length - 1], hours = z.h - a.h;
    const dist = hours > 0 ? hav(a.lat, a.lon, z.lat, z.lon) : 0;
    const dir = hours > 0 && dist > 15 ? bearing(a.lat, a.lon, z.lat, z.lon) : null;
    const levelMax = Math.max(...pts.map(p => p.level)), probMax = Math.max(...pts.map(p => p.prob));
    const dl = z.level - a.level, dr = z.radius / a.radius;
    const trend = hours === 0 ? "aparece solo en una hora" : (dl > 0 || dr > 1.25) ? "se intensifica"
      : (dl < 0 || dr < 0.8) ? "se debilita" : "se mantiene";
    return {points: pts.map(p => Object.assign({}, p, {t: times[p.h]})), speed: hours > 0 ? Math.round(dist / hours) : 0,
            dir, dirText: dir == null ? (hours === 0 ? "sin desplazamiento estimable" : "casi estacionaria") : "hacia el " + cardinal(dir), trend, levelMax,
            level: LEVELS[levelMax], probMax, start: times[a.h], end: times[z.h]};
  }

  function track(grid, data, opts) {
    opts = opts || {};
    const nModels = opts.nModels || Object.keys(data.models).length || 1;
    const H = data.times.length, perHour = [];
    for (let h = 0; h < H; h++) perHour.push(systemsAt(grid, data, h, nModels));
    const maxMove = opts.maxMoveKm || 160, tracks = [];
    let open = (perHour[0] || []).map(s => ({points: [s]}));
    tracks.push(...open);
    for (let h = 1; h < H; h++) {
      const next = perHour[h], pairs = [], takenA = new Set(), takenB = new Set(), nextOpen = [];
      open.forEach((t, a) => {
        const last = t.points[t.points.length - 1];
        next.forEach((s, b) => {
          const d = hav(last.lat, last.lon, s.lat, s.lon);
          if (d <= maxMove + 0.5 * Math.min(last.radius, s.radius)) pairs.push([d, a, b]);
        });
      });
      pairs.sort((x, y) => x[0] - y[0]);
      for (const [, a, b] of pairs) {
        if (takenA.has(a) || takenB.has(b)) continue;
        takenA.add(a); takenB.add(b);
        open[a].points.push(next[b]);
        nextOpen.push(open[a]);
      }
      next.forEach((s, b) => { if (!takenB.has(b)) { const t = {points: [s]}; tracks.push(t); nextOpen.push(t); } });
      open = nextOpen;
    }
    const minProb = opts.minProb == null ? 0.4 : opts.minProb;
    // Se descartan señales débiles: menos de 2 modelos, o una sola hora sin mayoría de modelos.
    return tracks.map(t => summarize(t, data.times)).filter(t => t.probMax >= minProb && (t.points.length >= 2 || t.probMax >= 0.6))
      .sort((x, y) => y.levelMax - x.levelMax || y.probMax - x.probMax);
  }

  /* Lugares (municipios) que quedan dentro de algún círculo de la trayectoria y a qué hora entran. */
  function affected(tr, places) {
    const out = [];
    for (const pl of places) {
      const first = tr.points.find(p => hav(pl.lat, pl.lon, p.lat, p.lon) <= p.radius);
      if (first) out.push({id: pl.id, name: pl.name, t: first.t, h: first.h, level: LEVELS[first.level], prob: first.prob});
    }
    return out.sort((x, y) => x.h - y.h || x.name.localeCompare(y.name));
  }

  /* Campo de viento interpolado (km/h hacia donde sopla): devuelve f(lat, lon) -> [u, v] o null fuera de la grilla. */
  function windField(grid, speeds, dirs) {
    const N = grid.points.length, U = new Float32Array(N), V = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const s = speeds[i] || 0, d = (dirs[i] || 0) * RAD;
      U[i] = -s * Math.sin(d); V[i] = -s * Math.cos(d);
    }
    const {nLat, nLon, spec} = grid;
    return function (lat, lon) {
      const fr = (spec.latN - lat) / spec.step, fc = (lon - spec.lonW) / spec.step;
      if (fr < 0 || fc < 0 || fr > nLat - 1 || fc > nLon - 1) return null;
      const r0 = Math.floor(fr), c0 = Math.floor(fc), r1 = Math.min(r0 + 1, nLat - 1), c1 = Math.min(c0 + 1, nLon - 1);
      const tr = fr - r0, tc = fc - c0, a = r0 * nLon, b = r1 * nLon;
      const u = (U[a + c0] * (1 - tc) + U[a + c1] * tc) * (1 - tr) + (U[b + c0] * (1 - tc) + U[b + c1] * tc) * tr;
      const v = (V[a + c0] * (1 - tc) + V[a + c1] * tc) * (1 - tr) + (V[b + c0] * (1 - tc) + V[b + c1] * tc) * tr;
      return [u, v];
    };
  }

  root.ARGWX_TRACKING = {LEVELS, HOURLY, hav, bearing, cardinal, isStorm, cellLevel, condition, makeGrid, parseModels,
                         clustersFor, systemsAt, track, affected, windField};
})(typeof module !== "undefined" && module.exports ? module.exports : window);
