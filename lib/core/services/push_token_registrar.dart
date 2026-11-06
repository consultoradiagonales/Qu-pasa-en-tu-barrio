import 'dart:async';

import 'package:flutter/foundation.dart';

/// Registra el token FCM del dispositivo en `users/{uid}.fcmToken`.
///
/// Es independiente de Firebase a propósito (todo entra por funciones) para
/// poder probar los reintentos sin plataforma. Reglas de diseño:
/// - Se solicita el permiso antes del token, cuando el sistema todavía puede
///   mostrar la autorización. Si se rechaza o falla, igual se intenta guardar
///   el token para que la persona conserve la bandeja dentro de ConDi.
/// - Ningún error se traga sin dejar rastro en el log.
/// - Si algo falla (red, doc de usuario aún no creado al registrarse,
///   servicio de Google no disponible) se reintenta con espera creciente.
class PushTokenRegistrar {
  PushTokenRegistrar({
    required this.getToken,
    required this.saveToken,
    this.ensurePermission,
    this.retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ],
    this.log = _defaultLog,
  });

  final Future<String?> Function() getToken;
  final Future<void> Function(String uid, String token) saveToken;
  final Future<void> Function()? ensurePermission;
  final List<Duration> retryDelays;
  final void Function(String message) log;

  final Map<String, Future<bool>> _inFlight = {};

  static void _defaultLog(String message) => debugPrint(message);

  /// Devuelve true si el token quedó guardado. Llamadas simultáneas para el
  /// mismo uid comparten la misma ejecución.
  Future<bool> register(String uid) {
    return _inFlight[uid] ??= _run(uid).whenComplete(() {
      _inFlight.remove(uid);
    });
  }

  Future<bool> _run(String uid) async {
    await _askPermission();
    final attempts = retryDelays.length + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final token = await getToken();
        if (token == null || token.isEmpty) {
          throw StateError('getToken() devolvió un token vacío');
        }
        await saveToken(uid, token);
        log('Push: token FCM guardado (intento ${attempt + 1}).');
        return true;
      } catch (error) {
        log('Push: no se pudo registrar el token FCM '
            '(intento ${attempt + 1}/$attempts): $error');
        if (attempt < retryDelays.length) {
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
    }
    return false;
  }

  Future<void> _askPermission() async {
    final ask = ensurePermission;
    if (ask == null) return;
    try {
      await ask();
    } catch (error) {
      log('Push: no se pudo pedir el permiso de notificaciones: $error');
    }
  }
}
