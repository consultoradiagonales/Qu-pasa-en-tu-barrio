import test from 'node:test';
import assert from 'node:assert/strict';
import { formatReceiptLatency, reportReceiptLatency } from '../../web/admin/report-realtime.js';

test('mide la demora de recepción sin aceptar latencias negativas', () => {
  assert.equal(reportReceiptLatency(1000, 1450), 450);
  assert.equal(reportReceiptLatency(2000, 1450), 0);
  assert.equal(reportReceiptLatency(undefined, 1450), null);
});

test('muestra milisegundos, segundos y minutos legibles', () => {
  assert.equal(formatReceiptLatency(450), '450 ms');
  assert.equal(formatReceiptLatency(1250), '1,3 s');
  assert.equal(formatReceiptLatency(65000), '1 min 5 s');
});
