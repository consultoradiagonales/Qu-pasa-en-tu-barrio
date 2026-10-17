import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  LocalNotificationService._();

  static const _morningId = 1001;
  static const _eveningId = 1002;
  static const _previewId = 1003;
  static const _scheduleReminderPreview =
      bool.fromEnvironment('SCHEDULE_REMINDER_PREVIEW');
  static const _reminderBody =
      '\u2728 Vivir mejor depende de vos.\n\u{1F4E2} Report\u00E1 y ayud\u00E1 a transformar tu ciudad.';
  static const _channelId = 'condi_daily_reminders';
  static const _updatesChannelId = 'condi_report_updates';
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) return;
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
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
    // El permiso de notificaciones NO se pide acá. Pedirlo al abrir la app,
    // antes de mostrar nada, es el momento en que más se rechaza. Se pide en
    // contexto, apenas la persona inicia sesión (_registerPushForUser en
    // main.dart). Los recordatorios quedan programados igual y empiezan a
    // verse cuando el permiso se concede.
    await _plugin.cancel(id: _morningId);
    await _plugin.cancel(id: _eveningId);
    await _plugin.cancel(id: _previewId);
    await _schedule(_morningId, 10);
    await _schedule(_eveningId, 18);
    if (_scheduleReminderPreview) {
      await _schedulePreviewForTomorrow();
    }
  }

  static tz.TZDateTime _nextAt(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  static Future<void> _schedule(int id, int hour) async {
    await _plugin.zonedSchedule(
      id: id,
      title: 'ConDi',
      body: _reminderBody,
      scheduledDate: _nextAt(hour),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Recordatorios de ConDi',
          channelDescription: 'Recordatorios diarios para reportar mejoras',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> _schedulePreviewForTomorrow() async {
    final now = tz.TZDateTime.now(tz.local);
    final tomorrow = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      20,
      15,
    );
    await _plugin.zonedSchedule(
      id: _previewId,
      title: 'ConDi',
      body: _reminderBody,
      scheduledDate: tomorrow,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Recordatorios de ConDi',
          channelDescription: 'Recordatorios diarios para reportar mejoras',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Muestra un aviso que llegó por FCM cuando la aplicación está abierta.
  /// En segundo plano el sistema operativo muestra el payload de FCM.
  static Future<void> showRemote({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _updatesChannelId,
          'Actualizaciones de reportes',
          channelDescription: 'Avisos sobre el estado de tus reportes',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
