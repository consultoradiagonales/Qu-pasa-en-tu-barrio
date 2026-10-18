import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Widget _host(bool isAdmin, {_FakeReach? reach}) => ProviderScope(
      overrides: [
        pushReachRepositoryProvider.overrideWithValue(reach ??
            _FakeReach((_) async => const PushReach(total: 3, withPush: 1))),
        reachMunicipalityIdProvider.overrideWithValue('muni-1'),
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
}
