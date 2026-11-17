import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/models/notification_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/notifications_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/notifications/screens/notifications_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Repositorio en memoria: markRead persiste en el store y el stream re-emite.
class _MemoryRepo implements NotificationsRepository {
  _MemoryRepo(List<NotificationModel> recent, {this.remote = const {}})
      : store = {for (final n in recent) n.id: n};
  final Map<String, NotificationModel> store;
  final Map<String, NotificationModel> remote;
  final marked = <String>[];
  Object? lookupError;
  Object? markError;
  final _ctrl = StreamController<List<NotificationModel>>.broadcast();

  List<NotificationModel> get _list => store.values.toList();

  @override
  Stream<List<NotificationModel>> watchNotifications(String userId) async* {
    yield _list;
    yield* _ctrl.stream;
  }

  @override
  Future<NotificationModel?> getOwnedNotification(
      String userId, String notificationId) async {
    if (lookupError != null) throw lookupError!;
    return store[notificationId] ?? remote[notificationId];
  }

  @override
  Future<void> markRead(String userId, String notifId) async {
    marked.add(notifId);
    if (markError != null) throw markError!;
    final n = store[notifId];
    if (n != null) {
      store[notifId] = n.copyWith(read: true);
      _ctrl.add(_list);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationModel _n(String id, NotificationType type,
        {bool read = false, DateTime? at}) =>
    NotificationModel(
      id: id,
      userId: 'u1',
      type: type,
      reportId: '',
      title: 'Titulo $id',
      body: 'Cuerpo $id',
      read: read,
      createdAt: at ?? DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, _MemoryRepo repo,
    {String? open}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
      notificationsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: NotificationsScreen(openNotificationId: open)),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

List<NotificationModel> _recent50() => [
      for (var i = 0; i < 50; i++)
        _n('recent_$i', NotificationType.municipalityMessage,
            read: true, at: DateTime(2026, 11, 1).add(Duration(minutes: i))),
    ];

void main() {
  testWidgets(
      'alerta meteorológica fuera de las 50 recientes abre su detalle y se marca leída',
      (tester) async {
    final repo = _MemoryRepo(_recent50(), remote: {
      'old_weather': _n('old_weather', NotificationType.weatherAlert,
          at: DateTime(2025, 1, 1)),
    });
    await _pump(tester, repo, open: 'old_weather');
    expect(find.byKey(const Key('notification-message-full')), findsOneWidget);
    expect(find.text('Cuerpo old_weather'), findsOneWidget);
    expect(repo.marked, ['old_weather']);
  });

  testWidgets(
      'mensaje municipal fuera de las 50 recientes también abre por enlace profundo',
      (tester) async {
    final repo = _MemoryRepo(_recent50(), remote: {
      'old_msg': _n('old_msg', NotificationType.municipalityMessage,
          at: DateTime(2025, 1, 1)),
    });
    await _pump(tester, repo, open: 'old_msg');
    expect(find.byKey(const Key('notification-message-full')), findsOneWidget,
        reason: 'el deep link a un mensaje no meteorológico cae en la lista');
    expect(repo.marked, ['old_msg']);
  });

  testWidgets('alerta ya leída abre el detalle sin volver a marcar',
      (tester) async {
    final repo = _MemoryRepo(const [], remote: {
      'w_read': _n('w_read', NotificationType.weatherAlert, read: true),
    });
    await _pump(tester, repo, open: 'w_read');
    expect(find.byKey(const Key('notification-message-full')), findsOneWidget);
    expect(repo.marked, isEmpty);
  });

  testWidgets('si marcar leída falla, el detalle sigue visible',
      (tester) async {
    final repo = _MemoryRepo(const [],
        remote: {'w1': _n('w1', NotificationType.weatherAlert)})
      ..markError = StateError('offline');
    await _pump(tester, repo, open: 'w1');
    expect(find.byKey(const Key('notification-message-full')), findsOneWidget);
    expect(repo.marked, ['w1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('id inexistente cae a la lista',
      (tester) async {
    final repo = _MemoryRepo([_n('m1', NotificationType.municipalityMessage)]);
    await _pump(tester, repo, open: 'missing');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Titulo m1'), findsOneWidget);
  });

  testWidgets('lookup con permission-denied cae a la lista', (tester) async {
    final denied = _MemoryRepo([_n('m2', NotificationType.municipalityMessage)])
      ..lookupError =
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await _pump(tester, denied, open: 'w_denied');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Titulo m2'), findsOneWidget);
  });

  testWidgets('la lectura persiste: al volver la alerta ya no está en negrita',
      (tester) async {
    final repo = _MemoryRepo([_n('w', NotificationType.weatherAlert)]);
    await _pump(tester, repo);
    Text title() => tester.widget<Text>(find.text('Titulo w'));
    expect(title().style?.fontWeight, FontWeight.bold);

    await tester.tap(find.text('Titulo w'));
    await tester.pumpAndSettle();
    expect(find.text('Alerta meteorológica'), findsOneWidget);
    expect(find.byKey(const Key('notification-message-full')), findsOneWidget);
    expect(repo.store['w']!.read, isTrue);

    Navigator.of(tester.element(
            find.byKey(const Key('notification-message-full'))))
        .pop();
    await tester.pumpAndSettle();
    expect(title().style?.fontWeight, FontWeight.normal);

    await tester.tap(find.text('Titulo w'));
    await tester.pumpAndSettle();
    expect(repo.marked, ['w'], reason: 'no debe volver a marcar una leída');
  });
}
