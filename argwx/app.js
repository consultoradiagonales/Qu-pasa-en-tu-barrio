/* ConDi · Tiempo en vivo (motor ARGWX). Mapa con viento animado, lluvia, tormentas en movimiento y alertas. */
(function () {
  "use strict";
  const T = window.ARGWX_TRACKING;
  const LV = T.LEVELS;
  const COLOR = {GREEN: "#2e9d4f", YELLOW: "#f2c200", ORANGE: "#f07c00", RED: "#d62828", PURPLE: "#7b2cbf"};
  const LABEL = {GREEN: "Verde", YELLOW: "Amarilla", ORANGE: "Naranja", RED: "Roja", PURPLE: "Púrpura"};
  const INTENS = {YELLOW: "moderada", ORANGE: "fuerte", RED: "severa", PURPLE: "extrema", GREEN: "débil"};
  const MODELS = ["gfs_seamless", "icon_seamless", "ecmwf_ifs025", "gem_seamless", "ukmo_seamless"];
  const OM = "https://api.open-meteo.com/v1/forecast";
  const COND = {storm: "Tormenta eléctrica", heavy: "Lluvia fuerte", light: "Lluvia débil / llovizna"};
  const PHASE = {EL_NINO: "El Niño", LA_NINA: "La Niña", NEUTRAL: "Neutral"};
  const PHASE_COLOR = {EL_NINO: "#d62828", LA_NINA: "#1f6fd1", NEUTRAL: "#8a96a3"};
  const SEAS = {DJF: "DEF", JFM: "EFM", FMA: "FMA", MAM: "MAM", AMJ: "AMJ", MJJ: "MJJ", JJA: "JJA", JAS: "JAS", ASO: "ASO",
                SON: "SON", OND: "OND", NDJ: "NDE"};
  const DARK = false; // Tema claro uniforme para todos los accesos, incluido el mapa.
  const S = {region: "pba", hour: 0, layers: {storms: true, wind: true, wx: true, smn: true, sat: false, radar: true, obs: false, rios: true, costa: false, red: false, cuencas: false}, grids: {},
             cur: null, st: {}, munis: [], provs: [], smnFilter: "storm", pwin: "24", oniRange: "30", play: null, me: null,
             crecF: "alerta", crecN: 40, r72: {}};
  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
  const lvlBadge = l => `<span class="lvl ${l || "UNKNOWN"}" style="background:${COLOR[l] || "#667788"}">${LABEL[l] || "Sin evaluación"}</span>`;
  const hydroHot = c => LV.includes(c.nivel) && c.nivel !== "GREEN";
  const hydroContext = c => `<div class="muted">${esc((c.jurisdicciones || []).join(" · "))}${c.cuencas && c.cuencas.length ? c.cuencas.length > 3 ? `<details><summary>Cuencas DPH (${c.cuencas.length})</summary>${esc(c.cuencas.join(" · "))}</details>` : `<br>Cuencas DPH: ${esc(c.cuencas.join(" · "))}` : ""}${c.fuentes ? `<br>Cartografía: ${esc(c.fuentes.map(x => ({dph:"DPH Buenos Aires",ign:"IGN",gcba:"GCBA",osm:"OpenStreetMap"}[x] || x)).join(" · "))}` : ""}${c.nota ? `<br>${esc(c.nota)}` : ""}</div>`;
  const TF = {hour: "2-digit", minute: "2-digit", hourCycle: "h23"};
  const hhmm = unix => new Date(unix * 1000).toLocaleTimeString("es-AR", TF);
  const fmtDT = iso => iso ? new Date(iso).toLocaleString("es-AR", {day: "2-digit", month: "2-digit", ...TF}) : "–";
  const windColor = s => s >= 70 ? "#8e44ad" : s >= 50 ? "#e74c3c" : s >= 30 ? "#f39c12" : s >= 15 ? "#2b8cbe" : "#7f8c9a";
  const toDir = from => (from + 180) % 360;
  const norm = s => String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const fmtDay = d => d ? `${new Date(d + "T12:00:00").toLocaleDateString("es-AR", {weekday: "short"}).replace(".", "")} ${+d.slice(8, 10)}/${+d.slice(5, 7)}` : "–";
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  const fmtDMY = d => d ? `${+d.slice(8, 10)}/${+d.slice(5, 7)}/${d.slice(0, 4)}` : "–";
  const RIVER = {RIODELAPLATA: "Río de la Plata", PARANADELASPALMAS: "Paraná de las Palmas", PARANAINF: "Paraná inferior",
                 PARANAGUAZU: "Paraná Guazú", PARANABRAVO: "Paraná Bravo", PARANAMINI: "Paraná Miní", LUJAN: "Luján",
                 CHANA: "Chaná", BARADERO: "Baradero", URUGUAY: "Uruguay", SALADO: "Salado"};
  const riverName = r => !r ? "" : RIVER[r] || (r === r.toUpperCase() ? r.charAt(0) + r.slice(1).toLowerCase() : r);
  const SOIL_COLOR = {"muy húmedo": "#1f4e9c", "húmedo": "#3a8fd6", adecuado: "#4caf50", seco: "#c9a227"};
  const kmTxt = c => c.km ? ` · ${c.km < 1 ? c.km.toFixed(2).replace(".", ",") : Math.round(c.km)} km de trazado` : "";
  const kindOf = tr => (tr.points.some(p => p.thunder) ? "Tormenta " : "Área de lluvia ") + INTENS[tr.level];
  const mobile = () => matchMedia("(max-width: 959px)").matches;
  // Pantalla completa: el detalle se muestra en un panel lateral en lugar del globo de Leaflet.
  const full = () => document.body.classList.contains("mapfull");
  const useSheet = () => mobile() || full();
  function eta(unix) {
    const h = (unix * 1000 - Date.now()) / 3.6e6;
    return h <= 0.5 ? "ahora" : h < 1.5 ? "en ~1 h" : `en ~${Math.round(h)} h`;
  }
  async function getJSON(url) {
    const r = await fetch(url, {cache: "no-store"});
    if (!r.ok) throw new Error(r.status + " " + url);
    return r.json();
  }
  function pip(lat, lon, ring) {
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const yi = ring[i][1], xi = ring[i][0], yj = ring[j][1], xj = ring[j][0];
      if ((yi > lat) !== (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }
  const inGeom = (lat, lon, g) => (g.type === "Polygon" ? [g.coordinates] : g.coordinates).some(p => pip(lat, lon, p[0]));
  const pipLatLon = (lat, lon, poly) => pip(lat, lon, poly.map(p => [p[1], p[0]]));

  // ------------------------------------------------------------------ mapa
  const map = L.map("map", {zoomControl: false, preferCanvas: true, minZoom: 3, maxZoom: 17, zoomSnap: 0.25});
  if (!L.Browser.mobile) L.control.zoom({position: "topright"}).addTo(map);
  // Mapa base: OpenStreetMap (sin clave). En producción conviene un proveedor de mapas contratado.
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);
  [["satPane", 250], ["radarPane", 300], ["provPane", 370], ["smnPane", 380], ["muniPane", 390], ["stormPane", 420]].forEach(([n, z]) => { map.createPane(n).style.zIndex = z; });
  // Imagen de hace ~1 hora (redondeada a 10 min): la más reciente suele no estar publicada todavía.
  const satTime = () => new Date(Math.floor((Date.now() - 60 * 60e3) / 600e3) * 600e3).toISOString().slice(0, 19) + "Z";
  const sat = L.tileLayer("https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/GOES-East_ABI_GeoColor/default/{time}/GoogleMapsCompatible_Level7/{z}/{y}/{x}.png",
    {pane: "satPane", time: satTime(), maxNativeZoom: 7, maxZoom: 11, opacity: 0.6, attribution: "Satélite: NASA GIBS · GOES-Este"});
  const G = {cuencas: L.layerGroup().addTo(map), cauces: L.layerGroup().addTo(map), hl: L.layerGroup().addTo(map), obs: L.layerGroup().addTo(map), rios: L.layerGroup().addTo(map), costa: L.layerGroup().addTo(map),
             prov: L.layerGroup().addTo(map), smn: L.layerGroup().addTo(map), muni: L.layerGroup().addTo(map), storms: L.layerGroup().addTo(map),
             arrows: L.layerGroup().addTo(map), wx: L.layerGroup().addTo(map), me: L.layerGroup().addTo(map)};

  /* Partículas de viento: líneas que avanzan con el viento interpolado. */
  const WindLayer = L.Layer.extend({
    onAdd(m) {
      this._m = m;
      this._c = L.DomUtil.create("canvas", "wind-canvas");
      m.getPanes().overlayPane.appendChild(this._c);
      m.on("movestart zoomstart", this._stop, this);
      m.on("moveend zoomend resize", this._reset, this);
      this._reset();
    },
    onRemove(m) {
      this._stop();
      this._c.remove();
      m.off("movestart zoomstart", this._stop, this);
      m.off("moveend zoomend resize", this._reset, this);
    },
    setField(f) { this._f = f; },
    _stop() {
      if (this._raf) cancelAnimationFrame(this._raf);
      this._raf = null;
      if (this._c) this._c.getContext("2d").clearRect(0, 0, this._c.width, this._c.height);
    },
    _reset() {
      const s = this._m.getSize(), dpr = Math.min(2, window.devicePixelRatio || 1), c = this._c;
      c.width = s.x * dpr; c.height = s.y * dpr; c.style.width = s.x + "px"; c.style.height = s.y + "px";
      L.DomUtil.setPosition(c, this._m.containerPointToLayerPoint([0, 0]));
      this._dpr = dpr;
      const n = Math.round(Math.min(900, Math.max(250, s.x * s.y / 1100)));
      this._p = Array.from({length: n}, () => this._rand());
      this._stop();
      const step = () => { this._draw(); this._raf = requestAnimationFrame(step); };
      this._raf = requestAnimationFrame(step);
    },
    _rand() {
      const b = this._m.getBounds();
      return {lat: b.getSouth() + Math.random() * (b.getNorth() - b.getSouth()),
              lon: b.getWest() + Math.random() * (b.getEast() - b.getWest()), age: Math.floor(Math.random() * 90)};
    },
    _draw() {
      const c = this._c, ctx = c.getContext("2d"), m = this._m, f = this._f, dpr = this._dpr;
      ctx.globalCompositeOperation = "destination-in";
      ctx.fillStyle = "rgba(0,0,0,0.9)";
      ctx.fillRect(0, 0, c.width, c.height);
      ctx.globalCompositeOperation = "source-over";
      if (!f) return;
      ctx.lineWidth = 1.3 * dpr;
      ctx.strokeStyle = DARK ? "rgba(225,238,255,0.75)" : "rgba(18,52,96,0.55)";
      const k = 0.00075 * Math.pow(2, 6 - m.getZoom());
      ctx.beginPath();
      for (const p of this._p) {
        const w = f(p.lat, p.lon);
        if (!w || p.age > 100) { Object.assign(p, this._rand(), {age: 0}); continue; }
        const a = m.latLngToContainerPoint([p.lat, p.lon]);
        p.lon += w[0] * k / Math.cos(p.lat * Math.PI / 180);
        p.lat += w[1] * k;
        p.age++;
        const z = m.latLngToContainerPoint([p.lat, p.lon]);
        ctx.moveTo(a.x * dpr, a.y * dpr);
        ctx.lineTo(z.x * dpr, z.y * dpr);
      }
      ctx.stroke();
    }
  });
  const wind = new WindLayer().addTo(map);

  const svgIcon = (id, size, cls) => L.divIcon({className: cls || "wx", iconSize: [size, size], iconAnchor: [size / 2, size / 2],
    html: `<svg width="${size}" height="${size}"><use href="#i-${id}"/></svg>`});

  // ------------------------------------------------------------------ datos en vivo (Open-Meteo)
  function omURL(grid, kind) {
    const lat = grid.points.map(p => p.lat.toFixed(2)).join(","), lon = grid.points.map(p => p.lon.toFixed(2)).join(",");
    const base = `${OM}?latitude=${lat}&longitude=${lon}&forecast_hours=12&timezone=UTC&timeformat=unixtime&wind_speed_unit=kmh`;
    return kind === "best"
      ? `${base}&hourly=temperature_2m,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m`
      : `${base}&hourly=precipitation,weather_code&models=${MODELS.join(",")}`;
  }

  async function loadLive(region, force) {
    const grid = S.grids[region], key = "argwx-live-v1-" + region, now = Date.now();
    let cache = null;
    try { cache = JSON.parse(localStorage.getItem(key) || "null"); } catch (e) { cache = null; }
    const okBest = !force && cache && now - cache.tb < 15 * 60e3, okModels = !force && cache && now - cache.tm < 60 * 60e3;
    try {
      const [best, models] = await Promise.all([okBest ? cache.best : getJSON(omURL(grid, "best")),
                                                okModels ? cache.models : getJSON(omURL(grid, "models"))]);
      const tb = okBest ? cache.tb : now, tm = okModels ? cache.tm : now;
      try { localStorage.setItem(key, JSON.stringify({best, models, tb, tm})); } catch (e) { /* sin espacio: se sigue sin caché */ }
      return {best, models, source: "live", at: tb};
    } catch (e) {
      try {
        const snap = await getJSON(`data/live_${region}.json`);
        return {best: snap.best, models: snap.models, source: "snapshot", at: Date.parse(snap.generated_at)};
      } catch (e2) {
        return {best: null, models: null, source: "none", at: null};
      }
    }
  }

  function prepare(region, live) {
    if (!live.best) return null;
    const grid = S.grids[region], locs = Array.isArray(live.best) ? live.best : [live.best];
    const times = locs[0].hourly.time, H = times.length, N = locs.length;
    const mk = () => Array.from({length: H}, () => new Array(N).fill(null));
    const B = {times, temp: mk(), p: mk(), c: mk(), ws: mk(), wd: mk(), g: mk()};
    locs.forEach((l, i) => {
      const h = l.hourly || {};
      for (let k = 0; k < H; k++) {
        B.temp[k][i] = h.temperature_2m ? h.temperature_2m[k] : null;
        B.p[k][i] = h.precipitation ? h.precipitation[k] : null;
        B.c[k][i] = h.weather_code ? h.weather_code[k] : null;
        B.ws[k][i] = h.wind_speed_10m ? h.wind_speed_10m[k] : null;
        B.wd[k][i] = h.wind_direction_10m ? h.wind_direction_10m[k] : null;
        B.g[k][i] = h.wind_gusts_10m ? h.wind_gusts_10m[k] : null;
      }
    });
    let tracks = [], nModels = 0;
    if (live.models) {
      const M = T.parseModels(live.models, MODELS);
      Object.values(M.models).forEach(m => { m.G = B.g; });  // ráfagas del modelo de mejor ajuste (menos consultas)
      nModels = Object.keys(M.models).length;
      if (nModels) tracks = T.track(grid, M, {nModels: MODELS.length});
    }
    tracks.forEach(t => {
      t.affected = region === "pba" ? T.affected(t, S.munis) : [];
      t.provincias = provincesAlong(t);
    });
    return {region, grid, B, H, tracks, nModels, source: live.source, at: live.at};
  }

  function provincesAlong(tr) {
    const out = [];
    for (const p of tr.points) {
      const pv = S.provs.find(f => inGeom(p.lat, p.lon, f.geometry));
      if (pv && !out.some(x => x.name === pv.properties.name)) out.push({name: pv.properties.name, t: p.t});
    }
    return out;
  }

  // ------------------------------------------------------------------ dibujo
  function drawSMN() {
    G.smn.clearLayers();
    if (!S.layers.smn || !S.st.smn) return;
    for (const a of S.st.smn.alerts) {
      a.polygons.forEach(poly => L.polygon(poly, {pane: "smnPane", color: a.color, weight: 1.5, fillColor: a.color, fillOpacity: 0.22})
        .bindPopup(`<div class="pop"><h3>${lvlBadge(a.level)} ${esc(a.title)}</h3><div class="muted">SMN · ${esc(a.provincias.join(", "))}</div>
          <div>Desde ${fmtDT(a.valid_from)} hasta ${fmtDT(a.valid_to)}</div>${a.partidos_pba.length ? `<div><b>Buenos Aires:</b> ${esc(a.partidos_pba.join(", "))}</div>` : ""}</div>`)
        .addTo(G.smn));
    }
  }

  function drawProvs() {
    G.prov.clearLayers();
    if (!S.st.prov) return;
    L.geoJSON(S.st.prov, {pane: "provPane", interactive: false,
      style: {color: DARK ? "#9fb3c8" : "#33475b", weight: S.region === "pba" ? 1 : 1.3, fill: false, opacity: 0.85}}).addTo(G.prov);
  }

  function drawMunis() {
    G.muni.clearLayers();
    if (S.region !== "pba" || !S.st.muniGeo) return;
    L.geoJSON(S.st.muniGeo, {pane: "muniPane", interactive: false,
      style: {color: DARK ? "#7d8fa1" : "#5b6b78", weight: 0.6, fill: false, opacity: 0.7}}).addTo(G.muni);
  }

  function storm(tr, h) {
    const col = COLOR[tr.level];
    L.polyline(tr.points.map(p => [p.lat, p.lon]), {pane: "stormPane", color: col, weight: 2.5, dashArray: "6 7", opacity: 0.9, interactive: false}).addTo(G.storms);
    const last = tr.points[tr.points.length - 1].h;
    tr.points.forEach(p => {
      const now = p.h === h, c = COLOR[LV[p.level]];
      if (!now && (p.h < h || ((p.h - h) % 3 !== 0 && p.h !== last))) return;
      L.circle([p.lat, p.lon], {pane: "stormPane", radius: p.radius * 1000, color: c, weight: now ? 2.5 : 1,
        opacity: now ? 0.95 : 0.45, fillColor: c, fillOpacity: now ? 0.14 + 0.3 * p.prob : 0.03 + 0.08 * p.prob, interactive: now})
        .bindPopup(() => trackHTML(tr, true)).addTo(G.storms);
    });
    tr.points.filter(p => p.h > h && (p.h - h) % 3 === 0).forEach(p =>
      L.marker([p.lat, p.lon + (p.radius / 111.2) / Math.cos(p.lat * Math.PI / 180)], {interactive: false,
        icon: L.divIcon({className: "hlbl", html: `+${p.h - h} h`, iconSize: [38, 16], iconAnchor: [19, 8]})}).addTo(G.storms));
    const cur = tr.points.find(p => p.h === h);
    if (!cur) return;
    L.marker([cur.lat, cur.lon], {icon: svgIcon(cur.thunder ? "storm" : "heavy", 46, "wx storm-ico"), zIndexOffset: 900})
      .bindPopup(() => trackHTML(tr, true)).addTo(G.storms);
    if (tr.dir != null) {
      const d = cur.radius / 111.2, rad = tr.dir * Math.PI / 180;
      const at = [cur.lat + d * Math.cos(rad), cur.lon + d * Math.sin(rad) / Math.cos(cur.lat * Math.PI / 180)];
      L.marker(at, {interactive: false, zIndexOffset: 800, icon: L.divIcon({className: "dir-ico", iconSize: [34, 34], iconAnchor: [17, 17],
        html: `<svg width="34" height="34" style="--rot:${tr.dir}deg;--c:${col}"><use href="#i-dir"/></svg>`})}).addTo(G.storms);
    }
  }

  function draw() {
    const D = S.cur;
    G.arrows.clearLayers(); G.wx.clearLayers(); G.storms.clearLayers();
    if (!D) { wind.setField(null); return; }
    const h = Math.min(S.hour, D.H - 1), sa = stride(D, 44), si = stride(D, 34), RANK = {storm: 3, heavy: 2, light: 1};
    const best = {};
    D.grid.points.forEach((pt, i) => {
      const cond = S.layers.wx ? T.condition(D.B.p[h][i], D.B.c[h][i]) : null;
      if (!cond) return;
      const k = Math.floor(pt.r / si) + "_" + Math.floor(pt.c / si);
      if (!best[k] || RANK[cond] > RANK[best[k].cond]) best[k] = {pt, cond};
    });
    Object.values(best).forEach(({pt, cond}) =>
      L.marker([pt.lat, pt.lon], {interactive: false, keyboard: false, icon: svgIcon(cond, cond === "light" ? 24 : 30)}).addTo(G.wx));
    D.grid.points.forEach((pt, i) => {
      const ws = D.B.ws[h][i], wd = D.B.wd[h][i];
      if (S.layers.wind && ws != null && wd != null && pt.r % sa === 0 && pt.c % sa === 0) {
        const dur = Math.max(0.7, Math.min(2.8, 2.8 - ws / 25)).toFixed(2);
        L.marker([pt.lat, pt.lon], {interactive: false, keyboard: false, icon: L.divIcon({className: "wa", iconSize: [22, 22], iconAnchor: [11, 11],
          html: `<svg width="22" height="22" style="--rot:${toDir(wd)}deg;--c:${windColor(ws)};--dur:${dur}s"><use href="#i-arrow"/></svg>`})}).addTo(G.arrows);
      }
    });
    wind.setField(S.layers.wind ? T.windField(D.grid, D.B.ws[h], D.B.wd[h]) : null);
    if (S.layers.storms) D.tracks.forEach(tr => storm(tr, h));
    $("hour-lbl").innerHTML = h === 0 ? `Ahora<br><span class="muted">${hhmm(D.B.times[0])}</span>` : `+${h} h<br><span class="muted">${hhmm(D.B.times[h])}</span>`;
    $("hour").max = D.H - 1;
  }

  /* Cada cuántos puntos de la grilla dibujar para que no se encimen (mínimo minPx píxeles). */
  function stride(D, minPx) {
    const sp = D.grid.spec, a = map.latLngToContainerPoint([sp.latN, sp.lonW]), b = map.latLngToContainerPoint([sp.latN, sp.lonW + sp.step]);
    return Math.max(1, Math.ceil(minPx / Math.max(1, Math.abs(b.x - a.x))));
  }
  map.on("zoomend", () => draw());

  // ------------------------------------------------------------------ radar, estaciones, ríos y costa
  const radar = {layer: null, time: null};
  async function loadRadar() {
    try {
      const wm = await getJSON("https://api.rainviewer.com/public/weather-maps.json");
      const f = wm.radar && wm.radar.past && wm.radar.past[wm.radar.past.length - 1];
      if (!f) return;
      if (radar.layer) map.removeLayer(radar.layer);
      radar.layer = L.tileLayer(`${wm.host}${f.path}/256/{z}/{x}/{y}/2/1_1.png`, {pane: "radarPane", opacity: 0.75,
        maxNativeZoom: 7, maxZoom: 11, attribution: 'Radar: <a href="https://www.rainviewer.com/">RainViewer</a>'});
      radar.time = f.time;
      if (S.layers.radar) radar.layer.addTo(map);
      const el = $("radar-time");
      if (el) el.textContent = `Radar: ${hhmm(f.time)}`;
    } catch (e) { /* sin radar: el resto sigue funcionando */ }
  }

  const tempColor = t => t == null ? "#7f8c9a" : t >= 35 ? "#b2182b" : t >= 28 ? "#e66101" : t >= 20 ? "#f4a50c" : t >= 12 ? "#1a9850" : t >= 5 ? "#2b8cbe" : "#5e3c99";
  function nearestStation(lat, lon, maxKm) {
    const list = S.st.obs ? S.st.obs.estaciones : [];
    let best = null, bd = Infinity;
    list.forEach(o => { const d = T.hav(lat, lon, o.lat, o.lon); if (d < bd) { bd = d; best = o; } });
    return bd <= maxKm ? best : null;
  }

  function sparkline(series, ref) {
    const q = (series.q || []).map(v => v == null ? null : v), vals = q.filter(v => v != null);
    if (vals.length < 2) return "";
    const W = 240, H = 60, max = Math.max(...vals, ref.p98 || 0) * 1.05, x = i => (i / (q.length - 1)) * W, y = v => H - 3 - (v / max) * (H - 6);
    const pts = q.map((v, i) => v == null ? null : `${x(i).toFixed(1)},${y(v).toFixed(1)}`).filter(Boolean).join(" ");
    return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="display:block;margin-top:6px">
      <line x1="0" x2="${W}" y1="${y(ref.p90)}" y2="${y(ref.p90)}" stroke="#f2c200" stroke-dasharray="3 3"/>
      <line x1="0" x2="${W}" y1="${y(ref.p98)}" y2="${y(ref.p98)}" stroke="#f07c00" stroke-dasharray="3 3"/>
      <polyline points="${pts}" fill="none" stroke="#1e88e5" stroke-width="2"/></svg>
      <div class="muted">Caudal esperado (mediana) próximos 30 días. Línea amarilla: alto (p90). Naranja: muy alto (p98).</div>`;
  }

  const MN = id => (S.munis.find(m => m.id === id) || {}).name || id;

  function courseHTML(c) {
    const green = !hydroHot(c), pa = green ? c.partidos : c.partidos_afectados;
    const locs = (green ? c.localidades : c.localidades_afectadas).slice(0, 12);
    return `<div class="pop"><h3>💧 ${esc(c.nombre)}</h3><div class="muted">${esc(c.tipo)}${kmTxt(c)} · ${c.monitoreo === "costero" ? "alturas observadas" : "próximos 3 días"}</div>
      <div class="row"><span>Evaluación orientativa</span>${lvlBadge(c.nivel)}</div>${hydroContext(c)}
      ${c.pico ? `<div class="row"><span>Pico estimado (GloFAS)</span><b>${fmtDay(c.pico)}</b></div>` : ""}
      <ul class="mot">${c.motivos.map(m => `<li>${esc(m)}</li>`).join("")}
      ${!green && c.partidos_senal.length ? `<li>Señal más fuerte en <b>${c.partidos_senal.slice(0, 4).map(p => esc(MN(p))).join(", ")}</b></li>` : ""}</ul>
      <div class="muted" style="margin-top:6px">${green ? "Partidos que cruza" : "Partidos sobre el curso que podrían verse afectados"}:</div>
      <div class="pl">${pa.slice(0, 16).map(p => `<span>${esc(MN(p))}</span>`).join("")}${pa.length > 16 ? `<span>+${pa.length - 16}</span>` : ""}</div>
      ${locs.length ? `<div class="muted" style="margin-top:6px">Localidades a menos de 4 km del cauce:</div><div class="pl">${locs.map(l => `<span>${esc(l[0])}</span>`).join("")}</div>` : ""}</div>`;
  }

  function gaugeHTML(st) {
    const num = v => v == null ? "–" : `${v.toFixed(2).replace(".", ",")} m`;
    return `<div class="pop"><h3>📏 ${esc(st.estacion)}</h3><div class="muted">${esc(riverName(st.rio))} · ${esc(st.red || "")} · altura observada</div>
      <div class="row"><span>Estado</span>${st.nivel === "GREEN" ? `<b>${esc(st.estado)}</b>` : lvlBadge(st.nivel) + " " + esc(st.estado)}</div>
      <div class="row"><span>Altura</span><b>${num(st.altura_m)}</b></div>
      <div class="row"><span>Cambio en 24 h</span><b>${st.cambio_24h == null ? "–" : (st.cambio_24h > 0 ? "+" : "") + num(st.cambio_24h)}</b></div>
      <div class="row"><span>Nivel de alerta</span><b>${num(st.alerta)}</b></div>
      <div class="row"><span>Nivel de evacuación</span><b>${num(st.evacuacion)}</b></div>
      <div class="row"><span>Medición</span><b>${fmtDT(st.fecha)}</b></div>${heightChart(st)}</div>`;
  }

  function heightChart(st) {
    const pts = (st.serie_30d || []).map(x => x[1]);
    if (pts.length < 2) return "";
    const W = 240, H = 64, lim = [st.alerta, st.evacuacion].filter(v => v != null);
    const lo = Math.min(...pts), hi = Math.max(...pts, ...lim), pad = (hi - lo) * 0.1 || 0.1;
    const y = v => H - 3 - ((v - lo + pad) / (hi - lo + 2 * pad)) * (H - 6), x = i => (i / (pts.length - 1)) * W;
    const line = (v, c) => v == null ? "" : `<line x1="0" x2="${W}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}" stroke="${c}" stroke-dasharray="3 3"/>`;
    return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="display:block;margin-top:6px">${line(st.alerta, "#f07c00")}${line(st.evacuacion, "#d62828")}
      <polyline points="${pts.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ")}" fill="none" stroke="#1e88e5" stroke-width="2"/></svg>
      <div class="muted">Últimos 30 días. Naranja: alerta. Roja: evacuación (niveles oficiales de la escala).</div>`;
  }

  function drawCourse(c, group, hl) {
    const col = hydroHot(c) ? COLOR[c.nivel] : c.nivel ? "#1e88e5" : "#667788";
    if (hl || hydroHot(c)) L.polyline(c.trazo, {color: "#fff", weight: hl ? 10 : 7, opacity: 0.8, interactive: false}).addTo(group);
    L.polyline(c.trazo, {color: col, weight: hl ? 6 : hydroHot(c) ? 4 : 2, opacity: hl ? 1 : 0.8,
      dashArray: !c.nivel ? "5 4" : null, bubblingMouseEvents: false})
      .bindPopup(() => courseHTML(c), {maxWidth: 300}).addTo(group);
  }

  function drawExtras() {
    G.obs.clearLayers(); G.rios.clearLayers(); G.costa.clearLayers(); G.cauces.clearLayers(); G.cuencas.clearLayers();
    const visible = bb => map.getBounds().intersects([[bb[0], bb[1]], [bb[2], bb[3]]]);
    if ((S.layers.rios || S.layers.red) && S.st.crec) S.st.crec.cursos.filter(c => visible(c.bbox) &&
      ((S.layers.rios && hydroHot(c)) || (S.layers.red && (map.getZoom() >= 8 || ["río", "estuario"].includes(c.tipo)))))
      .forEach(c => drawCourse(c, G.cauces, false));
    if (S.layers.cuencas && S.st.cuencas) L.geoJSON(S.st.cuencas, {
      style: {color: "#3c7f98", weight: 1.5, fillOpacity: 0.06},
      onEachFeature: (f, layer) => layer.bindPopup(`<div class="pop"><h3>${esc(f.properties.nombre)}</h3><p>Cuenca cartográfica DPH. No representa una zona inundable.</p><a href="https://www.gba.gob.ar/hidraulica/cuencas_hidricas/mapa" target="_blank" rel="noopener">Fuente oficial</a></div>`)
    }).addTo(G.cuencas);
    if (S.layers.rios && S.st.obsRios) S.st.obsRios.estaciones.forEach(st => {
      L.marker([st.lat, st.lon], {icon: L.divIcon({className: "esc", iconSize: [64, 22], iconAnchor: [32, 11],
        html: `<span style="border-color:${COLOR[st.nivel]}">📏 ${st.altura_m.toFixed(2).replace(".", ",")} m</span>`})})
        .bindPopup(() => gaugeHTML(st), {maxWidth: 300}).addTo(G.rios);
    });
    if (S.layers.obs && S.st.obs) S.st.obs.estaciones.forEach(o => {
      const storm = /tormenta|granizo/i.test(o.estado);
      L.marker([o.lat, o.lon], {icon: L.divIcon({className: "obs", iconSize: [40, 20], iconAnchor: [20, 10],
        html: `<span style="background:${tempColor(o.temp_c)}">${storm ? "⛈️ " : ""}${o.temp_c == null ? "–" : Math.round(o.temp_c) + "°"}</span>`})})
        .bindPopup(`<div class="pop"><h3>🌡️ ${esc(o.estacion)}</h3><div class="muted">SMN · ${esc(o.fecha)} ${esc(o.hora)} (hora argentina)</div>
          <div class="row"><span>Estado</span><b>${esc(o.estado)}</b></div><div class="row"><span>Temperatura</span><b>${o.temp_c ?? "–"} °C</b></div>
          <div class="row"><span>Humedad</span><b>${o.humedad ?? "–"} %</b></div><div class="row"><span>Viento</span><b>${esc(o.viento_dir || "")} ${o.viento_kmh ?? ""} km/h</b></div>
          <div class="row"><span>Presión</span><b>${o.presion_hpa ?? "–"} hPa</b></div><div class="row"><span>Visibilidad</span><b>${esc(o.visibilidad)}</b></div></div>`)
        .addTo(G.obs);
    });
    if (S.layers.rios && S.st.rios) S.st.rios.rios.forEach(r => {
      L.marker([r.lat, r.lon], {icon: L.divIcon({className: "rio", iconSize: [30, 30], iconAnchor: [15, 15],
        html: `<span style="background:${COLOR[r.nivel_7d]}">💧</span>`})})
        .bindPopup(`<div class="pop"><h3>💧 Río ${esc(r.rio)}</h3><div class="muted">${esc(r.lugar)} · GloFAS (Copernicus)</div>
          <div class="row"><span>Próx. 7 días</span>${lvlBadge(r.nivel_7d)}</div><div class="row"><span>Próx. 30 días</span>${lvlBadge(r.nivel_30d)}</div>
          <div class="row"><span>Caudal hoy</span><b>${r.caudal_hoy == null ? "–" : Math.round(r.caudal_hoy) + " m³/s"}</b></div>
          <div class="row"><span>Máximo 7 días</span><b>${r.max_7d == null ? "–" : Math.round(r.max_7d) + " m³/s"}</b></div>
          <div class="row"><span>Tendencia</span><b>${esc(r.tendencia || "–")}</b></div>
          <div class="row"><span>Peor escenario 30 días</span><b>${r.peor_escenario_30d == null ? "–" : Math.round(r.peor_escenario_30d) + " m³/s"}</b></div>${sparkline(r.serie, r.ref)}</div>`, {maxWidth: 280})
        .addTo(G.rios);
    });
    if (S.layers.costa && S.st.costa) S.st.costa.puntos.forEach(p => {
      L.marker([p.lat, p.lon], {icon: L.divIcon({className: "costa", iconSize: [58, 22], iconAnchor: [29, 11],
        html: `<span style="border-color:${COLOR[p.nivel]}">🌊 ${p.ola_max_24h == null ? "–" : p.ola_max_24h.toFixed(1) + " m"}</span>`})})
        .bindPopup(`<div class="pop"><h3>🌊 ${esc(p.lugar)}</h3><div class="muted">Olas · Open-Meteo Marine</div>
          <div class="row"><span>Ahora</span><b>${p.ola_ahora ?? "–"} m</b></div><div class="row"><span>Máx. 24 h</span><b>${p.ola_max_24h ?? "–"} m</b></div>
          <div class="row"><span>Máx. 72 h</span><b>${p.ola_max_72h ?? "–"} m${p.hora_max ? " (" + fmtDT(new Date(p.hora_max * 1000).toISOString()) + ")" : ""}</b></div>
          <div class="row"><span>Período</span><b>${p.periodo ?? "–"} s</b></div><div class="row"><span>Nivel</span>${lvlBadge(p.nivel)}</div></div>`)
        .addTo(G.costa);
    });
  }

  function extrasCards() {
    const o = S.st.obs, rios = S.st.rios, costa = S.st.costa, amb = S.st.ambiente, pr = S.st.probs;
    if (o) {
      const pba = o.estaciones.filter(x => x.municipio), storms = o.estaciones.filter(x => /tormenta|granizo/i.test(x.estado));
      const hot = [...pba].filter(x => x.temp_c != null).sort((a, b) => b.temp_c - a.temp_c);
      $("obs-card").innerHTML = `<h2>🌡️ Observado ahora (estaciones del SMN)</h2>
        <p>${o.estaciones.length} estaciones informando en el país, ${pba.length} en Buenos Aires.
        ${storms.length ? `<b>Tormenta observada en:</b> ${esc(storms.map(x => x.municipio ? x.estacion : `${x.estacion} (${x.provincia.charAt(0) + x.provincia.slice(1).toLowerCase()})`).join(", "))}.` : "Ninguna estación informa tormenta en este momento."}</p>
        ${hot.length ? `<p class="muted">Más cálido en PBA: ${esc(hot[0].estacion)} ${hot[0].temp_c} °C · más fresco: ${esc(hot[hot.length - 1].estacion)} ${hot[hot.length - 1].temp_c} °C.</p>` : ""}
        <p class="muted">Las observaciones de tormenta o granizo elevan la alerta del municipio: la observación prevalece sobre el modelo. Prendé "🌡️ Estaciones" para verlas en el mapa.</p>`;
    }
    if (rios) $("rios-card").innerHTML = `<h2>💧 Ríos principales (puntos de referencia GloFAS)</h2><ul class="plain">${rios.rios.map(r => `<li><div>${lvlBadge(r.nivel_7d)} <b>${esc(r.rio)}</b> · ${esc(r.lugar)}</div>
        <div class="muted">${esc(r.estado_7d)} próximos 7 días${r.tendencia ? ", " + esc(r.tendencia) : ""} · 30 días: ${esc(r.estado_30d)}</div></li>`).join("")}</ul>
        <p class="muted">${esc(rios.metodo)} Fuente: ${esc(rios.fuente)}.</p>
        <button class="lnk" data-tab="crec">Ver crecidas de todos los ríos, arroyos y canales →</button>`;
    if (costa) $("costa-card").innerHTML = `<h2>🌊 Costa atlántica (olas)</h2><ul class="plain">${costa.puntos.map(p => `<li class="row"><span>${esc(p.lugar)}</span>
        <span>${lvlBadge(p.nivel)} <b>${p.ola_max_24h == null ? "–" : p.ola_max_24h.toFixed(1) + " m"}</b></span></li>`).join("")}</ul>
        <p class="muted">Altura máxima de olas en las próximas 24 h. Umbrales iniciales: 2,5 m amarilla, 3,5 m naranja, 5 m roja. Prendé "🌊 Costa" para verlas en el mapa.</p>`;
    if (amb) {
      const rows = Object.entries(amb.municipios).filter(([, v]) => v.uv_max != null), name = id => (S.munis.find(m => m.id === id) || {}).name || id;
      const uv = rows.sort((a, b) => b[1].uv_max - a[1].uv_max), pm = [...rows].filter(([, v]) => v.pm25_max != null).sort((a, b) => b[1].pm25_max - a[1].pm25_max);
      $("amb-card").innerHTML = `<h2>☀️ Ambiente (UV y aire)</h2>
        ${uv.length ? `<p>UV máximo hoy: <b>${uv[0][1].uv_max}</b> (${esc(uv[0][1].uv_categoria)}) en ${esc(name(uv[0][0]))}.</p>` : ""}
        ${pm.length ? `<p>PM2.5 máximo: <b>${pm[0][1].pm25_max} µg/m³</b> en ${esc(name(pm[0][0]))}${pm[0][1].pm25_max > 15 ? " (sobre la guía diaria de la OMS)" : ""}.</p>` : ""}
        <p class="muted">${esc(amb.nota)} Fuente: ${esc(amb.fuente)}. Tocá un municipio en el mapa para ver su valor.</p>`;
    }
    if (pr) $("prob-card").innerHTML = `<h2>🎲 Probabilidad de lluvia (51 escenarios ECMWF)</h2>
      <table class="heat"><tr><th>Zona</th><th>≥10 mm<br><small>24 h</small></th><th>≥30 mm<br><small>24 h</small></th><th>≥10 mm<br><small>24-48 h</small></th><th>≥30 mm<br><small>24-48 h</small></th></tr>
      ${pr.puntos.map(p => { const a = p.ventanas["24"] || {}, b = p.ventanas["48"] || {}, c = v => v == null ? "–" : Math.round(v * 100) + " %";
        return `<tr><td style="text-align:left">${esc(p.name)}</td><td>${c(a.p_10mm)}</td><td>${c(a.p_30mm)}</td><td>${c(b.p_10mm)}</td><td>${c(b.p_30mm)}</td></tr>`; }).join("")}</table>
      <p class="muted">${esc(pr.nota)}</p>`;
    const t = Math.floor(Date.now() / 600e3);
    $("sat-card").innerHTML = `<h2>🛰️ Satélite GOES-19 · Sudamérica sur</h2>
      <a href="https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/GEOCOLOR/1800x1080.jpg" target="_blank" rel="noopener">
      <img src="https://cdn.star.nesdis.noaa.gov/GOES19/ABI/SECTOR/ssa/GEOCOLOR/900x540.jpg?t=${t}" alt="Imagen satelital GOES-19 del sur de Sudamérica" style="width:100%;border-radius:10px" loading="lazy"></a>
      <p class="muted">Imagen real de NOAA (GeoColor), se renueva cada 10 minutos. Tocala para verla en alta resolución. <span id="radar-time"></span></p>`;
  }

  // ------------------------------------------------------------------ paneles
  function trackHTML(tr, popup) {
    const cur = tr.points.find(p => p.h === S.hour) || tr.points[0];
    const places = S.region === "pba" ? tr.affected : tr.provincias;
    const list = places.slice(0, popup ? 14 : 24).map(x => `<span><b>${esc(x.name)}</b> ${eta(x.t)}</span>`).join("");
    const html = `<div class="trk-h">${lvlBadge(tr.level)} <b>${kindOf(tr)}</b>
        <span class="muted">${Math.round(tr.probMax * 5)} de 5 modelos (${Math.round(tr.probMax * 100)} %)</span></div>
      <div class="trk-m">🧭 ${esc(tr.dirText)}${tr.speed ? ` a ${tr.speed} km/h` : ""} · ${tr.trend === "se intensifica" ? "📈" : tr.trend === "se debilita" ? "📉" : "➖"} ${esc(tr.trend)}
        <span class="muted">· entre ${hhmm(tr.start)} y ${hhmm(tr.end)} · ahora: ${Math.round(cur.radius)} km de radio</span></div>
      ${places.length ? `<div class="muted">Pasaría por${S.region === "pba" ? "" : " (provincias argentinas)"}:</div><div class="pl">${list}${places.length > 24 ? `<span>+${places.length - 24} más</span>` : ""}</div>`
        : `<div class="muted">No toca ${S.region === "pba" ? "municipios bonaerenses" : "provincias argentinas"} en las próximas horas.</div>`}`;
    return popup ? `<div class="pop">${html}</div>` : html;
  }

  function setMini(text, cls) {
    $("mini-txt").textContent = text;
    $("pulse2").className = cls;
  }

  function panels() {
    const D = S.cur;
    const txt = $("live-txt"), pulse = $("pulse");
    if (!D) {
      pulse.className = "pulse off"; txt.textContent = "Sin datos"; setMini("Sin datos", "pulse off");
      $("now-card").innerHTML = `<h2>Ahora</h2><p>No se pudieron obtener datos. Probá de nuevo en unos minutos.</p>`;
      $("tracks").innerHTML = "";
      return;
    }
    pulse.className = "pulse" + (D.source === "live" ? "" : " snap");
    txt.textContent = `${D.source === "live" ? "En vivo" : "Copia del servidor"} · ${new Date(D.at).toLocaleTimeString("es-AR", TF)}`;
    setMini(`${D.source === "live" ? "En vivo" : "Copia"} ${new Date(D.at).toLocaleTimeString("es-AR", TF)}`, pulse.className);
    const n = D.tracks.length, top = D.tracks[0];
    const smnStorm = S.st.smn ? S.st.smn.alerts.filter(a => a.storm) : [];
    const pbaSMN = smnStorm.filter(a => a.partidos_pba.length);
    let lead;
    if (top) {
      const first = (S.region === "pba" ? top.affected : top.provincias)[0];
      lead = `⛈️ <b>${n} ${n === 1 ? "tormenta" : "tormentas"} en seguimiento</b> en las próximas ${D.H} horas. La principal es ${INTENS[top.level]} (${Math.round(top.probMax * 5)} de 5 modelos), se mueve ${esc(top.dirText)}${top.speed ? ` a ${top.speed} km/h` : ""} y ${esc(top.trend)}${first ? `; llegaría a <b>${esc(first.name)}</b> ${eta(first.t)}` : ""}.`;
    } else {
      lead = `✅ Sin tormentas organizadas en ${{pba: "la provincia", ar: "el país", sa: "Sudamérica"}[S.region]} en las próximas ${D.H} horas, según el consenso de ${D.nModels || 5} modelos.`;
    }
    $("now-card").innerHTML = `<h2>Ahora en ${{pba: "Buenos Aires", ar: "la Argentina", sa: "Sudamérica"}[S.region]}</h2><p class="big">${lead}</p>
      <p class="muted">⚠️ SMN: ${smnStorm.length} alertas por tormentas vigentes en el país${S.region === "pba" ? `, ${pbaSMN.length} sobre partidos bonaerenses` : ""}.
      ${D.source === "live" ? "Datos de modelos actualizados cada 15 minutos." : "No se pudo consultar en vivo: se muestra la última copia guardada por el servidor."}</p>`;
    $("tracks").innerHTML = n ? D.tracks.map((tr, i) => `<div class="trk" data-i="${i}" style="--c:${COLOR[tr.level]}">${trackHTML(tr, false)}</div>`).join("")
      : `<p class="muted">No hay tormentas organizadas a la vista. Igual conviene revisar las alertas del SMN.</p>`;
  }

  function alertsTab() {
    const all = S.st.smn ? S.st.smn.alerts : [], list = all.filter(a => S.smnFilter === "all" || a.storm);
    $("smn-src").textContent = S.st.smn ? `API oficial del SMN (formato CAP) · ${all.length} alertas vigentes en el país · leídas el ${fmtDT(S.st.smn.generated_at)}` : "";
    $("smn-list").innerHTML = list.length ? list.map(a => `<li><div>${lvlBadge(a.level)} <b>${esc(a.title)}</b></div>
      <div class="muted">${esc(a.provincias.join(", ") || "Área sin provincia identificada")} · desde ${fmtDT(a.valid_from)} hasta ${fmtDT(a.valid_to)}</div>
      ${a.partidos_pba.length ? `<div class="muted"><b>Buenos Aires:</b> ${esc(a.partidos_pba.join(", "))}</div>` : ""}</li>`).join("")
      : `<li class="muted">${S.st.smn ? "No hay alertas vigentes para este filtro." : "No se pudieron leer las alertas del SMN."}</li>`;
    const win = S.st.pba && S.st.pba.windows[S.pwin];
    const alerted = win ? win.municipios.filter(m => m.alert_level !== "GREEN").sort((a, b) => LV.indexOf(b.alert_level) - LV.indexOf(a.alert_level)) : [];
    $("pba-info").textContent = win ? `${win.label} · ${135 - alerted.length} municipios en verde · consenso de ${(S.st.pba.models || []).length} modelos (${(S.st.pba.models || []).join(", ")}) + observaciones del SMN` : "Sin datos.";
    $("pba-list").innerHTML = alerted.length ? alerted.map(m => `<li><div>${lvlBadge(m.alert_level)} <b>${esc(m.name)}</b> <span class="muted">${esc(m.hazard || "")} · confianza ${esc(m.confidence_label)}</span></div><div class="muted">${esc(m.drivers[0] || "")}</div>${probLine(m.prob_lluvia, "30")}${weightedLine(m)}</li>`).join("")
      : `<li class="muted">Ningún municipio en alerta en esta ventana.</li>`;
    // Probabilidad calibrada: los partidos con más chance de lluvia importante en la ventana elegida
    const withP = win ? win.municipios.filter(m => m.prob_lluvia && m.prob_lluvia["10"] && m.prob_lluvia["10"].probabilidad != null) : [];
    const rank = t => withP.filter(m => m.prob_lluvia[t].k > 0 && m.prob_lluvia[t].probabilidad != null)
      .sort((a, b) => b.prob_lluvia[t].probabilidad - a.prob_lluvia[t].probabilidad || b.prob_lluvia[t].k - a.prob_lluvia[t].k);
    const top30 = rank("30"), top10 = rank("10"), t = top30.length ? "30" : "10", top = (top30.length ? top30 : top10).slice(0, 8);
    $("pba-prob").innerHTML = !withP.length ? `<p class="muted">La probabilidad calibrada aparece cuando la base histórica tiene suficientes pares pronóstico-observación.</p>`
      : top.length ? `<p class="muted">Lluvia de ${t} mm o más en la ventana elegida: frecuencia con que ocurrió en el último año cuando una proporción parecida de modelos lo pronosticó.</p>
        <ul class="plain">${top.map(m => `<li class="row"><span><b>${esc(m.name)}</b> <span class="muted">· ${m.prob_lluvia[t].k} de ${m.prob_lluvia[t].n} modelos</span></span><b>${probTxt(m.prob_lluvia[t])}</b></li>`).join("")}</ul>`
      : `<p class="muted">Ningún modelo pronostica 10 mm o más en ningún partido para esta ventana.</p>`;
  }

  // Modelo ponderado ARGWX (en evaluación): pesa cada modelo según cuánto acertó la lluvia en el último año.
  function weightedLine(m) {
    const w = m && m.ponderado;
    if (!w) return "";
    return `<div class="muted">⚖️ ARGWX ponderado (en evaluación): ${w.lluvia_mm} mm · ${lvlBadge(w.nivel)}${w.difiere ? " · difiere del consenso" : ""}</div>`;
  }
  function weightedRow(m) {
    const w = m && m.ponderado;
    if (!w) return "";
    const tops = (w.modelos_principales || []).map(x => `${esc(x.modelo)} ${Math.round(x.peso * 100)} %`).join(", ");
    return `<div class="row"><span>⚖️ ARGWX ponderado 24 h <span class="muted">(en evaluación)</span></span><span>${w.lluvia_mm} mm ${lvlBadge(w.nivel)}</span></div>
      ${tops ? `<div class="muted">Pesan más: ${tops}</div>` : ""}`;
  }

  function probTxt(p) {
    if (!p || p.probabilidad == null) return "–";
    const v = p.probabilidad > 0 && p.probabilidad < 1 ? "menos de 1" : Math.round(p.probabilidad);
    return `${v} %${p.confiable ? "" : " (pocos casos)"}`;
  }

  function probLine(pr, t) {
    const p = pr && pr[t];
    if (!p || p.probabilidad == null) return "";
    return `<div class="muted">🎯 Lluvia ≥ ${t} mm: ${probTxt(p)} · ${p.k} de ${p.n} modelos · calibrado con ${p.casos} casos</div>`;
  }

  const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
  function probRows(id) {
    const win = S.st.pba && S.st.pba.windows["24"], m = win && win.municipios.find(x => x.id === id);
    const mu = S.munis.find(x => x.id === id), cl = S.st.clima;
    const month = new Date().getMonth() + 1, pid = cl && mu ? cl.por_seccion[String(mu.seccion)] : null;
    const c = pid && cl.puntos[pid] ? cl.puntos[pid][String(month)] : null;
    let html = "";
    ["30", "10"].forEach(t => {
      const p = m && m.prob_lluvia && m.prob_lluvia[t];
      if (p && p.probabilidad != null && (t === "30" || !html)) html += `<div class="row"><span>🎯 Lluvia ≥ ${t} mm en 24 h (calibrada)</span><b>${probTxt(p)}</b></div>`;
    });
    if (c && c.p24) html += `<div class="row"><span>📅 Normal de ${MONTHS[month - 1]}: ≥ 30 mm en un día</span><b>${String(c.p24["30"]).replace(".", ",")} % de los días</b></div>`;
    return html;
  }

  // ------------------------------------------------------------------ base histórica y verificación
  function histCards() {
    const cb = S.st.calib, cat = S.st.catalogo;
    if (cb && cb.verificacion) {
      const rows = Object.entries(cb.verificacion).map(([mod, v]) => ({mod, v: v["1"]})).filter(r => r.v)
        .map(r => ({...r, u: r.v.umbrales["20"]})).sort((a, b) => (b.u.csi || 0) - (a.u.csi || 0));
      const pct = x => x == null ? "–" : Math.round(x * 100) + " %";
      const rel = ((cb.calibracion.tabla["30"] || {})["1"] || []);
      const BIN = ["ningún modelo", "hasta 1 de cada 4", "entre 1 de cada 4 y la mitad", "más de la mitad", "más de 3 de cada 4"];
      $("verif-card").innerHTML = `<h2>📊 ¿Qué tan bien aciertan los modelos?</h2>
        <p class="muted">Lluvia pronosticada con 1 día de anticipación frente a la observada (ERA5) del ${fmtDMY(cb.periodo[0])} al ${fmtDMY(cb.periodo[1])}, en 8 puntos de la provincia (${cb.dias} días).</p>
        <table class="vt"><tr><th>Modelo</th><th>Detecta ≥ 20 mm</th><th>Falsas alarmas</th><th>Error medio</th></tr>
        ${rows.map(r => `<tr><td>${esc(r.mod)}</td><td>${pct(r.u.pod)}</td><td>${pct(r.u.far)}</td><td>${r.v.mae} mm</td></tr>`).join("")}</table>
        ${rel.length ? `<p style="margin-top:10px"><b>Probabilidad calibrada (≥ 30 mm, 1 día):</b> cuando lo pronosticó…</p>
          <ul class="plain">${rel.map((b, i) => b.casos ? `<li class="row"><span>${BIN[i]}</span><b>${b.frecuencia} % <span class="muted">(${b.ocurrio} de ${b.casos} casos${b.confiable ? "" : ", pocos"})</span></b></li>` : "").join("")}</ul>` : ""}
        <p class="muted">${esc(cb.verdad)}. "Detecta": de los días que llovió 20 mm o más, cuántos pronosticó. "Falsas alarmas": de los días que pronosticó 20 mm o más, en cuántos no llovió eso.</p>`;
    } else $("verif-card").innerHTML = "";
    if (cat && cat.tablas) {
      $("hist-card").innerHTML = `<h2>🗄️ Base histórica (datos públicos)</h2>
        <ul class="plain">${cat.tablas.filter(t => t.archivos.length).map(t => `<li><div><b>${esc(t.descripcion)}</b></div>
          <div class="muted">${t.registros != null ? `${t.registros.toLocaleString("es-AR")} registros` : "resumen"}${t.desde ? ` · ${fmtDay(t.desde)} a ${fmtDay(t.hasta)}` : ""} · ${esc(t.fuente)}</div>
          <div>${t.archivos.map(f => `<a href="data/historico/${encodeURIComponent(f)}" download>${esc(f)}</a>`).join(" · ")}</div></li>`).join("")}</ul>
        <p class="muted">${esc(cat.nota)}</p>`;
    } else $("hist-card").innerHTML = "";
  }

  function divColor(v) {
    if (v == null) return "transparent";
    const t = Math.max(-1, Math.min(1, v / 40)), a = t < 0 ? [140, 81, 10] : [1, 102, 94], b = [245, 245, 245], m = Math.abs(t);
    return `rgb(${a.map((x, i) => Math.round(b[i] + (x - b[i]) * m)).join(",")})`;
  }
  const seasonEs = p => { const parts = String(p).split(" "); return `${SEAS[parts[0]] || parts[0]} ${parts[1] || ""}`.trim(); };

  function ensoTab() {
    const e = S.st.enso && S.st.enso.status, ep = S.st.ensoPba;
    if (e) {
      const w = e.weekly && e.weekly.NINO34;
      $("enso-now").innerHTML = `<h2>Estado actual</h2><div style="font-size:30px;font-weight:800;color:${PHASE_COLOR[e.phase]}">${PHASE[e.phase]}</div>
        <p>ONI <b>${e.oni}</b> en ${seasonEs(e.season)} · ${e.official_episode ? `episodio oficial (${e.consecutive_seasons} trimestres seguidos)` : `${e.consecutive_seasons} trimestre(s) en esta fase`}</p>
        ${w ? `<p class="muted">Niño 3.4 semanal: anomalía ${w.anomaly} °C (semana del ${w.week}).${e.soi ? ` SOI: ${e.soi.value} (${e.soi.month}).` : ""}</p>` : ""}
        <p><b>Para Buenos Aires:</b> ${esc(e.impact_buenos_aires ? e.impact_buenos_aires.tendencia : "")}</p>
        <p class="muted">${esc(e.impact_buenos_aires ? e.impact_buenos_aires.nota : "")}</p>`;
    } else {
      $("enso-now").innerHTML = `<h2>Estado actual</h2><p class="muted">No se pudo leer el ENSO.</p>`;
    }
    drawOni();
    if (!ep) { $("enso-sum").innerHTML = `<p class="muted">Cálculo histórico pendiente.</p>`; return; }
    const P = ep.provincia, ph = ["EL_NINO", "NEUTRAL", "LA_NINA"], r = ep.resumen || {};
    $("enso-sum").innerHTML = `<p>${r.nino_max ? `Con <b style="color:${PHASE_COLOR.EL_NINO}">El Niño</b>, la mayor diferencia fue en <b>${r.nino_max.estacion}</b>: ${r.nino_max.valor > 0 ? "+" : ""}${r.nino_max.valor} % de lluvia respecto de lo normal. ` : ""}${r.nina_min ? `Con <b style="color:${PHASE_COLOR.LA_NINA}">La Niña</b>, en <b>${r.nina_min.estacion}</b>: ${r.nina_min.valor > 0 ? "+" : ""}${r.nina_min.valor} %.` : ""}</p>`;
    $("heat").innerHTML = `<tr><th>Trimestre</th>${ph.map(x => `<th style="color:${PHASE_COLOR[x]}">${PHASE[x]}</th>`).join("")}</tr>` +
      ep.estaciones.map((s, k) => `<tr><td>${s.es}</td>${ph.map(x => { const v = P[x].media[k];
        return `<td class="v" style="background:${divColor(v)}">${v == null ? "–" : (v > 0 ? "+" : "") + v + " %"}<small>${P[x].n[k]} casos</small></td>`; }).join("")}</tr>`).join("");
    $("enso-method").textContent = `${ep.metodo} Período ${ep.periodo}. ${ep.fuente}`;
    const phase = e ? e.phase : "NEUTRAL", k0 = new Date().getMonth(), k1 = (k0 + 1) % 12;
    $("zones").innerHTML = `<p class="muted">Promedio histórico de la lluvia en cada zona cuando hubo <b>${PHASE[phase]}</b>, para los trimestres ${ep.estaciones[k0].es} y ${ep.estaciones[k1].es}. Indica una tendencia, no garantiza lo que va a pasar.</p>` +
      ep.puntos.map(p => {
        const vals = [k0, k1].map(k => (ep.por_punto[p.id] || {})[phase]).map((arr, j) => arr ? arr[[k0, k1][j]] : null).filter(v => v != null);
        const v = vals.length ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length) : null, wd = v == null ? 0 : Math.min(50, Math.abs(v));
        return `<div class="bar"><span class="lab">${esc(p.name)} <span class="muted">(${esc(p.seccion_nombre)})</span></span><span class="track"><span class="mid"></span>${v == null ? "" : `<span class="fill" style="${v >= 0 ? "left:50%" : `left:${50 - wd}%`};width:${wd}%;background:${divColor(v)}"></span>`}</span><b style="width:52px;text-align:right">${v == null ? "–" : (v > 0 ? "+" : "") + v + " %"}</b></div>`;
      }).join("");
  }

  function drawOni() {
    const svg = $("oni-chart"), all = S.st.enso ? S.st.enso.oni : [], data = S.oniRange === "all" ? all : all.slice(-360);
    if (!data.length) { svg.innerHTML = ""; return; }
    const W = 600, H = 220, pad = 24, max = 3, bw = (W - pad) / data.length, y = v => H / 2 - (v / max) * (H / 2 - 10);
    let s = `<line x1="${pad}" x2="${W}" y1="${y(0)}" y2="${y(0)}" stroke="currentColor" opacity=".4"/>` +
      [0.5, -0.5].map(v => `<line x1="${pad}" x2="${W}" y1="${y(v)}" y2="${y(v)}" stroke="currentColor" opacity=".3" stroke-dasharray="3 3"/>`).join("") +
      [2, 1, 0, -1, -2].map(v => `<text x="2" y="${y(v) + 4}" font-size="10" fill="currentColor" opacity=".6">${v > 0 ? "+" : ""}${v}</text>`).join("");
    s += data.map((d, i) => { const v = Math.max(-max, Math.min(max, d.value)), y0 = y(0), y1 = y(v);
      return `<rect x="${(pad + i * bw).toFixed(2)}" y="${Math.min(y0, y1).toFixed(1)}" width="${Math.max(bw, 0.6).toFixed(2)}" height="${Math.abs(y1 - y0).toFixed(1)}" fill="${PHASE_COLOR[d.phase]}"><title>${seasonEs(d.period)}: ${d.value}</title></rect>`; }).join("");
    const step = S.oniRange === "all" ? 10 : 5;
    [...new Set(data.map(d => d.period.split(" ")[1]))].filter(yr => +yr % step === 0).forEach(yr => {
      const i = data.findIndex(d => d.period.endsWith(" " + yr));
      s += `<text x="${pad + i * bw}" y="${H - 2}" font-size="10" fill="currentColor" opacity=".6">${yr}</text>`;
    });
    svg.innerHTML = s;
  }

  // ------------------------------------------------------------------ interacción
  map.on("click", e => {
    if (useSheet()) closeSheet();  // un toque en otro lugar reemplaza o cierra el detalle
    const D = S.cur;
    if (!D) return;
    const h = Math.min(S.hour, D.H - 1), lat = e.latlng.lat, lon = e.latlng.lng;
    let bi = -1, bd = Infinity;
    D.grid.points.forEach((p, i) => { const d = T.hav(lat, lon, p.lat, p.lon); if (d < bd) { bd = d; bi = i; } });
    if (bd > D.grid.spec.step * 111.2 * 1.2) return;
    const f = S.st.muniGeo && S.region === "pba" ? S.st.muniGeo.features.find(ft => inGeom(lat, lon, ft.geometry)) : null;
    const name = f ? f.properties.name : `${lat.toFixed(2)}°, ${lon.toFixed(2)}°`;
    const cond = T.condition(D.B.p[h][bi], D.B.c[h][bi]);
    const ws = D.B.ws[h][bi], wd = D.B.wd[h][bi], g = D.B.g[h][bi], t = D.B.temp[h][bi], p = D.B.p[h][bi];
    const argwx = f && S.st.pba ? S.st.pba.windows["24"].municipios.find(m => m.id === f.properties.id) : null;
    const smn = S.st.smn ? S.st.smn.alerts.filter(a => a.polygons.some(poly => pipLatLon(lat, lon, poly))) : [];
    const amb = f && S.st.ambiente ? S.st.ambiente.municipios[f.properties.id] : null;
    const st = nearestStation(lat, lon, 40);
    const coming = D.tracks.map(tr => ({tr, hit: tr.points.find(q => q.h >= h && T.hav(lat, lon, q.lat, q.lon) <= q.radius)})).filter(x => x.hit);
    L.popup({maxWidth: 290}).setLatLng(e.latlng).setContent(`<div class="pop"><h3>${esc(name)}</h3>
      <div class="muted">${h === 0 ? "Ahora" : `En ${h} h`} (${hhmm(D.B.times[h])}) · modelo de mejor ajuste</div>
      ${cond ? `<div class="row"><span>${COND[cond]}</span><svg width="28" height="28"><use href="#i-${cond}"/></svg></div>` : `<div class="row"><span>Sin lluvia</span></div>`}
      <div class="row"><span>🌡️ Temperatura</span><b>${t == null ? "–" : Math.round(t) + " °C"}</b></div>
      <div class="row"><span>💨 Viento</span><b>${ws == null ? "–" : `${Math.round(ws)} km/h hacia el ${T.cardinal(toDir(wd))}`}</b></div>
      <div class="row"><span>Ráfagas</span><b>${g == null ? "–" : Math.round(g) + " km/h"}</b></div>
      <div class="row"><span>🌧️ Lluvia</span><b>${p == null ? "–" : p + " mm/h"}</b></div>
      ${argwx ? `<div class="row"><span>ARGWX 24 h</span>${lvlBadge(argwx.alert_level)}</div>` : ""}
      ${argwx ? weightedRow(argwx) : ""}
      ${f ? soilRows(f.properties.id) : ""}
      ${f ? probRows(f.properties.id) : ""}
      ${amb ? `<div class="row"><span>☀️ UV máx. hoy</span><b>${amb.uv_max ?? "–"} ${amb.uv_categoria ? "(" + amb.uv_categoria + ")" : ""}</b></div>
              <div class="row"><span>🌫️ PM2.5 máx.</span><b>${amb.pm25_max ?? "–"} µg/m³</b></div>` : ""}
      ${st ? `<div class="row"><span>🌡️ SMN ${esc(st.estacion)} (${esc(st.hora)})</span><b>${esc(st.estado)}, ${st.temp_c ?? "–"} °C</b></div>` : ""}
      ${smn.map(a => `<div class="row"><span>SMN</span><span>${lvlBadge(a.level)} ${esc(a.title)}</span></div>`).join("")}
      ${coming.map(x => `<div class="row"><span>⛈️ ${kindOf(x.tr)}</span><b>${eta(x.hit.t)}</b></div>`).join("")}</div>`).openOn(map);
  });

  function soilRows(id) {
    const r72 = S.r72[id], su = S.st.suelo && S.st.suelo.municipios[id];
    const crs = S.st.crec ? S.st.crec.cursos.filter(c => hydroHot(c) && c.partidos_afectados.includes(id)).slice(0, 3) : [];
    return `${r72 != null ? `<div class="row"><span>🌧️ Lluvia prevista 72 h</span><b>${r72} mm</b></div>` : ""}
      ${su && su.suelo ? `<div class="row"><span>🌱 Suelo</span><b>${esc(su.suelo)}${su.lluvia_30d != null ? ` · ${Math.round(su.lluvia_30d)} mm en 30 días` : ""}</b></div>` : ""}
      ${crs.map(c => `<div class="row"><span>💧 ${esc(c.nombre)}</span>${lvlBadge(c.nivel)}</div>`).join("")}`;
  }

  // ------------------------------------------------------------------ crecidas y suelo
  function crecTab() {
    const cr = S.st.crec;
    if (!cr) {
      $("crec-sum").innerHTML = `<h2>💧 Crecidas</h2><p class="muted">Todavía no hay datos de crecidas publicados.</p>`;
      sueloCard();
      return;
    }
    const R = cr.resumen, alert = cr.cursos.filter(hydroHot);
    const refs = S.st.rios ? S.st.rios.rios.filter(r => r.nivel_7d !== "GREEN") : [];
    let lead;
    if (alert.length) {
      const per = ["RED", "ORANGE", "YELLOW"].filter(l => R.por_nivel[l]).map(l => `${R.por_nivel[l]} en ${LABEL[l].toLowerCase()}`);
      lead = `⚠️ <b>${alert.length} ${alert.length === 1 ? "tramo con señal de crecida" : "tramos con señal de crecida"}</b> en los próximos 3 días (${per.join(", ")}). Mayor señal: <b>${esc(alert[0].nombre)}</b> ${lvlBadge(alert[0].nivel)}.`;
    } else {
      const top = cr.cursos.filter(c => c.lluvia_72h != null).sort((a, b) => b.lluvia_72h - a.lluvia_72h)[0];
      lead = `<b>Sin superaciones de umbral en los tramos evaluados.</b> Los tramos sin evaluación no tienen un diagnóstico de riesgo.${top ? ` Mayor lluvia media sobre partidos del trazado: ${esc(top.nombre)}, ${top.lluvia_72h} mm en 72 h.` : ""}`;
    }
    $("crec-sum").innerHTML = `<h2>💧 Crecidas: próximos 3 días</h2><p class="big">${lead}</p>
      ${refs.length ? `<p>Puntos de referencia GloFAS con caudal alto frente a su historia 1984-hoy: ${refs.map(r => `<b>${esc(r.rio)}</b> en ${esc(r.lugar)} ${lvlBadge(r.nivel_7d)}`).join(", ")}.</p>` : ""}
      <p class="muted">Inventario: ${R.cursos} tramos cartográficos (${R.por_tipo["río"]} de ríos, ${R.por_tipo.arroyo} de arroyos, ${R.por_tipo.canal} de canales y ${R.por_tipo.estuario || 0} estuario). Un curso puede tener varios registros, incluidos cauces sin nombre. ${R.evaluados ?? R.cursos} con evaluación orientativa; ${R.sin_evaluacion || 0} sin evaluación; ${R.con_caudal} con caudal GloFAS. Evaluación actualizada: ${fmtDT(cr.generated_at)}.</p>
      ${cr.cobertura ? `<p class="muted">${cr.cobertura.cuencas} cuencas DPH · cartografía DPH descargada: ${esc(cr.cobertura.fecha_descarga)}. ${esc(cr.cobertura.nota)} Activá «Red hídrica» o «Cuencas DPH» en Capas; acercá el mapa para ver cauces menores.</p>` : ""}
      <p class="muted">Fuentes: <a href="https://www.gba.gob.ar/hidraulica/cuencas_hidricas/mapa" target="_blank" rel="noopener">DPH Buenos Aires</a> · <a href="https://www.ign.gob.ar/NuestrasActividades/InformacionGeoespacial/CapasSIG" target="_blank" rel="noopener">IGN</a> · <a href="https://data.buenosaires.gob.ar/dataset/arroyos" target="_blank" rel="noopener">Arroyos GCBA</a> · <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>. <a href="data/red_hidrica.json" target="_blank" rel="noopener">Datos y procedencia</a>.</p>`;
    $("crec-method").innerHTML = `${esc(cr.metodo)} Las alturas observadas en escalas oficiales (Prefectura, Red Hidrológica Nacional) prevalecen: sobre el nivel de alerta el curso queda al menos en Naranja y sobre el de evacuación, en Roja.<br><br>${esc(cr.nota)}<br><br>${esc(cr.fuentes)}`;
    crecList();
    sueloCard();
    gaugesCard();
  }

  function gaugesCard() {
    const o = S.st.obsRios;
    if (!o || !o.estaciones.length) { $("obs-rios-card").innerHTML = ""; return; }
    const hot = o.estaciones.filter(st => st.nivel !== "GREEN");
    $("obs-rios-card").innerHTML = `<h2>📏 Alturas observadas de los ríos</h2>
      <p>${hot.length ? `⚠️ <b>${plural(hot.length, "escala", "escalas")} sobre el nivel de alerta</b>.` : `✅ Ninguna escala de la provincia supera su nivel de alerta.`}</p>
      <ul class="plain">${o.estaciones.slice(0, 14).map(st => `<li class="row"><span><b>${esc(st.estacion)}</b> <span class="muted">· ${esc(riverName(st.rio))}${st.alerta != null ? ` · alerta ${String(st.alerta).replace(".", ",")} m` : ""}</span></span>
        <b>${st.altura_m.toFixed(2).replace(".", ",")} m ${st.nivel !== "GREEN" ? lvlBadge(st.nivel) : `<span class="muted">${esc(st.estado)}</span>`}</b></li>`).join("")}</ul>
      <p class="muted">${esc(o.fuente)}. Cada escala tiene su propio cero: las alturas sirven para seguir un mismo puerto, no para comparar puertos entre sí. Se ven en el mapa con la capa Ríos.</p>`;
  }

  function crecList() {
    const cr = S.st.crec;
    if (!cr) { $("crec-list").innerHTML = ""; return; }
    const q = norm($("crec-q").value.trim());
    let list = cr.cursos;
    if (q) {  // primero los que coinciden por nombre; después por partido o localidad
      const byName = c => [c.nombre, ...(c.alias || [])].some(n => norm(n) === q) ? 2 :
        norm([c.nombre, ...(c.alias || [])].join(" ")).includes(q) ? 1 : 0;
      list = list.filter(c => byName(c) || c.partidos.some(p => norm(MN(p)).includes(q)) || c.localidades.some(l => norm(l[0]).includes(q)) ||
        norm([...(c.cuencas || []), ...(c.jurisdicciones || [])].join(" ")).includes(q))
        .sort((a, b) => (byName(b) - byName(a)) || (LV.indexOf(b.nivel) - LV.indexOf(a.nivel)) || ((b.km || 0) - (a.km || 0)));
    }
    else if (S.crecF === "alerta") list = list.filter(hydroHot);
    else if (S.crecF === "sin-datos") list = list.filter(c => !c.nivel);
    const shown = list.slice(0, S.crecN);
    $("crec-list").innerHTML = shown.length ? shown.map(c => {
      const green = !hydroHot(c), pa = green ? c.partidos : c.partidos_afectados;
      const locs = (green ? c.localidades : c.localidades_afectadas).slice(0, 8);
      return `<li><div>${lvlBadge(c.nivel)} <b>${esc(c.nombre)}</b> <span class="muted">· ${esc(c.tipo)}${kmTxt(c)}${c.pico ? ` · pico ${fmtDay(c.pico)}` : ""}</span></div>
        ${hydroContext(c)}${c.motivos.length ? `<div class="muted" style="margin:4px 0">${c.motivos.map(esc).join(" · ")}</div>` : ""}
        ${!green && c.partidos_senal.length ? `<div style="margin:4px 0;font-size:13.5px">Señal más fuerte en <b>${c.partidos_senal.slice(0, 4).map(p => esc(MN(p))).join(", ")}</b>; podría afectar a los partidos sobre el curso:</div>` : ""}
        <div class="pl">${pa.slice(0, 10).map(p => `<span>${esc(MN(p))}</span>`).join("")}${pa.length > 10 ? `<span>+${pa.length - 10}</span>` : ""}</div>
        ${locs.length ? `<div class="muted" style="margin-top:4px">📍 ${locs.map(l => esc(l[0])).join(", ")}</div>` : ""}
        <button class="lnk" data-go="${esc(c.id)}">Ver en el mapa →</button></li>`;
    }).join("") + (list.length > shown.length ? `<li><button class="lnk" id="crec-more">Ver más (${list.length - shown.length} restantes)</button></li>` : "")
      : `<li class="muted">${q ? "Sin resultados para esa búsqueda." : S.crecF === "sin-datos" ? "No hay tramos sin evaluación en esta actualización." : "No hay alertas en los tramos evaluados. Elegí «Todos» para ver el inventario completo o buscá por nombre, partido, cuenca o localidad."}</li>`;
  }

  function sueloCard() {
    const su = S.st.suelo;
    if (!su) { $("suelo-card").innerHTML = ""; return; }
    const rows = Object.entries(su.municipios).map(([id, v]) => ({id, ...v}));
    const cats = ["muy húmedo", "húmedo", "adecuado", "seco"];
    const cnt = Object.fromEntries(cats.map(c => [c, rows.filter(r => r.suelo === c).length]));
    const wet = rows.filter(r => r.lluvia_30d != null).sort((a, b) => b.lluvia_30d - a.lluvia_30d).slice(0, 8);
    const dry = rows.filter(r => r.humedad_suelo != null).sort((a, b) => a.humedad_suelo - b.humedad_suelo).slice(0, 6);
    const risk = rows.filter(r => (r.suelo === "muy húmedo" || r.suelo === "húmedo") && (S.r72[r.id] || 0) >= 20)
      .sort((a, b) => S.r72[b.id] - S.r72[a.id]);
    const known = cats.some(c => cnt[c]);
    $("suelo-card").innerHTML = `<h2>🌱 Suelo y siembra</h2>
      ${known ? `<div class="soilbar">${cats.map(c => `<span style="flex:${cnt[c]};background:${SOIL_COLOR[c]}"></span>`).join("")}</div>
      <p class="muted">${cats.map(c => `<span class="sw" style="background:${SOIL_COLOR[c]}"></span>${c}: ${cnt[c]}`).join(" · ")} partidos</p>` : `<p class="muted">Sin datos de humedad del suelo en esta actualización.</p>`}
      ${risk.length ? `<p>⚠️ <b>Suelo con mucha agua y más lluvia prevista</b> (20 mm o más en 72 h): ${risk.slice(0, 12).map(r => `${esc(MN(r.id))} (${S.r72[r.id]} mm)`).join(", ")}${risk.length > 12 ? ` y ${risk.length - 12} más` : ""}. Puede haber anegamiento de lotes bajos y demoras en la siembra y la cosecha.</p>` : ""}
      ${wet.length ? `<p><b>Más lluvia en los últimos 30 días:</b> ${wet.map(r => `${esc(MN(r.id))} ${Math.round(r.lluvia_30d)} mm`).join(", ")}.</p>` : ""}
      ${dry.length ? `<p><b>Suelos más secos:</b> ${dry.map(r => `${esc(MN(r.id))} (${esc(r.suelo)})`).join(", ")}.</p>` : ""}
      <p class="muted">${esc(su.fuente)}. ${esc(su.nota)}</p>`;
  }

  function showCourse(id) {
    const c = S.st.crec && S.st.crec.cursos.find(x => x.id === id);
    if (!c) return;
    document.querySelector('#tabs button[data-t="live"]').click();
    if (S.region !== "pba") document.querySelector('#region button[data-r="pba"]').click();
    if (!S.layers.rios) document.querySelector('#layers button[data-l="rios"]').click();
    G.hl.clearLayers();
    if (c.trazo.length) drawCourse(c, G.hl, true);
    window.scrollTo({top: 0});
    const bounds = L.latLngBounds([c.bbox[0], c.bbox[1]], [c.bbox[2], c.bbox[3]]);
    if (mobile()) openSheet(courseHTML(c), null);
    setTimeout(() => {  // después de que la barra se acomoda y el mapa toma su tamaño
      map.invalidateSize({pan: false});
      const below = mobile() ? $("sheet").offsetHeight : 70;
      map.fitBounds(bounds, {paddingTopLeft: [24, 64], paddingBottomRight: [24, below + 16], maxZoom: 16});
      if (!mobile()) L.popup({maxWidth: 300}).setLatLng(bounds.getCenter()).setContent(courseHTML(c)).openOn(map);
    }, 420);
  }

  function setRegion(r) {
    S.region = r;
    const b = S.regions[r].bounds;
    map.fitBounds(b, {padding: [10, 10]});
    drawProvs(); drawMunis(); drawSMN();
    refresh(false);
  }

  async function refresh(force) {
    const region = S.region;
    $("live-txt").textContent = "Actualizando…";
    const live = await loadLive(region, force);
    if (region !== S.region) return;
    S.cur = prepare(region, live);
    S.hour = Math.min(S.hour, S.cur ? S.cur.H - 1 : 0);
    $("hour").value = S.hour;
    draw(); panels();
  }

  async function loadStatic() {
    const files = {meta: "data/meta.json", smn: "data/smn_argentina.json", enso: "data/enso.json", ensoPba: "data/enso_pba.json",
                   pba: "data/alertas_pba.json", muniGeo: "geo/municipios_pba.geojson", munis: "geo/municipios_pba.json",
                   prov: "geo/provincias_ar.geojson", obs: "data/observaciones_smn.json", rios: "data/rios.json",
                   costa: "data/costa.json", ambiente: "data/ambiente.json", probs: "data/probabilidades.json",
                   crec: "data/crecidas.json", suelo: "data/suelo.json", clima: "data/historico/climatologia_lluvia.json",
                   calib: "data/historico/calibracion.json", catalogo: "data/historico/catalogo.json",
                   obsRios: "data/rios_observados.json", cuencas: "data/cuencas_hidricas.json"};
    const vals = await Promise.all(Object.values(files).map(u => getJSON(u).catch(() => null)));
    Object.keys(files).forEach((k, i) => { S.st[k] = vals[i]; });
    S.munis = S.st.munis || [];
    S.provs = S.st.prov ? S.st.prov.features : [];
    const failed = S.st.meta ? Object.entries(S.st.meta.parts).filter(([, v]) => !v.ok).map(([k]) => k) : [];
    const PART = {enso: "El Niño", smn: "alertas del SMN", en_vivo_respaldo: "copia de respaldo del mapa", observaciones_smn: "estaciones del SMN",
                  rios: "ríos de referencia", costa: "olas", ambiente: "UV y calidad del aire", probabilidades: "probabilidades de lluvia",
                  enso_pba: "El Niño en la provincia", red_hidrica: "red de ríos y arroyos", suelo: "humedad del suelo",
                  caudales_red: "caudales de ríos y arroyos (GloFAS)", alertas_pba: "alertas por municipio", crecidas: "crecidas"};
    $("warns").innerHTML = failed.length ? `<div class="warn">Algunas fuentes no respondieron en la última actualización del servidor: ${esc(failed.map(k => PART[k] || k).join(", "))}. Se muestran los datos disponibles.</div>` : "";
    S.r72 = {};
    if (S.st.pba) {
      const per = {};
      ["24", "48", "72"].forEach(w => (S.st.pba.windows[w] || {municipios: []}).municipios.forEach(m => { (per[m.id] = per[m.id] || []).push(m.lluvia_mm); }));
      Object.entries(per).forEach(([id, v]) => { if (v.length === 3 && v.every(x => x != null)) S.r72[id] = Math.round(v.reduce((a, b) => a + b, 0) * 10) / 10; });
    }
    drawProvs(); drawSMN(); drawMunis(); drawExtras(); extrasCards(); alertsTab(); ensoTab(); crecTab(); histCards();
  }

  function seg(id, fn) {
    $(id).addEventListener("click", e => {
      const b = e.target.closest("button");
      if (!b || b.classList.contains("hdr-toggle")) return;  // "Menú" no es una pestaña
      [...$(id).children].forEach(x => { if (!x.classList.contains("hdr-toggle")) x.classList.toggle("on", x === b); });
      fn(b.dataset);
    });
  }
  seg("tabs", d => {
    ["live", "alerts", "enso", "crec"].forEach(t => { $("t-" + t).hidden = t !== d.t; });
    if (d.t === "live") setTimeout(() => map.invalidateSize(), 50);
  });
  seg("region", d => setRegion(d.r));
  seg("smn-filter", d => { S.smnFilter = d.f; alertsTab(); });
  seg("pwin", d => { S.pwin = d.w; alertsTab(); });
  seg("oni-range", d => { S.oniRange = d.r; drawOni(); });
  seg("crec-f", d => { S.crecF = d.f; S.crecN = 40; crecList(); });
  $("crec-q").addEventListener("input", () => { S.crecN = 40; crecList(); });
  $("crec-list").addEventListener("click", e => {
    const b = e.target.closest("button");
    if (!b) return;
    if (b.id === "crec-more") { S.crecN += 50; crecList(); } else if (b.dataset.go) showCourse(b.dataset.go);
  });
  document.addEventListener("click", e => {
    const a = e.target.closest("[data-tab]");
    if (a) { e.preventDefault(); document.querySelector(`#tabs button[data-t="${a.dataset.tab}"]`).click(); window.scrollTo({top: 0}); }
  });
  $("layers").addEventListener("click", e => {
    const b = e.target.closest("button");
    if (!b) return;
    const l = b.dataset.l;
    S.layers[l] = !S.layers[l];
    b.classList.toggle("on", S.layers[l]);
    if (l === "sat") { if (S.layers.sat) { sat.options.time = satTime(); sat.addTo(map); sat.redraw(); } else map.removeLayer(sat); }
    else if (l === "smn") drawSMN();
    else if (l === "radar") { if (radar.layer) { if (S.layers.radar) radar.layer.addTo(map); else map.removeLayer(radar.layer); } }
    else if (["obs", "rios", "costa", "red", "cuencas"].includes(l)) drawExtras();
    else draw();
  });
  $("hour").addEventListener("input", e => { S.hour = +e.target.value; draw(); });
  map.on("moveend", drawExtras);
  $("play").addEventListener("click", () => {
    if (S.play) { clearInterval(S.play); S.play = null; $("play").textContent = "▶"; return; }
    $("play").textContent = "⏸";
    S.play = setInterval(() => {
      const max = S.cur ? S.cur.H - 1 : 0;
      S.hour = S.hour >= max ? 0 : S.hour + 1;
      $("hour").value = S.hour;
      draw();
    }, 1300);
  });
  $("refresh").addEventListener("click", () => { refresh(true); loadStatic(); });
  $("tracks").addEventListener("click", e => {
    const card = e.target.closest(".trk");
    if (!card || !S.cur) return;
    const tr = S.cur.tracks[+card.dataset.i], p = tr.points.find(q => q.h === S.hour) || tr.points[0];
    map.flyTo([p.lat, p.lon], Math.max(map.getZoom(), 7));
    window.scrollTo({top: 0, behavior: "smooth"});
  });
  $("locate").addEventListener("click", () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(pos => {
      const ll = [pos.coords.latitude, pos.coords.longitude];
      G.me.clearLayers();
      L.marker(ll, {icon: L.divIcon({className: "me", iconSize: [16, 16]})}).addTo(G.me);
      map.flyTo(ll, 8);
      setTimeout(() => map.fire("click", {latlng: L.latLng(ll)}), 900);
    }, () => alert("No se pudo obtener tu ubicación."), {enableHighAccuracy: false, timeout: 10000});
  });

  // ------------------------------------------------------------------ celular: barra compacta y panel de detalle
  // La barra superior se contrae al desplazar la página o tocar el mapa; el mapa gana ese alto.
  function fitMap() {
    if (mobile()) document.documentElement.style.setProperty("--topH", $("topbar").offsetHeight + "px");
    else document.documentElement.style.removeProperty("--topH");
    if ($("map").offsetWidth) map.invalidateSize({pan: false});  // con el mapa oculto (otra pestaña) correría la vista
  }
  function setCompact(on) {
    if (document.body.classList.contains("compact") === on) return;
    document.body.classList.toggle("compact", on);
    setTimeout(fitMap, 240);
  }
  addEventListener("scroll", () => {
    const room = document.documentElement.scrollHeight - innerHeight;
    if (scrollY > 30 && (room > 200 || mobile())) setCompact(true);
    else if (scrollY <= 0) setCompact(false);
  }, {passive: true});
  // Se contrae al terminar un gesto (arrastre o pellizco), nunca al primer contacto: si el mapa se moviera
  // bajo el dedo, el toque caería en otro lugar.
  let moved = false;
  $("map").addEventListener("touchmove", () => { moved = true; }, {passive: true});
  $("map").addEventListener("touchend", () => { if (moved && mobile()) setCompact(true); moved = false; }, {passive: true});
  map.on("dragend", () => { if (mobile()) setCompact(true); });
  $("brand").addEventListener("click", e => {
    if (!document.body.classList.contains("compact")) return;
    e.preventDefault();
    window.scrollTo({top: 0});
    setCompact(false);
  });
  $("mini").addEventListener("click", () => { refresh(true); loadStatic(); });

  // ------------------------------------------------------------------ encabezado contraíble y pantalla completa
  // "▴ Menú" fija el encabezado contraído (se recuerda en este navegador); el mapa gana ese alto.
  function setPinned(on) {
    document.body.classList.toggle("pinned", on);
    $("hdr-toggle").textContent = on ? "▾ Menú" : "▴ Menú";
    $("hdr-toggle").setAttribute("aria-pressed", String(on));
    try { localStorage.setItem("argwx-hdr", on ? "1" : "0"); } catch (e) { /* sin almacenamiento */ }
    if (on) setCompact(true); else if (scrollY <= 0) setCompact(false);
    setTimeout(fitMap, 240);
  }
  $("hdr-toggle").addEventListener("click", () => setPinned(!document.body.classList.contains("pinned")));
  try { if (localStorage.getItem("argwx-hdr") === "1") setPinned(true); } catch (e) { /* sin almacenamiento */ }

  function setFull(on) {
    if (full() === on) return;
    document.body.classList.toggle("mapfull", on);
    $("fs").textContent = on ? "✕" : "⛶";
    $("fs").setAttribute("aria-label", on ? "Salir de pantalla completa" : "Ver el mapa en pantalla completa");
    map.closePopup();
    if (on) {
      if (document.documentElement.requestFullscreen && !document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => { /* el navegador lo negó: queda el modo dentro de la página */ });
      }
      if (!mobile()) showAlertsPanel();
    } else {
      closeSheet();
      if (document.fullscreenElement && document.exitFullscreen) document.exitFullscreen().catch(() => {});
    }
    setTimeout(fitMap, 260);
  }
  $("fs").addEventListener("click", () => setFull(!full()));
  document.addEventListener("fullscreenchange", () => { if (!document.fullscreenElement && full()) setFull(false); });

  // Panel lateral con todas las alertas vigentes; cada una lleva al lugar en el mapa.
  function showAlertsPanel() {
    const smn = (S.st.smn ? S.st.smn.alerts : []).map((a, i) => ({a, i})).filter(x => x.a.partidos_pba.length || S.region !== "pba");
    const win = S.st.pba && S.st.pba.windows[S.pwin || "24"];
    const pba = win ? win.municipios.filter(m => m.alert_level !== "GREEN" || (m.ponderado && m.ponderado.difiere))
      .sort((a, b) => LV.indexOf(b.alert_level) - LV.indexOf(a.alert_level)) : [];
    openSheet(`<div class="pop side-alerts"><h3>⚠️ Alertas vigentes</h3>
      <p class="muted">Tocá una alerta para verla en el mapa. ${win ? esc(win.label) : ""}</p>
      <h4>SMN (oficiales)</h4>
      ${smn.length ? smn.map(x => `<button class="side-item" data-smn="${x.i}">${lvlBadge(x.a.level)} <b>${esc(x.a.title)}</b>
        <span class="muted">${esc((x.a.partidos_pba.length ? x.a.partidos_pba : x.a.provincias).slice(0, 6).join(", "))} · hasta ${fmtDT(x.a.valid_to)}</span></button>`).join("")
        : `<p class="muted">${S.st.smn ? "Sin alertas del SMN para esta zona." : "No se pudieron leer las alertas del SMN."}</p>`}
      <h4>ARGWX por partido</h4>
      ${pba.length ? pba.map(m => `<button class="side-item" data-muni="${esc(m.id)}">${lvlBadge(m.alert_level)} <b>${esc(m.name)}</b>
        <span class="muted">${esc(m.hazard || "")} ${m.consensus ? "· coinciden " + esc(m.consensus) : ""}</span>${weightedLine(m)}</button>`).join("")
        : `<p class="muted">Ningún partido en alerta en esta ventana.</p>`}</div>`);
  }
  $("fs-alerts").addEventListener("click", showAlertsPanel);
  $("sheet-c").addEventListener("click", e => {
    const back = e.target.closest("[data-back]");
    if (back) { showAlertsPanel(); return; }
    const item = e.target.closest(".side-item");
    if (!item) return;
    if (item.dataset.smn != null) {
      const a = S.st.smn.alerts[+item.dataset.smn];
      if (!a) return;
      const b = L.latLngBounds(a.polygons.flat());
      if (b.isValid()) map.fitBounds(b, {padding: [30, 30], maxZoom: 9});
      openSheet(`<div class="pop"><button class="side-back" data-back>← Alertas</button><h3>${lvlBadge(a.level)} ${esc(a.title)}</h3>
        <div class="muted">SMN · ${esc(a.provincias.join(", "))}</div><div>Desde ${fmtDT(a.valid_from)} hasta ${fmtDT(a.valid_to)}</div>
        ${a.partidos_pba.length ? `<div><b>Buenos Aires:</b> ${esc(a.partidos_pba.join(", "))}</div>` : ""}</div>`);
      return;
    }
    const f = S.st.muniGeo && S.st.muniGeo.features.find(ft => ft.properties.id === item.dataset.muni);
    if (!f) return;
    const c = L.geoJSON(f).getBounds();
    map.fitBounds(c, {padding: [40, 40], maxZoom: 10});
    setTimeout(() => map.fire("click", {latlng: c.getCenter()}), 450);
  });
  let resizeT;
  addEventListener("resize", () => { clearTimeout(resizeT); resizeT = setTimeout(fitMap, 150); });

  // Capas: en el celular se despliegan con un botón para no tapar el mapa.
  const countLayers = () => { $("layers-n").textContent = `(${[...$("layers").children].filter(b => b.classList.contains("on")).length})`; };
  $("layers-btn").addEventListener("click", () => {
    const open = !$("maptop").classList.contains("open");
    $("maptop").classList.toggle("open", open);
    $("layers-btn").setAttribute("aria-expanded", String(open));
  });
  $("layers").addEventListener("click", countLayers);
  map.on("click dragstart", () => { $("maptop").classList.remove("open"); $("layers-btn").setAttribute("aria-expanded", "false"); });
  countLayers();

  // Detalle: en el celular, panel inferior legible en lugar del globo de Leaflet (que quedaba tapado).
  const pick = L.layerGroup().addTo(map);
  function closeSheet() {
    $("sheet").hidden = true;
    document.body.classList.remove("sheet-open");
    pick.clearLayers();
    if (full()) setTimeout(() => map.invalidateSize({pan: false}), 30);
  }
  function openSheet(html, ll) {
    $("sheet-c").innerHTML = html;
    $("sheet").hidden = false;
    document.body.classList.add("sheet-open");
    if (full()) setTimeout(() => map.invalidateSize({pan: false}), 30);
    $("sheet").scrollTop = 0;
    setTimeout(() => setCompact(true), 0);
    pick.clearLayers();
    if (!ll) return;
    L.marker(ll, {icon: L.divIcon({className: "pick", iconSize: [18, 18]}), interactive: false, keyboard: false, pane: "stormPane"}).addTo(pick);
    requestAnimationFrame(() => {
      const free = map.getSize().y - $("sheet").offsetHeight, y = map.latLngToContainerPoint(ll).y;
      if (y > free - 30 || y < 50) map.panBy([0, y - Math.max(free / 2, 60)], {animate: true});
    });
  }
  $("sheet-x").addEventListener("click", closeSheet);
  addEventListener("keydown", e => {
    if (e.key !== "Escape") return;
    if (!$("sheet").hidden) closeSheet(); else if (full()) setFull(false);
  });
  if (mobile()) L.Popup.mergeOptions({autoPan: false});
  else L.Popup.mergeOptions({autoPanPaddingTopLeft: L.point(16, 120), autoPanPaddingBottomRight: L.point(16, 90)});
  map.on("popupopen", e => {
    if (!useSheet()) return;
    const pop = e.popup, c = pop.getContent();
    const html = typeof c === "function" ? c(pop._source) : c;
    const ll = pop.getLatLng();
    map.closePopup(pop);
    const back = full() ? `<button class="side-back" data-back>← Alertas</button>` : "";
    openSheet(back + (typeof html === "string" ? html : html.outerHTML), ll);
  });

  (async () => {
    fitMap();
    S.regions = await getJSON("regions.json");
    Object.keys(S.regions).forEach(r => { S.grids[r] = T.makeGrid(S.regions[r]); });
    map.fitBounds(S.regions.pba.bounds, {padding: [10, 10]});
    await loadStatic();
    loadRadar();
    setInterval(loadRadar, 10 * 60e3);
    await refresh(false);
    setInterval(() => refresh(false), 15 * 60e3);
    setInterval(loadStatic, 30 * 60e3);
  })();
})();
