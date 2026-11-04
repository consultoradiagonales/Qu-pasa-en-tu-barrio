// Test del seguimiento de tormentas (node tests/js/tracking.test.js). Datos SINTÉTICOS, solo para probar el algoritmo.
const assert = require("assert");
const path = require("path");
const T = require(path.join(__dirname, "../../app/site/tracking.js")).ARGWX_TRACKING;
const regions = require(path.join(__dirname, "../../app/site/regions.json"));
const munis = require(path.join(__dirname, "../../app/data/municipios_pba.json"));

const grid = T.makeGrid(regions.pba);
assert.strictEqual(grid.points.length, grid.nLat * grid.nLon);
const MODELS = ["gfs_seamless", "icon_seamless", "ecmwf_ifs025", "gem_seamless", "ukmo_seamless"];
const H = 6, N = grid.points.length, times = Array.from({length: H}, (_, h) => 1700000000 + h * 3600);

// Una tormenta que avanza una columna por hora hacia el este y crece; cada modelo la ubica un poco distinto.
function build(models) {
  const data = {times, models: {}};
  models.forEach((m, k) => {
    const P = [], C = [], G = [];
    for (let h = 0; h < H; h++) {
      const p = new Array(N).fill(0), c = new Array(N).fill(3), g = new Array(N).fill(30);
      const r0 = 6 + (k % 2), c0 = 2 + h, size = h < 3 ? 1 : 2;
      for (let dr = -size; dr <= size; dr++) for (let dc = -size; dc <= size; dc++) {
        const i = (r0 + dr) * grid.nLon + (c0 + dc);
        p[i] = 12; c[i] = 95; g[i] = 85;
      }
      P.push(p); C.push(c); G.push(g);
    }
    data.models[m] = {P, C, G};
  });
  return data;
}

const tracks = T.track(grid, build(MODELS), {nModels: 5});
assert.strictEqual(tracks.length, 1, "una sola trayectoria");
const tr = tracks[0];
assert.strictEqual(tr.points.length, H);
assert.strictEqual(tr.probMax, 1);
assert.ok(tr.dir > 70 && tr.dir < 110, "se mueve hacia el este: " + tr.dir);
assert.strictEqual(tr.dirText, "hacia el este");
assert.ok(tr.speed > 50 && tr.speed < 80, "velocidad ~67 km/h: " + tr.speed);
assert.strictEqual(tr.level, "ORANGE");
assert.strictEqual(tr.trend, "se intensifica");
const hit = T.affected(tr, munis);
assert.ok(hit.length > 0 && hit.every((x, i) => i === 0 || hit[i - 1].h <= x.h), "municipios ordenados por hora");

// Un solo modelo con tormenta: no alcanza el consenso mínimo (probabilidad 0,2 < 0,4)
assert.strictEqual(T.track(grid, build(["gfs_seamless"]), {nModels: 5}).length, 0);

// Viento del norte (0°) a 36 km/h: sopla hacia el sur -> v negativo
const f = T.windField(grid, new Array(N).fill(36), new Array(N).fill(0));
const [u, v] = f(-36.5, -60.1);
assert.ok(Math.abs(u) < 1e-6 && Math.abs(v + 36) < 1e-6);
assert.strictEqual(f(-20, -60), null);
assert.strictEqual(T.condition(2, 61), "light");
assert.strictEqual(T.condition(6, 63), "heavy");
assert.strictEqual(T.condition(1, 95), "storm");
console.log("tracking.js OK:", tr.dirText, tr.speed + " km/h,", tr.trend + ",", hit.length, "municipios");
