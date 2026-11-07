'use strict';

// Doble mínimo de Firestore para tests de entrega de mensajes (sin red).
class FakeDb {
  constructor(seed = {}) {
    this.data = new Map(); // "coleccion/id" -> objeto
    this.failCreateFor = new Set();
    for (const [path, value] of Object.entries(seed)) this.data.set(path, { ...value });
  }

  collection(name) {
    return new FakeCollection(this, name, []);
  }

  get(path) { return this.data.get(path); }
}

class FakeCollection {
  constructor(db, name, filters) {
    this.db = db;
    this.name = name;
    this.filters = filters;
  }

  doc(id) { return new FakeDoc(this.db, this.name, id); }

  where(field, op, value) {
    if (op !== '==') throw new Error('operador no soportado en el fake');
    return new FakeCollection(this.db, this.name, [...this.filters, [field, value]]);
  }

  async get() {
    const docs = [];
    for (const [path, value] of this.db.data) {
      const [col, ...rest] = path.split('/');
      if (col !== this.name) continue;
      if (this.filters.every(([f, v]) => value[f] === v)) {
        docs.push(new FakeSnap(rest.join('/'), value));
      }
    }
    return { docs, empty: docs.length === 0, size: docs.length };
  }
}

class FakeSnap {
  constructor(id, value) {
    this.id = id;
    this._value = value;
    this.exists = value !== undefined;
  }

  get(field) { return this._value ? this._value[field] : undefined; }

  data() { return this._value; }
}

function isDelete(v) {
  return v && typeof v === 'object' && /delete/i.test(String(v.constructor?.name || '')) ;
}

class FakeDoc {
  constructor(db, col, id) {
    this.db = db;
    this.id = id;
    this.path = `${col}/${id}`;
  }

  async get() {
    const v = this.db.data.get(this.path);
    return new FakeSnap(this.id, v === undefined ? undefined : { ...v });
  }

  async create(value) {
    if (this.db.failCreateFor.has(this.id)) {
      const e = new Error('boom');
      e.code = 'unavailable';
      throw e;
    }
    if (this.db.data.has(this.path)) {
      const e = new Error('already exists');
      e.code = 6;
      throw e;
    }
    this.db.data.set(this.path, { ...value });
  }

  async set(value, options) {
    const prev = options?.merge ? this.db.data.get(this.path) || {} : {};
    this.db.data.set(this.path, { ...prev, ...value });
  }

  async update(value) {
    if (!this.db.data.has(this.path)) {
      const e = new Error('not found');
      e.code = 5;
      throw e;
    }
    this.db.data.set(this.path, { ...this.db.data.get(this.path), ...value });
  }

  async delete() { this.db.data.delete(this.path); }
}

/** Mock de getMessaging: `plan(messages, call)` devuelve el array de responses. */
function fakeMessaging(plan) {
  const calls = [];
  const impl = {
    calls,
    async sendEach(messages) {
      calls.push(messages);
      if (plan) return plan(messages, calls.length);
      return { responses: messages.map(() => ({ success: true })) };
    },
  };
  const provider = () => impl;
  provider.impl = impl;
  return provider;
}

module.exports = { FakeDb, fakeMessaging, isDelete };
