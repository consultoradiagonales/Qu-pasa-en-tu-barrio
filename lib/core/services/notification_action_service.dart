import 'package:url_launcher/url_launcher.dart';

const androidPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi';
const androidInternalTestUrl =
    'https://play.google.com/apps/internaltest/4701647237677047143';

typedef NotificationActionLookup = Future<Map<String, dynamic>?> Function(
  String notificationId,
);
typedef NotificationActionLauncher = Future<bool> Function(Uri uri);

Uri? trustedNotificationActionUri(Map<String, dynamic> data) {
  final value = data['actionUrl'];
  if (value is! String) return null;
  final text = value.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }

  if (text == androidPlayStoreUrl || text == androidInternalTestUrl) {
    return uri;
  }

  // iOS todavía no está publicado, pero el manejador queda preparado para
  // aceptar únicamente fichas reales de App Store cuando exista su URL.
  if (uri.host.toLowerCase() == 'apps.apple.com' &&
      uri.pathSegments.contains('app') &&
      uri.pathSegments.any((segment) => RegExp(r'^id\d+$').hasMatch(segment))) {
    return uri;
  }
  return null;
}

Future<bool> launchTrustedNotificationAction(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Resuelve una acción segura desde el payload. Los pushes antiguos traen
/// solamente notificationId, por lo que pueden recuperar actionUrl desde el
/// documento de la bandeja antes de abrir la tienda.
Future<bool> openNotificationAction(
  Map<String, dynamic> data, {
  NotificationActionLookup? lookupById,
  NotificationActionLauncher? launcher,
}) async {
  var uri = trustedNotificationActionUri(data);
  if (uri == null && lookupById != null) {
    final notificationId = data['notificationId'];
    if (notificationId is String &&
        RegExp(r'^[A-Za-z0-9_-]{1,240}$').hasMatch(notificationId)) {
      try {
        final stored = await lookupById(notificationId);
        if (stored != null) uri = trustedNotificationActionUri(stored);
      } catch (_) {
        return false;
      }
    }
  }
  if (uri == null) return false;

  try {
    return await (launcher ?? launchTrustedNotificationAction)(uri);
  } catch (_) {
    return false;
  }
}
