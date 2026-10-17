'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { saveDeviceProfileHandler, sendCustomMessageHandler, cleanText } = require('./user-messaging');

test('sin consentimiento no se guarda el perfil del dispositivo', async () => {
  await assert.rejects(
    saveDeviceProfileHandler({ auth: { uid: 'u1', token: {} }, data: { consent: false } }),
    (error) => error.code === 'failed-precondition',
  );
  await assert.rejects(
    saveDeviceProfileHandler({ data: { consent: true } }),
    (error) => error.code === 'unauthenticated',
  );
});

test('enviar mensajes exige sesion iniciada', async () => {
  await assert.rejects(
    sendCustomMessageHandler({ data: {} }),
    (error) => error.code === 'unauthenticated',
  );
});

test('cleanText quita enlaces y caracteres de control', () => {
  assert.equal(cleanText('Hola\n https://x.com/a  mundo', 50), 'Hola [enlace omitido] mundo');
  assert.equal(cleanText(5, 10), '');
});
