import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'web_camera_errors.dart';

@JS('window')
external _CameraWindow get _window;
@JS('document')
external _CameraDocument get _document;
@JS('navigator')
external _CameraNavigator get _navigator;

extension type _CameraWindow(JSObject _) implements JSObject {
  external bool get isSecureContext;
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}

extension type _CameraDocument(JSObject _) implements JSObject {
  external _CameraElement? get body;
  external _CameraElement createElement(String name);
  external String get visibilityState;
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}

extension type _CameraNavigator(JSObject _) implements JSObject {
  external _MediaDevices? get mediaDevices;
  external _UserActivation? get userActivation;
}

extension type _UserActivation(JSObject _) implements JSObject {
  external bool get isActive;
}

extension type _MediaDevices(JSObject _) implements JSObject {
  external JSPromise<_CameraStream> getUserMedia(
      _CameraConstraints constraints);
}

extension type _CameraConstraints._(JSObject _) implements JSObject {
  external factory _CameraConstraints({
    _VideoConstraints video,
    bool audio,
  });
}

extension type _VideoConstraints._(JSObject _) implements JSObject {
  external factory _VideoConstraints({
    _PreferredFacingMode facingMode,
    _PreferredSize width,
    _PreferredSize height,
  });
}

extension type _PreferredFacingMode._(JSObject _) implements JSObject {
  external factory _PreferredFacingMode({String ideal});
}

extension type _PreferredSize._(JSObject _) implements JSObject {
  external factory _PreferredSize({int ideal});
}

extension type _CameraStream(JSObject _) implements JSObject {
  external JSArray<_CameraTrack> getTracks();
}

extension type _CameraTrack(JSObject _) implements JSObject {
  external void stop();
  external void addEventListener(String type, JSFunction callback);
}

extension type _CameraElement(JSObject _) implements JSObject {
  external set textContent(String value);
  external void setAttribute(String name, String value);
  external void appendChild(_CameraElement child);
  external void remove();
  external void addEventListener(String type, JSFunction callback);
  external void showModal();
  external void close();
  external void focus();
  external set hidden(bool value);
  external set disabled(bool value);
  external set src(String value);
  external set srcObject(_CameraStream? value);
  external set muted(bool value);
  external set autoplay(bool value);
  external int get videoWidth;
  external int get videoHeight;
  external set width(int value);
  external set height(int value);
  external _CameraCanvasContext? getContext(String name);
  external String toDataURL(String type, double quality);
  external JSPromise<JSAny?> play();
}

extension type _CameraCanvasContext(JSObject _) implements JSObject {
  external void drawImage(_CameraElement video, int x, int y, int w, int h);
}

/// Opens the live browser camera. No file picker or microphone is requested.
///
/// The native mobile implementation remains in ReportCaptureService. Browser
/// bindings are isolated here so mobile builds never import browser libraries.
Future<XFile?> captureWebCameraPhoto() {
  if (!_window.isSecureContext) {
    throw StateError('Para usar la cámara abrí ConDi mediante HTTPS.');
  }
  if (_navigator.mediaDevices == null) {
    throw StateError('Este navegador no permite acceder a la cámara. '
        'Abrí ConDi con Safari o Chrome actualizado.');
  }
  return _BrowserCameraSession().open();
}

class _BrowserCameraSession {
  final _result = Completer<XFile?>();
  late final _CameraElement _dialog;
  late final _CameraElement _style;
  late final _CameraElement _video;
  late final _CameraElement _image;
  late final _CameraElement _status;
  late final _CameraElement _activate;
  late final _CameraElement _capture;
  late final _CameraElement _repeat;
  late final _CameraElement _usePhoto;
  late final JSFunction _leavePage;
  late final JSFunction _visibilityChanged;
  _CameraStream? _stream;
  Uint8List? _photo;
  bool _closed = false;
  bool _requesting = false;

  static const _mediaStyle = 'width:100%;max-height:55dvh;object-fit:contain;'
      'border-radius:12px;background:#102030;';

  Future<XFile?> open() {
    final activeGesture = _navigator.userActivation?.isActive ?? false;
    _dialog = _element('dialog',
        style: 'border:0;border-radius:18px;padding:20px;width:min(92vw,720px);'
            'max-height:94dvh;overflow:auto;box-sizing:border-box;'
            'background:#f8fafc;color:#14283f;font:16px/1.4 Arial,sans-serif;');
    _dialog.setAttribute('id', 'condi-camera-dialog');
    _dialog.setAttribute('aria-labelledby', 'condi-camera-title');
    _dialog.setAttribute('aria-modal', 'true');
    final title = _element('h2', text: 'Cámara', style: 'margin:0 0 12px;');
    title.setAttribute('id', 'condi-camera-title');
    _dialog.appendChild(title);
    _style = _element('style',
        text: '#condi-camera-dialog::backdrop{background:rgba(8,22,45,.75)}'
            '#condi-camera-dialog [hidden]{display:none!important}'
            '#condi-camera-dialog button:focus-visible{outline:3px solid '
            '#eaa833;outline-offset:3px}');
    _dialog.appendChild(_style);
    _video = _element('video', style: _mediaStyle)
      ..muted = true
      ..autoplay = true;
    _video.setAttribute('playsinline', '');
    _video.setAttribute('aria-label', 'Vista en vivo de la cámara');
    _video.addEventListener(
        'loadedmetadata',
        (() {
          if (!_closed && _stream != null && _video.videoWidth > 0) {
            _capture.disabled = false;
          }
        }).toJS);
    _image = _element('img', style: _mediaStyle)..hidden = true;
    _image.setAttribute('alt', 'Foto recién tomada');
    _dialog.appendChild(_video);
    _dialog.appendChild(_image);
    _status = _element('p',
        text: 'Activá la cámara para fotografiar el problema. '
            'No se usa el micrófono.',
        style: 'margin:12px 0;');
    _status.setAttribute('role', 'status');
    _status.setAttribute('aria-live', 'polite');
    _dialog.appendChild(_status);
    final controls = _element('div',
        style: 'display:flex;flex-wrap:wrap;gap:10px;margin-top:16px;');
    _activate = _button(
        'Activar cámara', 'condi-camera-activate', () => unawaited(_start()),
        primary: true);
    _capture =
        _button('Sacar foto', 'condi-camera-capture', _takePhoto, primary: true)
          ..hidden = true
          ..disabled = true;
    _repeat = _button('Repetir', 'condi-camera-repeat', () {
      _photo = null;
      _image
        ..src = ''
        ..hidden = true;
      unawaited(_start());
    })
      ..hidden = true;
    _usePhoto = _button('Usar foto', 'condi-camera-use', () {
      final bytes = _photo;
      if (bytes == null) return;
      _finish(XFile.fromData(bytes,
          mimeType: 'image/jpeg',
          name: 'condi-${DateTime.now().millisecondsSinceEpoch}.jpg'));
    }, primary: true)
      ..hidden = true;
    for (final button in [
      _activate,
      _capture,
      _repeat,
      _usePhoto,
      _button('Cancelar', 'condi-camera-cancel', () => _finish(null)),
    ]) {
      controls.appendChild(button);
    }
    _dialog.appendChild(controls);
    _leavePage = (() => _finish(null)).toJS;
    _visibilityChanged = (() {
      if (_document.visibilityState == 'hidden') _finish(null);
    }).toJS;
    _window.addEventListener('pagehide', _leavePage);
    _window.addEventListener('hashchange', _leavePage);
    _document.addEventListener('visibilitychange', _visibilityChanged);
    _dialog.addEventListener('cancel', _leavePage);
    _dialog.addEventListener('close', _leavePage);
    _document.body!.appendChild(_dialog);
    try {
      _dialog.showModal();
    } catch (_) {
      _finish(null);
      throw StateError('No se pudo abrir la cámara. '
          'Probá con Safari o Chrome actualizado.');
    }
    // Automatic route initialization must never trigger a permission prompt.
    // Older browsers without UserActivation use the explicit activation button.
    if (activeGesture) unawaited(_start());
    return _result.future;
  }

  Future<void> _start() async {
    if (_requesting || _closed) return;
    _requesting = true;
    _activate.disabled = true;
    _capture
      ..hidden = true
      ..disabled = true;
    _repeat.hidden = true;
    _usePhoto.hidden = true;
    _video.hidden = false;
    _status.textContent = 'Esperando el permiso de la cámara…';
    try {
      final stream = await _navigator.mediaDevices!
          .getUserMedia(_CameraConstraints(
            audio: false,
            video: _VideoConstraints(
              facingMode: _PreferredFacingMode(ideal: 'environment'),
              width: _PreferredSize(ideal: 1600),
              height: _PreferredSize(ideal: 1200),
            ),
          ))
          .toDart;
      // The user can cancel while the browser permission dialog is still open.
      if (_closed) {
        _stopStream(stream);
        return;
      }
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      if (_closed) return;
      _activate.hidden = true;
      _capture
        ..hidden = false
        ..disabled = _video.videoWidth == 0;
      _status.textContent = 'Encuadrá el problema y tocá Sacar foto.';
      for (final track in stream.getTracks().toDart) {
        track.addEventListener(
            'ended',
            (() {
              if (!_closed && _stream == stream && _photo == null) {
                _stopCamera();
                _capture.hidden = true;
                _activate
                  ..hidden = false
                  ..disabled = false;
                _status.textContent = 'Se cerró la cámara. Volvé a activarla.';
              }
            }).toJS);
      }
      _capture.focus();
    } catch (error) {
      _stopCamera();
      if (!_closed) {
        _activate
          ..hidden = false
          ..textContent = 'Volver a intentar';
        _status.textContent = webCameraErrorMessage(error);
      }
    } finally {
      _requesting = false;
      if (!_closed) _activate.disabled = false;
    }
  }

  void _takePhoto() {
    if (_closed || _stream == null) return;
    final videoWidth = _video.videoWidth;
    final videoHeight = _video.videoHeight;
    if (videoWidth <= 0 || videoHeight <= 0) return;
    try {
      final scale = math.min(1.0, 1600 / math.max(videoWidth, videoHeight));
      final width = math.max(1, (videoWidth * scale).round());
      final height = math.max(1, (videoHeight * scale).round());
      final canvas = _element('canvas')
        ..width = width
        ..height = height;
      final context = canvas.getContext('2d');
      if (context == null) throw StateError('No se pudo tomar la foto.');
      context.drawImage(_video, 0, 0, width, height);
      final dataUrl = canvas.toDataURL('image/jpeg', 0.85);
      _photo = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
      _image
        ..src = dataUrl
        ..hidden = false;
      _video.hidden = true;
      _stopCamera();
      _capture.hidden = true;
      _activate.hidden = true;
      _repeat.hidden = false;
      _usePhoto.hidden = false;
      _status.textContent = 'Revisá la foto antes de usarla en el reporte.';
      _usePhoto.focus();
    } catch (_) {
      _status.textContent = 'No se pudo tomar la foto. Volvé a intentar.';
    }
  }

  void _finish(XFile? photo) {
    if (_closed) return;
    _closed = true;
    _stopCamera();
    _window.removeEventListener('pagehide', _leavePage);
    _window.removeEventListener('hashchange', _leavePage);
    _document.removeEventListener('visibilitychange', _visibilityChanged);
    _dialog.close();
    _dialog.remove();
    if (!_result.isCompleted) _result.complete(photo);
  }

  void _stopCamera() {
    final stream = _stream;
    _stream = null;
    _video.srcObject = null;
    if (stream != null) _stopStream(stream);
  }

  static void _stopStream(_CameraStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  static _CameraElement _element(String tag, {String? text, String? style}) {
    final element = _document.createElement(tag);
    if (text != null) element.textContent = text;
    if (style != null) element.setAttribute('style', style);
    return element;
  }

  static _CameraElement _button(String label, String id, void Function() onTap,
      {bool primary = false}) {
    final button = _element('button',
        text: label,
        style: 'min-height:44px;padding:10px 16px;border-radius:9px;'
            'border:1px solid #1268c4;font:600 16px Arial,sans-serif;'
            'cursor:pointer;background:${primary ? '#1268c4' : '#fff'};'
            'color:${primary ? '#fff' : '#1268c4'};');
    button.setAttribute('id', id);
    button.setAttribute('type', 'button');
    button.addEventListener('click', onTap.toJS);
    return button;
  }
}
