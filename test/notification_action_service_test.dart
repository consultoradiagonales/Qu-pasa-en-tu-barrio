import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/core/services/local_notification_service.dart';
import 'package:que_pasa_en_tu_barrio/core/services/notification_action_service.dart';

void main() {
  group('notification action', () {
    test('acepta únicamente las URLs oficiales de actualización', () {
      expect(
        trustedNotificationActionUri({'actionUrl': androidPlayStoreUrl}),
        Uri.parse(androidPlayStoreUrl),
      );
      expect(
        trustedNotificationActionUri({'actionUrl': androidInternalTestUrl}),
        Uri.parse(androidInternalTestUrl),
      );
      expect(
        trustedNotificationActionUri({
          'actionUrl': 'https://apps.apple.com/ar/app/condi/id123456789',
        }),
        Uri.parse('https://apps.apple.com/ar/app/condi/id123456789'),
      );
      for (final unsafe in [
        'http://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi',
        'https://play.google.com.evil.example/store/apps/details?id=ar.com.consultoradiagonales.condi',
        'https://play.google.com/store/apps/details?id=otra.app',
        'texto',
      ]) {
        expect(
          trustedNotificationActionUri({'actionUrl': unsafe}),
          isNull,
        );
      }
    });

    test('abre la acción recibida al tocar el push desde background', () async {
      Uri? opened;
      final result = await openNotificationAction(
        {'actionUrl': androidInternalTestUrl},
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      );
      expect(result, isTrue);
      expect(opened, Uri.parse(androidInternalTestUrl));
    });

    test('un push anterior recupera actionUrl mediante notificationId',
        () async {
      String? lookedUp;
      Uri? opened;
      final result = await openNotificationAction(
        {'notificationId': 'custom_update_alerts_20261030_01_u1'},
        lookupById: (id) async {
          lookedUp = id;
          return {'actionUrl': androidInternalTestUrl};
        },
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      );
      expect(result, isTrue);
      expect(lookedUp, 'custom_update_alerts_20261030_01_u1');
      expect(opened, Uri.parse(androidInternalTestUrl));
    });

    test('no consulta ni abre ids o destinos inválidos', () async {
      var lookups = 0;
      var launches = 0;
      final result = await openNotificationAction(
        {'notificationId': '../otro', 'actionUrl': 'https://evil.example'},
        lookupById: (_) async {
          lookups++;
          return {'actionUrl': androidPlayStoreUrl};
        },
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      expect(result, isFalse);
      expect(lookups, 0);
      expect(launches, 0);
    });
  });

  test('el payload local conserva la acción y tolera datos corruptos', () {
    final encoded = encodeNotificationPayload({
      'type': 'municipality_message',
      'notificationId': 'n1',
      'actionUrl': androidInternalTestUrl,
      'ignored': const ['no'],
    });
    expect(decodeNotificationPayload(encoded), {
      'type': 'municipality_message',
      'notificationId': 'n1',
      'actionUrl': androidInternalTestUrl,
    });
    expect(decodeNotificationPayload('{malformed'), isEmpty);
    expect(decodeNotificationPayload(null), isEmpty);
  });
}
