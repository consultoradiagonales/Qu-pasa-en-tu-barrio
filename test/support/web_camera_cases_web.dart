import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:que_pasa_en_tu_barrio/features/report/camera/web_camera_capture.dart';

@JS('Function')
extension type _Script._(JSFunction _) implements JSFunction {
  external _Script(String body);
}

@JS('__condiCameraCheck')
external bool get _checkResult;
@JS('__condiCameraText')
external String get _textResult;

const _cameraReady = '!document.getElementById("condi-camera-capture").disabled '
    '&& !document.getElementById("condi-camera-capture").hidden';

void _run(String body) => _Script(body).callAsFunction();
bool _check(String expression) {
  _run('window.__condiCameraCheck = !!($expression);');
  return _checkResult;
}

String _text(String expression) {
  _run('window.__condiCameraText = String($expression);');
  return _textResult;
}

void _click(String id) => _run('document.getElementById("$id").click();');

Future<void> _until(String condition) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (_check(condition)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('No se cumplió la condición de cámara: $condition');
}

void runWebCameraTests() {
  setUp(() {
    _run('''
      const state = window.__condiCameraTest = {
        original: navigator.mediaDevices.getUserMedia,
        tracks: [], calls: 0, requested: []
      };
      Object.defineProperty(navigator, 'userActivation', {
        configurable: true, value: {isActive: false}
      });
      state.makeStream = () => {
        const canvas = document.createElement('canvas');
        canvas.width = 640; canvas.height = 480;
        const context = canvas.getContext('2d');
        context.fillStyle = '#1268c4'; context.fillRect(0, 0, 640, 480);
        const stream = canvas.captureStream(15);
        state.tracks.push(...stream.getTracks());
        return stream;
      };
      navigator.mediaDevices.getUserMedia = async constraints => {
        state.calls++; state.requested.push(constraints);
        return state.makeStream();
      };
    ''');
  });
  tearDown(() {
    _run('''
      document.getElementById('condi-camera-cancel')?.click();
      const state = window.__condiCameraTest;
      state.tracks.forEach(track => track.stop());
      navigator.mediaDevices.getUserMedia = state.original;
      delete navigator.userActivation;
    ''');
  });

  test('no solicita permiso sin gesto y libera cámara al repetir/cancelar',
      () async {
    final result = captureWebCameraPhoto();
    expect(_check('window.__condiCameraTest.calls === 0'), isTrue);
    _click('condi-camera-activate');
    await _until(_cameraReady);
    expect(_check('window.__condiCameraTest.requested[0].audio === false'),
        isTrue);
    _click('condi-camera-capture');
    expect(
        _check('window.__condiCameraTest.tracks.every(t => '
            't.readyState === "ended")'),
        isTrue);
    expect(
        _check('!document.getElementById("condi-camera-use").hidden'), isTrue);
    _click('condi-camera-repeat');
    await _until('window.__condiCameraTest.calls === 2 && $_cameraReady');
    _click('condi-camera-cancel');
    expect(await result, isNull);
    expect(
        _check('window.__condiCameraTest.tracks.every(t => '
            't.readyState === "ended")'),
        isTrue);
    expect(_check('document.getElementById("condi-camera-dialog") === null'),
        isTrue);
  });

  test('entrega JPEG legible desde la ruta XFile usada por el reporte',
      () async {
    final result = captureWebCameraPhoto();
    _click('condi-camera-activate');
    await _until(_cameraReady);
    _click('condi-camera-capture');
    _click('condi-camera-use');
    final photo = await result;
    expect(photo, isNotNull);
    expect(photo!.mimeType, 'image/jpeg');
    final bytes = await XFile(photo.path).readAsBytes();
    expect(bytes.take(2), [0xff, 0xd8]);
    expect(bytes.length, greaterThan(100));
    expect(
        _check('window.__condiCameraTest.tracks.every(t => '
            't.readyState === "ended")'),
        isTrue);
  });

  test('permiso denegado muestra ayuda sin abrir selector de archivos',
      () async {
    _run('navigator.mediaDevices.getUserMedia = async () => '
        '{ throw new DOMException("blocked", "NotAllowedError"); };');
    final result = captureWebCameraPhoto();
    _click('condi-camera-activate');
    await _until('document.querySelector("#condi-camera-dialog [role=status]")'
        '.textContent.includes("Permití")');
    expect(
        _text('document.querySelector('
            '"#condi-camera-dialog [role=status]").textContent'),
        contains('permisos del navegador'));
    expect(
        _check('document.querySelector('
            '"#condi-camera-dialog input[type=file]") === null'),
        isTrue);
    _click('condi-camera-cancel');
    expect(await result, isNull);
  });

  test('cancelar mientras se espera permiso detiene el stream que llega tarde',
      () async {
    _run('navigator.mediaDevices.getUserMedia = () => new Promise(resolve => '
        '{ window.__condiCameraTest.resolve = resolve; });');
    final result = captureWebCameraPhoto();
    _click('condi-camera-activate');
    _click('condi-camera-cancel');
    expect(await result, isNull);
    _run('window.__condiCameraTest.resolve('
        'window.__condiCameraTest.makeStream());');
    await _until('window.__condiCameraTest.tracks.length > 0 && '
        'window.__condiCameraTest.tracks.every(t => t.readyState === "ended")');
  });
}
