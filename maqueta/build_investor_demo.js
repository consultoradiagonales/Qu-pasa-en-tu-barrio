// Genera una demo HTML independiente para abrir y compartir sin servidor.
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
let html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const js = fs.readFileSync(path.join(root, 'app.js'), 'utf8');

html = html
  .replace('<title>¿Qué pasa en tu barrio? · Maqueta local</title>',
      '<title>¿Qué pasa en tu barrio? · Demo interactiva</title>')
  .replace('<link rel="stylesheet" href="styles.css">', `<style>\n${css}\n</style>`)
  .replace(/  <link rel="manifest" href="manifest.webmanifest">\n/, '')
  .replace(/  <link rel="icon" type="image\/svg\+xml" href="icon.svg">\n/, '')
  .replace(/  <link rel="apple-touch-icon" href="icon.svg">\n/, '')
  .replace('MAQUETA INTERACTIVA · V1', 'DEMO INTERACTIVA · INVERSORES')
  .replace('VISTA PREVIA / ANDROID + IOS', 'EXPERIENCIA MÓVIL / ANDROID + IOS')
  .replace('<script src="app.js"></script>',
      `<script>window.QPBTB_OFFLINE_DEMO=true;</script>\n  <script>\n${js}\n</script>`);

const destination = path.join(root, 'demo-inversores.html');
fs.writeFileSync(destination, html, 'utf8');
const hostingDir = path.join(root, 'dist');
fs.mkdirSync(hostingDir, {recursive: true});
fs.writeFileSync(path.join(hostingDir, 'index.html'), html, 'utf8');
process.stdout.write(`${destination}\n`);
