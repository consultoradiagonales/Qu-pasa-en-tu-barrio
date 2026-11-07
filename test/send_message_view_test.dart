import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/admin_messages_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/push_reach_repository.dart';
import 'package:que_pasa_en_tu_barrio/features/admin/widgets/send_message_view.dart';

class _FakeReach implements PushReachRepository {
  _FakeReach(this.result);
  final Future<PushReach> Function(String? municipalityId) result;
  final calls = <String?>[];

  @override
  Future<PushReach> reach({String? municipalityId}) {
    calls.add(municipalityId);
    return result(municipalityId);
  }
}

class _FakeMessages implements AdminMessagesRepository {
  final requests = <({
    String title,
    String body,
    String municipalityId,
    MessageAudience audience
  })>[];

  @override
  Future<MessageDispatchResult> send({
    required String title,
    required String body,
    required String senderMunicipalityId,
    required MessageAudience audience,
  }) async {
    requests.add((
      title: title,
      body: body,
      municipalityId: senderMunicipalityId,
      audience: audience,
    ));
    return const MessageDispatchResult(total: 2, pushed: 1, inApp: 1);
  }
}

Widget _host(bool isAdmin, {_FakeReach? reach, _FakeMessages? messages}) =>
    ProviderScope(
      overrides: [
        pushReachRepositoryProvider.overrideWithValue(reach ??
            _FakeReach((_) async => const PushReach(total: 3, withPush: 1))),
        reachMunicipalityIdProvider.overrideWithValue('muni-1'),
        adminMessagesRepositoryProvider
            .overrideWithValue(messages ?? _FakeMessages()),
      ],
      child: MaterialApp(
        home: Scaffold(body: SendMessageView(isAdmin: isAdmin)),
      ),
    );

void main() {
  testWidgets('el botón se habilita solo con título y mensaje', (tester) async {
    await tester.pumpWidget(_host(false));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byKey(const Key('message-send')));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('message-title')), 'Corte');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('message-body')), 'Sin agua en el centro');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets(
      'el compositor admite los limites del backend y un cuerpo extenso',
      (tester) async {
    await tester.pumpWidget(_host(true));

    final title =
        tester.widget<TextField>(find.byKey(const Key('message-title')));
    final body =
        tester.widget<TextField>(find.byKey(const Key('message-body')));

    expect(title.maxLength, 120);
    expect(body.maxLength, 4000);
    expect(body.minLines, 6);
    expect(body.maxLines, 12);
    expect(body.keyboardType, TextInputType.multiline);
    expect(find.text('0/120'), findsOneWidget);
    expect(find.text('0/4000'), findsOneWidget);
  });
  testWidgets('un coordinador no ve "Todos los usuarios"', (tester) async {
    await tester.pumpWidget(_host(false));
    await tester.tap(find.byKey(const Key('message-audience')));
    await tester.pumpAndSettle();
    expect(find.text('Todos los usuarios de la app'), findsNothing);
    expect(find.text('Vecinos de mi municipio'), findsWidgets);
  });

  testWidgets('el administrador sí ve "Todos los usuarios"', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.tap(find.byKey(const Key('message-audience')));
    await tester.pumpAndSettle();
    expect(find.text('Todos los usuarios de la app'), findsWidgets);
  });

  testWidgets('muestra el alcance cuando hay usuarios con push',
      (tester) async {
    final fake =
        _FakeReach((_) async => const PushReach(total: 10, withPush: 4));
    await tester.pumpWidget(_host(false, reach: fake));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('10 usuarios en total, 4 con notificaciones '
            'activas en el celular, 6 solo recibirán el aviso dentro de la '
            'app'),
        findsOneWidget);
    expect(find.byKey(const Key('message-reach-warning')), findsNothing);
    expect(fake.calls, ['muni-1']);
  });

  testWidgets('con push en cero avisa que nadie puede recibirlo',
      (tester) async {
    final fake =
        _FakeReach((_) async => const PushReach(total: 5, withPush: 0));
    await tester.pumpWidget(_host(true, reach: fake));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-reach-warning')), findsOneWidget);
    expect(find.textContaining('última versión'), findsOneWidget);
    expect(find.textContaining('aceptar el permiso'), findsOneWidget);

    // El administrador cambia a "todos": consulta sin municipio.
    await tester.tap(find.byKey(const Key('message-audience')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos los usuarios de la app').last);
    await tester.pumpAndSettle();
    expect(fake.calls, ['muni-1', null]);
  });

  testWidgets('si el conteo falla, la vista sigue usable', (tester) async {
    final fake = _FakeReach((_) async => throw Exception('permission-denied'));
    await tester.pumpWidget(_host(false, reach: fake));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-reach-error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message-title')), 'Corte');
    await tester.enterText(
        find.byKey(const Key('message-body')), 'Sin agua en el centro');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('message-send')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'entrega el mensaje por push y bandeja según el resultado del servidor',
      (tester) async {
    final messages = _FakeMessages();
    await tester.pumpWidget(_host(false, messages: messages));
    await tester.enterText(
        find.byKey(const Key('message-title')), 'Corte de agua');
    await tester.enterText(find.byKey(const Key('message-body')),
        'El servicio vuelve a las 18 horas.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar').last);
    await tester.pumpAndSettle();

    expect(messages.requests, hasLength(1));
    expect(messages.requests.single.title, 'Corte de agua');
    expect(messages.requests.single.municipalityId, 'muni-1');
    expect(messages.requests.single.audience, MessageAudience.municipality);
    expect(find.textContaining('Notificación enviada a 1 persona'),
        findsOneWidget);
    expect(find.textContaining('1 la verá al abrir ConDi'), findsOneWidget);
  });
}
