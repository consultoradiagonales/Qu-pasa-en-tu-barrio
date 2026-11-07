import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/models/notification_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/notifications_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/notifications/screens/notifications_screen.dart';
import 'package:que_pasa_en_tu_barrio/features/notifications/screens/notification_message_detail_screen.dart';

class _FakeDoc implements DocumentSnapshot {
  _FakeDoc(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Object? data() => _data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo implements NotificationsRepository {
  final List<String> marked = [];
  final List<String> deleted = [];
  @override
  Future<void> markRead(String userId, String notifId) async =>
      marked.add(notifId);
  @override
  Future<void> deleteNotification(String userId, String notifId) async =>
      deleted.add(notifId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationModel _n(String id, NotificationType type,
        {String reportId = '', bool read = false, String? actionUrl}) =>
    NotificationModel(
      id: id,
      userId: 'u1',
      type: type,
      reportId: reportId,
      title: 'Titulo $id',
      body: 'Cuerpo $id',
      actionUrl: actionUrl,
      read: read,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('NotificationModel', () {
    test('parsea weather_alert y municipality_message sin reportId', () {
      final w = NotificationModel.fromFirestore(_FakeDoc('a', {
        'userId': 'u1',
        'type': 'weather_alert',
        'title': 'Tormenta',
        'body': 'Alerta naranja',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      }));
      expect(w.type, NotificationType.weatherAlert);
      expect(w.reportId, '');
      expect(w.hasReport, isFalse);
      expect(w.title, 'Tormenta');

      final m = NotificationModel.fromFirestore(_FakeDoc('b', {
        'userId': 'u1',
        'type': 'municipality_message',
        'reportId': null,
        'title': 'Aviso',
        'body': 'Corte de agua',
        'imageUrl': 'https://x/y.png',
      }));
      expect(m.type, NotificationType.municipalityMessage);
      expect(m.hasReport, isFalse);
      expect(m.imageUrl, 'https://x/y.png');
    });

    test('preserva el cuerpo completo y los datos de conversacion', () {
      final longBody =
          List.filled(40, 'Mensaje largo para la conversacion.').join(' ');
      final notification =
          NotificationModel.fromFirestore(_FakeDoc('thread-1', {
        'userId': 'u1',
        'type': 'municipality_message',
        'reportId': '',
        'title': 'Actualizacion',
        'body': longBody,
        'actionUrl':
            'https://play.google.com/apps/internaltest/4701647237677047143',
        'threadId': 'city-la-plata',
        'parentNotificationId': 'thread-0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      }));

      expect(notification.body, longBody);
      expect(notification.actionUrl,
          'https://play.google.com/apps/internaltest/4701647237677047143');
      expect(notification.threadId, 'city-la-plata');
      expect(notification.parentNotificationId, 'thread-0');
      expect(notification.conversationId, 'city-la-plata');
      expect(notification.toFirestore()['body'], longBody);
      expect(notification.toFirestore()['actionUrl'], notification.actionUrl);
    });

    test('preserva ciudad y zonas afectadas de una alerta', () {
      final notification =
          NotificationModel.fromFirestore(_FakeDoc('weather-1', {
        'userId': 'u1',
        'type': 'weather_alert',
        'title': 'Tormentas',
        'body': 'Detalle completo',
        'municipalityName': 'Saladillo',
        'province': 'Buenos Aires',
        'affectedZones': ['Saladillo', 'Roque Pérez'],
        'affectedArea': 'Saladillo, Roque Pérez y alrededores',
      }));

      expect(notification.municipalityName, 'Saladillo');
      expect(notification.province, 'Buenos Aires');
      expect(notification.affectedZones, ['Saladillo', 'Roque Pérez']);
      expect(notification.affectedArea, contains('Roque Pérez'));
    });
    test('value/fromString son simétricos', () {
      for (final t in NotificationType.values) {
        expect(NotificationType.fromString(t.value), t);
      }
    });

    test('un aviso con reporte tiene hasReport', () {
      expect(_n('c', NotificationType.reportResolved, reportId: 'r1').hasReport,
          isTrue);
    });
  });

  group('NotificationsScreen', () {
    Future<_FakeRepo> pump(
      WidgetTester tester, {
      List<NotificationModel>? notifications,
      Future<bool> Function(Uri uri)? actionLauncher,
    }) async {
      final repo = _FakeRepo();
      final items = notifications ??
          [
            _n('w', NotificationType.weatherAlert),
            _n('m', NotificationType.municipalityMessage),
            _n('r', NotificationType.reportResolved,
                reportId: 'r1', read: true),
          ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
          notificationsRepositoryProvider.overrideWithValue(repo),
          notificationsProvider('u1').overrideWith((_) => Stream.value(items)),
        ],
        child: MaterialApp(
          home: actionLauncher == null
              ? const NotificationsScreen()
              : NotificationsScreen(actionLauncher: actionLauncher),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return repo;
    }

    testWidgets('muestra avisos sin reportId con íconos de nube y megáfono',
        (tester) async {
      await pump(tester);
      expect(find.text('Titulo w'), findsOneWidget);
      expect(find.text('Cuerpo m'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar un aviso abre el mensaje completo y lo marca leído',
        (tester) async {
      final repo = await pump(tester);
      await tester.tap(find.text('Titulo w'));
      await tester.pumpAndSettle();
      expect(repo.marked, ['w']);
      expect(find.text('Alerta meteorológica'), findsOneWidget);
      expect(
          find.byKey(const Key('notification-message-full')), findsOneWidget);
      expect(find.text('Cuerpo w'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deslizar una alerta muestra la papelera y la elimina',
        (tester) async {
      final repo = await pump(tester);
      await tester.drag(find.text('Titulo w'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['w']);
      expect(find.text('Alerta eliminada.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar una actualización abre Google Play directamente',
        (tester) async {
      const url =
          'https://play.google.com/apps/internaltest/4701647237677047143';
      Uri? opened;
      final repo = await pump(
        tester,
        notifications: [
          _n('update', NotificationType.municipalityMessage, actionUrl: url),
        ],
        actionLauncher: (uri) async {
          opened = uri;
          return true;
        },
      );

      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      await tester.tap(find.text('Titulo update'));
      await tester.pumpAndSettle();

      expect(opened, Uri.parse(url));
      expect(repo.marked, ['update']);
      expect(find.byKey(const Key('notification-message-full')), findsNothing);
    });

    testWidgets('si Google Play no abre conserva el detalle como respaldo',
        (tester) async {
      const url =
          'https://play.google.com/apps/internaltest/4701647237677047143';
      await pump(
        tester,
        notifications: [
          _n('update', NotificationType.municipalityMessage, actionUrl: url),
        ],
        actionLauncher: (_) async => false,
      );

      await tester.tap(find.text('Titulo update'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notification-message-full')),
        findsOneWidget,
      );
      expect(find.text('Actualizar ConDi'), findsOneWidget);
    });

    test('solo expone enlaces HTTPS de destinos confiables', () {
      final links = safeNotificationLinks(
        'Ok https://consultoradiagonales.com.ar/ayuda '
        'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi '
        'https://sitio-no-confiable.example/a http://inseguro.example',
      );
      expect(links.map((link) => link.host), [
        'consultoradiagonales.com.ar',
        'play.google.com',
      ]);
    });

    testWidgets('el detalle muestra la acción oficial de actualización',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: NotificationMessageDetailScreen(
          notification: _n(
            'update',
            NotificationType.municipalityMessage,
            actionUrl:
                'https://play.google.com/apps/internaltest/4701647237677047143',
          ),
          forFieldWorker: false,
        ),
      ));
      expect(find.text('Actualizar ConDi'), findsOneWidget);
      expect(
        find.byKey(const Key('notification-link-play.google.com')),
        findsOneWidget,
      );
    });
  });
}
