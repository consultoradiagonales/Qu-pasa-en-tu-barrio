import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pide consentimiento expreso y, solo si la persona acepta, envía al servidor
/// los datos de su dispositivo y su ubicación. Los datos de la cuenta de Google
/// y la IP los toma el servidor; el cliente no los declara.
///
/// No se obtiene el número de teléfono ni las torres de celular: Android e iOS
/// no los entregan a una app común y Google Play y Apple rechazan pedirlos.
class DeviceProfileService {
  DeviceProfileService._();

  static const _channel =
      MethodChannel('ar.com.consultoradiagonales.condi/device');
  static const _prefKey = 'device_consent_v1';
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Muestra el aviso una sola vez por instalación, a quien ya inició sesión.
  static Future<void> askIfNeeded(BuildContext context) async {
    if (kIsWeb || FirebaseAuth.instance.currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final decided = prefs.getString(_prefKey);
      if (decided == 'granted') {
        await _send(); // refresca modelo, versión y ubicación
        return;
      }
      if (decided == 'denied' || !context.mounted) return;

      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('¿Nos ayudás a cuidar tu barrio?'),
          content: const SingleChildScrollView(
            child: Text(
              'Si aceptás, guardamos de forma segura:\n\n'
              '• Tu ubicación aproximada\n'
              '• El modelo de tu celular y la versión de la app\n'
              '• Tu nombre y correo de Google\n'
              '• Tu dirección IP\n\n'
              'Los usamos para enviarte alertas del clima de tu zona y mejorar '
              'el servicio. Solo los ve el equipo administrador. Podés retirar '
              'tu consentimiento cuando quieras desde Mi cuenta.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No, gracias'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Acepto'),
            ),
          ],
        ),
      );
      await prefs.setString(_prefKey, accepted == true ? 'granted' : 'denied');
      if (accepted == true) await _send();
    } catch (_) {
      // Es información complementaria: nunca debe molestar al reporte.
    }
  }

  /// Retira el consentimiento y borra lo guardado en el servidor.
  static Future<void> withdraw() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, 'denied');
    await _functions.httpsCallable('deleteDeviceProfile').call();
  }

  static Future<void> _send() async {
    final device = await _deviceInfo();
    final location = await _location();
    await _functions.httpsCallable('saveDeviceProfile').call({
      'consent': true,
      'device': device,
      if (location != null) 'location': location,
    });
  }

  static Future<Map<String, String>> _deviceInfo() async {
    final package = await PackageInfo.fromPlatform();
    final base = <String, String>{
      'appVersion': '${package.version}+${package.buildNumber}',
      'locale': Platform.localeName,
    };
    if (Platform.isAndroid) {
      try {
        final info = await _channel.invokeMapMethod<String, String>('info');
        return {...base, 'platform': 'android', ...?info};
      } catch (_) {
        return {...base, 'platform': 'android'};
      }
    }
    if (Platform.isIOS) {
      return {
        ...base,
        'platform': 'ios',
        'manufacturer': 'Apple',
        'osVersion': Platform.operatingSystemVersion,
      };
    }
    return base;
  }

  /// Solo usa la ubicación si el permiso ya fue concedido: este aviso no pide
  /// permisos del sistema por su cuenta.
  static Future<Map<String, double>?> _location() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            ),
          );
      return {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracyM': position.accuracy,
      };
    } catch (_) {
      return null;
    }
  }
}
