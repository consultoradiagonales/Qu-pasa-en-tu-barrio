import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

typedef LocalNotificationTapHandler = Future<void> Function(
  Map<String, dynamic> data,
);

String? encodeNotificationPayload(Map<String, dynamic> data) {
  final payload = <String, String>{};
  for (final entry in data.entries) {
    final value = entry.value;
    if (value is String || value is num || value is bool) {
      payload[entry.key] = value.toString();
    }
  }
  return payload.isEmpty ? null : jsonEncode(payload);
}

Map<String, dynamic> decodeNotificationPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return const {};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  } catch (_) {
    return const {};
  }
}

class LocalNotificationService {
  LocalNotificationService._();

  static const _morningId = 1001;
  static const _eveningId = 1002;
  static const _previewId = 1003;
  static const _updatesChannelId = 'condi_report_updates';
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<Map<String, dynamic>?> initialize({
    LocalNotificationTapHandler? onNotificationTap,
  }) async {
    if (kIsWeb) return null;
    tz.initializeTimeZones();
    final deviceTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(deviceTimezone.identifier));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final data = decodeNotificationPayload(response.payload);
        if (data.isNotEmpty && onNotificationTap != null) {
          unawaited(onNotificationTap(data));
        }
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _updatesChannelId,
        'Actualizaciones de reportes',
        description: 'Avisos sobre el estado de los reportes enviados',
        importance: Importance.high,
      ),
    );
    // Cancela los recordatorios fijos de versiones anteriores. A partir de
    // ahora las notificaciones se originan únicamente en acciones reales del
    // municipio: mensajes del panel, actualizaciones de reportes y alertas.
    await _plugin.cancel(id: _morningId);
    await _plugin.cancel(id: _eveningId);
    await _plugin.cancel(id: _previewId);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp != true) return null;
    final data = decodeNotificationPayload(
      launchDetails?.notificationResponse?.payload,
    );
    return data.isEmpty ? null : data;
  }

  /// Muestra un aviso que llegó por FCM cuando la aplicación está abierta.
  /// En segundo plano el sistema operativo muestra el payload de FCM.
  static Future<void> showRemote({
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    if (kIsWeb) return;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      payload: encodeNotificationPayload(data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _updatesChannelId,
          'Actualizaciones de reportes',
          channelDescription: 'Avisos sobre el estado de tus reportes',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
          ),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
