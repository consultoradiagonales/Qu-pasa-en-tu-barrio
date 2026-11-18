'use strict';
// Instala dobles de firebase-admin/firestore y firebase-admin/messaging en
// require.cache ANTES de cargar los módulos del proyecto. Sin red ni credenciales.
const Module = require('node:module');

const FUNCTIONS_DIR = require('node:path').join(__dirname, '..');
const resolveFrom = (id) => require.resolve(id, { paths: [FUNCTIONS_DIR] });

class FakeServerTimestamp {}
class FakeFieldDelete {}
const FieldValue = {
  serverTimestamp: () => new FakeServerTimestamp(),
  delete: () => new FakeFieldDelete(),
};

const state = { db: null, messaging: null };

function install(id, exportsObj) {
  const file = resolveFrom(id);
  const m = new Module(file);
  m.filename = file;
  m.loaded = true;
  m.exports = exportsObj;
  require.cache[file] = m;
}

const realFirestore = require(resolveFrom('firebase-admin/firestore'));
install('firebase-admin/firestore', {
  FieldPath: realFirestore.FieldPath,
  Timestamp: realFirestore.Timestamp,
  FieldValue,
  getFirestore: () => {
    if (!state.db) throw new Error('stub: db no configurada');
    return state.db;
  },
});
install('firebase-admin/messaging', {
  getMessaging: () => {
    if (!state.messaging) throw new Error('stub: messaging no configurado');
    return state.messaging;
  },
});

/** Messaging doble con send() y sendEach(); `plan(token)` devuelve null o un error. */
function makeMessaging(plan = () => null) {
  const sent = [];
  return {
    sent,
    async send(message) {
      sent.push(message);
      const err = plan(message.token);
      if (err) throw err;
      return 'msg-id';
    },
    async sendEach(messages) {
      sent.push(...messages);
      return { responses: messages.map((m) => {
        const err = plan(m.token);
        return err ? { success: false, error: err } : { success: true };
      }) };
    },
  };
}

const { FakeDb } = require('./fake-firestore');

module.exports = { state, FieldValue, FakeFieldDelete, makeMessaging, FakeDb, FUNCTIONS_DIR };
