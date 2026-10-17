import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// Permisos que se usan al crear evidencia de un reporte urbano.
class ReportPermissions {
  static Future<bool> requestEssential() async {
    final results = await [
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.notification,
    ].request();
    return results[Permission.locationWhenInUse]?.isGranted ?? false;
  }

  static Future<bool> requestCamera() async =>
      (await Permission.camera.request()).isGranted;

  /// Android usa el selector de fotos del sistema: no pide acceso amplio a
  /// imágenes, que no es necesario para adjuntar evidencia al reporte.
  static Future<bool> requestPhotos() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return true;
    final photos = await Permission.photos.request();
    return photos.isGranted || photos.isLimited;
  }

  static Future<bool> openSettings() => openAppSettings();
}
