import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/models/notification_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/notifications_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/notifications/screens/notifications_screen.dart';

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
  @override
  Future<void> markRead(String userId, String notifId) async =>
      marked.add(notifId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationModel _n(String id, NotificationType type,
        {String reportId = '', bool read = false}) =>
    NotificationModel(
      id: id,
      userId: 'u1',
      type: type,
      reportId: reportId,
      title: 'Titulo $id',
      body: 'Cuerpo $id',
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
    Future<_FakeRepo> pump(WidgetTester tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
          notificationsRepositoryProvider.overrideWithValue(repo),
          notificationsProvider('u1').overrideWith((_) => Stream.value([
                _n('w', NotificationType.weatherAlert),
                _n('m', NotificationType.municipalityMessage),
                _n('r', NotificationType.reportResolved,
                    reportId: 'r1', read: true),
              ])),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
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

    testWidgets('tocar un aviso sin reportId solo lo marca leído',
        (tester) async {
      final repo = await pump(tester);
      await tester.tap(find.text('Titulo w'));
      await tester.pump();
      await tester.pump();
      expect(repo.marked, ['w']);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
