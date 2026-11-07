import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestiona el consentimiento para una medición territorial mínima.
///
/// La app registra como máximo un uso diario por cuenta, agrupado por la
/// ciudad/municipio que la persona eligió en su perfil. No recopila ni guarda
/// IP, ubicación exacta, fotos, correo, nombre ni datos del dispositivo.
class DeviceProfileService {
  DeviceProfileService._();

  static const _prefKey = 'territorial_usage_consent_v2';
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Pregunta una única vez luego de iniciar sesión. Si la persona ya aceptó,
  /// registra la presencia diaria sin interrumpir el uso de la app.
  static Future<void> askIfNeeded(BuildContext context) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final decision = prefs.getString(_prefKey);
      if (decision == 'granted') {
        await recordUsageIfAllowed();
        return;
      }
      if (decision == 'denied' || !context.mounted) return;
      await requestConsent(context);
    } catch (_) {
      // La analítica nunca interfiere con el reporte ni con el acceso.
    }
  }

  /// Permite volver a elegir la preferencia desde Mi perfil.
  static Future<bool> requestConsent(BuildContext context) async {
    if (FirebaseAuth.instance.currentUser == null || !context.mounted) {
      return false;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Medición territorial de uso'),
        content: const SingleChildScrollView(
          child: Text(
            'Si aceptás, ConDi registra un conteo diario de uso agrupado por '
            'la ciudad o municipio que elegiste en tu perfil.\n\n'
            'No guardamos tu dirección IP, ubicación exacta, fotos, correo, '
            'nombre ni identificadores del dispositivo para esta medición.\n\n'
            'El equipo de gestión solo ve resultados agregados. Podés '
            'desactivarla y borrar tu consentimiento desde Mi perfil.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, gracias'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acepto'),
          ),
        ],
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    if (accepted != true) {
      await prefs.setString(_prefKey, 'denied');
      try {
        await _functions.httpsCallable('deleteDeviceProfile').call();
      } catch (_) {}
      return false;
    }
    await _functions.httpsCallable('saveDeviceProfile').call({'consent': true});
    await prefs.setString(_prefKey, 'granted');
    await recordUsageIfAllowed();
    return true;
  }

  /// Envía el conteo solo cuando existe consentimiento vigente. El servidor
  /// vuelve a validarlo y deduplica por cuenta y por día.
  static Future<void> recordUsageIfAllowed() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefKey) != 'granted') return;
    try {
      await _functions.httpsCallable('recordUsagePresence').call();
    } catch (_) {
      // Se reintenta naturalmente en la próxima apertura de la app.
    }
  }

  /// Retira el consentimiento y borra el único registro personal asociado.
  /// Los conteos históricos ya son agregados y no contienen identidad ni IP.
  static Future<void> withdraw() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, 'denied');
    await _functions.httpsCallable('deleteDeviceProfile').call();
  }
}
