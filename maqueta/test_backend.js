const {test} = require('node:test');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const net = require('node:net');
const {setTimeout: delay} = require('node:timers/promises');

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

test('SQLite persiste el flujo y publica cambios en tiempo real', async (t) => {
  const port = await freePort();
  const base = `http://127.0.0.1:${port}`;
  const server = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: {...process.env, PORT: String(port), DB_PATH: ':memory:'},
    stdio: 'ignore',
  });
  t.after(() => server.kill());

  let ready = false;
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      const health = await fetch(`${base}/api/health`);
      ready = health.ok;
      if (ready) break;
    } catch {}
    await delay(100);
  }
  assert.ok(ready, 'El servidor debe iniciar');

  const controller = new AbortController();
  t.after(() => controller.abort());
  const events = await fetch(`${base}/api/events`, {signal: controller.signal});
  assert.equal(events.status, 200);
  const reader = events.body.getReader();
  const firstEvent = new TextDecoder().decode((await reader.read()).value);
  assert.match(firstEvent, /"revision":0/);

  async function action(input) {
    const response = await fetch(`${base}/api/actions`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(input),
    });
    return {status: response.status, body: await response.json()};
  }

  const created = await action({action:'create',title:'Bache de prueba',description:'La vereda está rota.',category:'Infraestructura'});
  assert.equal(created.status, 200);
  const id = created.body.id;
  assert.ok(id);
  const updateEvent = new TextDecoder().decode((await reader.read()).value);
  assert.match(updateEvent, new RegExp(id));

  assert.equal((await action({action:'finish',id})).status, 409);
  assert.equal((await action({action:'assign',id,teamId:'norte'})).status, 200);
  assert.equal((await action({action:'arrive',id})).status, 200);
  assert.equal((await action({action:'progress_photo',id})).status, 200);
  assert.equal((await action({action:'finish',id,note:'Trabajo concluido.'})).status, 200);
  assert.equal((await action({action:'rate',id,rating:5})).status, 200);

  const state = await (await fetch(`${base}/api/bootstrap`)).json();
  const report = state.reports.find(item => item.id === id);
  assert.equal(report.status, 'resolved');
  assert.equal(report.progressPhotos, 1);
  assert.equal(report.rating, 5);
  assert.equal(report.note, 'Trabajo concluido.');
  assert.ok(state.notifications.some(item => item.reportId === id && item.title === '¡Problema resuelto!'));

  const analytics = await (await fetch(`${base}/api/analytics`)).json();
  assert.equal(analytics.total, 4);
  assert.equal(analytics.byStatus.resolved, 2);
  assert.ok(analytics.avgResolutionHours !== null);

  assert.equal((await action({action:'reset'})).status, 200);
  const restored = await (await fetch(`${base}/api/bootstrap`)).json();
  assert.equal(restored.reports.length, 3);
  assert.equal(restored.reports.find(item => item.id === 'r101').status, 'pending');
});
