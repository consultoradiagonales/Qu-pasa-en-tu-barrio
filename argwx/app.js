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
  const DARK = window.matchMedia && matchMedia("(prefers-color-scheme: dark)").matches;
  const S = {region: "pba", hour: 0, layers: {storms: true, wind: true, wx: true, smn: true, sat: false}, grids: {},
             cur: null, st: {}, munis: [], provs: [], smnFilter: "storm", pwin: "24", oniRange: "30", play: null, me: null};
  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
  const lvlBadge = l => `<span class="lvl ${l}" style="background:${COLOR[l]}">${LABEL[l]}</span>`;
  const TF = {hour: "2-digit", minute: "2-digit", hourCycle: "h23"};
  const hhmm = unix => new Date(unix * 1000).toLocaleTimeString("es-AR", TF);
  const fmtDT = iso => iso ? new Date(iso).toLocaleString("es-AR", {day: "2-digit", month: "2-digit", ...TF}) : "–";
  const windColor = s => s >= 70 ? "#8e44ad" : s >= 50 ? "#e74c3c" : s >= 30 ? "#f39c12" : s >= 15 ? "#2b8cbe" : "#7f8c9a";
  const toDir = from => (from + 180) % 360;
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
  const map = L.map("map", {zoomControl: false, minZoom: 3, maxZoom: 11, zoomSnap: 0.25});
  if (!L.Browser.mobile) L.control.zoom({position: "topright"}).addTo(map);
  // Mapa base: OpenStreetMap (sin clave). En producción conviene un proveedor de mapas contratado.
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);
  [["satPane", 250], ["provPane", 370], ["smnPane", 380], ["muniPane", 390], ["stormPane", 420]].forEach(([n, z]) => { map.createPane(n).style.zIndex = z; });
  const sat = L.tileLayer("https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/GOES-East_ABI_GeoColor/default/default/GoogleMapsCompatible_Level7/{z}/{y}/{x}.png",
    {pane: "satPane", maxNativeZoom: 7, maxZoom: 11, opacity: 0.6, attribution: "Satélite: NASA GIBS · GOES-Este"});
  const G = {prov: L.layerGroup().addTo(map), smn: L.layerGroup().addTo(map), muni: L.layerGroup().addTo(map), storms: L.layerGroup().addTo(map),
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

  // ------------------------------------------------------------------ paneles
  function trackHTML(tr, popup) {
    const cur = tr.points.find(p => p.h === S.hour) || tr.points[0];
    const places = S.region === "pba" ? tr.affected : tr.provincias;
    const list = places.slice(0, popup ? 14 : 24).map(x => `<span><b>${esc(x.name)}</b> ${eta(x.t)}</span>`).join("");
    const kind = tr.points.some(p => p.thunder) ? "Tormenta" : "Lluvia fuerte";
    const html = `<div class="trk-h">${lvlBadge(tr.level)} <b>${kind} ${INTENS[tr.level]}</b>
        <span class="muted">${Math.round(tr.probMax * 5)} de 5 modelos (${Math.round(tr.probMax * 100)} %)</span></div>
      <div class="trk-m">🧭 ${esc(tr.dirText)}${tr.speed ? ` a ${tr.speed} km/h` : ""} · ${tr.trend === "se intensifica" ? "📈" : tr.trend === "se debilita" ? "📉" : "➖"} ${esc(tr.trend)}
        <span class="muted">· entre ${hhmm(tr.start)} y ${hhmm(tr.end)} · ahora: ${Math.round(cur.radius)} km de radio</span></div>
      ${places.length ? `<div class="muted">Pasaría por${S.region === "pba" ? "" : " (provincias argentinas)"}:</div><div class="pl">${list}${places.length > 24 ? `<span>+${places.length - 24} más</span>` : ""}</div>`
        : `<div class="muted">No toca ${S.region === "pba" ? "municipios bonaerenses" : "provincias argentinas"} en las próximas horas.</div>`}`;
    return popup ? `<div class="pop">${html}</div>` : html;
  }

  function panels() {
    const D = S.cur;
    const txt = $("live-txt"), pulse = $("pulse");
    if (!D) {
      pulse.className = "pulse off"; txt.textContent = "Sin datos";
      $("now-card").innerHTML = `<h2>Ahora</h2><p>No se pudieron obtener datos. Probá de nuevo en unos minutos.</p>`;
      $("tracks").innerHTML = "";
      return;
    }
    pulse.className = "pulse" + (D.source === "live" ? "" : " snap");
    txt.textContent = `${D.source === "live" ? "En vivo" : "Copia del servidor"} · ${new Date(D.at).toLocaleTimeString("es-AR", TF)}`;
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
    $("smn-list").innerHTML = list.length ? list.map(a => `<li><div>${lvlBadge(a.level)} <b>${esc(a.title)}</b></div>
      <div class="muted">${esc(a.provincias.join(", ") || "Área sin provincia identificada")} · desde ${fmtDT(a.valid_from)} hasta ${fmtDT(a.valid_to)}</div>
      ${a.partidos_pba.length ? `<div class="muted"><b>Buenos Aires:</b> ${esc(a.partidos_pba.join(", "))}</div>` : ""}</li>`).join("")
      : `<li class="muted">${S.st.smn ? "No hay alertas vigentes para este filtro." : "No se pudieron leer las alertas del SMN."}</li>`;
    const win = S.st.pba && S.st.pba.windows[S.pwin];
    const alerted = win ? win.municipios.filter(m => m.alert_level !== "GREEN").sort((a, b) => LV.indexOf(b.alert_level) - LV.indexOf(a.alert_level)) : [];
    $("pba-info").textContent = win ? `${win.label} · ${135 - alerted.length} municipios en verde · consenso de ${(S.st.pba.models || []).join(", ")}` : "Sin datos.";
    $("pba-list").innerHTML = alerted.length ? alerted.map(m => `<li><div>${lvlBadge(m.alert_level)} <b>${esc(m.name)}</b> <span class="muted">${esc(m.hazard || "")} · confianza ${esc(m.confidence_label)}</span></div><div class="muted">${esc(m.drivers[0] || "")}</div></li>`).join("")
      : `<li class="muted">Ningún municipio en alerta en esta ventana.</li>`;
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
    const coming = D.tracks.map(tr => ({tr, hit: tr.points.find(q => q.h >= h && T.hav(lat, lon, q.lat, q.lon) <= q.radius)})).filter(x => x.hit);
    L.popup({maxWidth: 290}).setLatLng(e.latlng).setContent(`<div class="pop"><h3>${esc(name)}</h3>
      <div class="muted">${h === 0 ? "Ahora" : `En ${h} h`} (${hhmm(D.B.times[h])}) · modelo de mejor ajuste</div>
      ${cond ? `<div class="row"><span>${COND[cond]}</span><svg width="28" height="28"><use href="#i-${cond}"/></svg></div>` : `<div class="row"><span>Sin lluvia</span></div>`}
      <div class="row"><span>🌡️ Temperatura</span><b>${t == null ? "–" : Math.round(t) + " °C"}</b></div>
      <div class="row"><span>💨 Viento</span><b>${ws == null ? "–" : `${Math.round(ws)} km/h hacia el ${T.cardinal(toDir(wd))}`}</b></div>
      <div class="row"><span>Ráfagas</span><b>${g == null ? "–" : Math.round(g) + " km/h"}</b></div>
      <div class="row"><span>🌧️ Lluvia</span><b>${p == null ? "–" : p + " mm/h"}</b></div>
      ${argwx ? `<div class="row"><span>ARGWX 24 h</span>${lvlBadge(argwx.alert_level)}</div>` : ""}
      ${smn.map(a => `<div class="row"><span>SMN</span><span>${lvlBadge(a.level)} ${esc(a.title)}</span></div>`).join("")}
      ${coming.map(x => `<div class="row"><span>⛈️ Tormenta ${INTENS[x.tr.level]}</span><b>${eta(x.hit.t)}</b></div>`).join("")}</div>`).openOn(map);
  });

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
                   prov: "geo/provincias_ar.geojson"};
    const vals = await Promise.all(Object.values(files).map(u => getJSON(u).catch(() => null)));
    Object.keys(files).forEach((k, i) => { S.st[k] = vals[i]; });
    S.munis = S.st.munis || [];
    S.provs = S.st.prov ? S.st.prov.features : [];
    const failed = S.st.meta ? Object.entries(S.st.meta.parts).filter(([, v]) => !v.ok).map(([k]) => k) : [];
    $("warns").innerHTML = failed.length ? `<div class="warn">Algunas fuentes no respondieron en la última actualización del servidor (${esc(failed.join(", "))}).</div>` : "";
    drawProvs(); drawSMN(); drawMunis(); alertsTab(); ensoTab();
  }

  function seg(id, fn) {
    $(id).addEventListener("click", e => {
      const b = e.target.closest("button");
      if (!b) return;
      [...$(id).children].forEach(x => x.classList.toggle("on", x === b));
      fn(b.dataset);
    });
  }
  seg("tabs", d => {
    ["live", "alerts", "enso"].forEach(t => { $("t-" + t).hidden = t !== d.t; });
    if (d.t === "live") setTimeout(() => map.invalidateSize(), 50);
  });
  seg("region", d => setRegion(d.r));
  seg("smn-filter", d => { S.smnFilter = d.f; alertsTab(); });
  seg("pwin", d => { S.pwin = d.w; alertsTab(); });
  seg("oni-range", d => { S.oniRange = d.r; drawOni(); });
  $("layers").addEventListener("click", e => {
    const b = e.target.closest("button");
    if (!b) return;
    const l = b.dataset.l;
    S.layers[l] = !S.layers[l];
    b.classList.toggle("on", S.layers[l]);
    if (l === "sat") { if (S.layers.sat) sat.addTo(map); else map.removeLayer(sat); }
    else if (l === "smn") drawSMN();
    else draw();
  });
  $("hour").addEventListener("input", e => { S.hour = +e.target.value; draw(); });
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

  (async () => {
    S.regions = await getJSON("regions.json");
    Object.keys(S.regions).forEach(r => { S.grids[r] = T.makeGrid(S.regions[r]); });
    map.fitBounds(S.regions.pba.bounds, {padding: [10, 10]});
    await loadStatic();
    await refresh(false);
    setInterval(() => refresh(false), 15 * 60e3);
    setInterval(loadStatic, 30 * 60e3);
  })();
})();
