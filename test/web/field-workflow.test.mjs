import test from 'node:test';
import assert from 'node:assert/strict';
import { canActOnFieldTask, canStartFieldTask, runFieldEvidenceUpdate } from '../../web/admin/field-workflow.js';

test('solo quien inició el trabajo puede cargar avances o resolverlo', () => {
  const report = { status: 'in_progress', assignedWorkerId: 'worker-a' };
  assert.equal(canActOnFieldTask(report, 'worker-a'), true);
  assert.equal(canActOnFieldTask(report, 'worker-b'), false);
  assert.equal(canActOnFieldTask(report, undefined), false);
  assert.equal(canActOnFieldTask(report, ''), false);
  assert.equal(canActOnFieldTask({ status: 'in_progress' }, 'worker-a'), false);
  assert.equal(canActOnFieldTask({ status: 'assigned', assignedWorkerId: 'worker-a' }, 'worker-a'), false);
  assert.equal(canActOnFieldTask(null, 'worker-a'), false);
});

test('un trabajo asignado se puede iniciar solo si sigue en estado asignado', () => {
  assert.equal(canStartFieldTask({ status: 'assigned' }, 'worker-a'), true);
  assert.equal(canStartFieldTask({ status: 'in_progress', assignedWorkerId: 'worker-b' }, 'worker-a'), false);
  assert.equal(canStartFieldTask({ status: 'assigned' }, undefined), false);
});

test('si la verificación falla no se sube ninguna foto', async () => {
  let uploads = 0;
  await assert.rejects(
    runFieldEvidenceUpdate({
      verify: async () => 'Este trabajo está a cargo de otra persona.',
      upload: async () => { uploads += 1; return { url: 'u' }; },
      update: async () => {},
    }),
    /otra persona/,
  );
  assert.equal(uploads, 0);
});

test('si Firestore rechaza la escritura se borra la foto recién subida', async () => {
  const cleaned = [];
  const denied = Object.assign(new Error('Missing or insufficient permissions.'), { code: 'permission-denied' });
  await assert.rejects(
    runFieldEvidenceUpdate({
      verify: async () => null,
      upload: async () => ({ url: 'https://x/progress.jpg', reference: 'ref-1' }),
      update: async () => { throw denied; },
      cleanup: async (uploaded) => { cleaned.push(uploaded.reference); },
    }),
    (error) => {
      assert.match(error.message, /ya no está a tu cargo/);
      assert.match(error.message, /se descartó/);
      assert.equal(error.photoCleaned, true);
      assert.equal(error.cause, denied);
      return true;
    },
  );
  assert.deepEqual(cleaned, ['ref-1']);
});

test('el borrado es de mejor esfuerzo y no oculta el error original', async () => {
  await assert.rejects(
    runFieldEvidenceUpdate({
      upload: async () => ({ url: 'u', reference: 'ref-2' }),
      update: async () => { throw new Error('unavailable'); },
      cleanup: async () => { throw Object.assign(new Error('denied'), { code: 'storage/unauthorized' }); },
    }),
    (error) => {
      assert.match(error.message, /No se pudo guardar el cambio/);
      assert.match(error.message, /no pudo descartarse/);
      assert.equal(error.photoCleaned, false);
      return true;
    },
  );
});

test('con escritura exitosa devuelve la foto subida y no borra nada', async () => {
  let cleanups = 0;
  let written = null;
  const result = await runFieldEvidenceUpdate({
    verify: async () => null,
    upload: async () => ({ url: 'https://x/after.jpg', reference: 'ref-3' }),
    update: async (uploaded) => { written = uploaded.url; },
    cleanup: async () => { cleanups += 1; },
  });
  assert.equal(result.url, 'https://x/after.jpg');
  assert.equal(written, 'https://x/after.jpg');
  assert.equal(cleanups, 0);
});
