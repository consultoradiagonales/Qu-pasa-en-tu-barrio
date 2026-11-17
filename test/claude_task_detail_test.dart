import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:que_pasa_en_tu_barrio/data/models/report_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/reports_repository.dart';
import 'package:que_pasa_en_tu_barrio/features/field/screens/task_detail_screen.dart';

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository(this.load);
  final Future<ReportModel?> Function(String id, int call) load;
  int calls = 0;

  @override
  Future<ReportModel?> getReport(String id) => load(id, ++calls);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReportModel _report(String id) => ReportModel(
      id: id,
      userId: 'citizen-1',
      municipalityId: 'georef_060707',
      title: 'Bache en calle 1',
      description: 'Pozo grande frente a la escuela',
      category: ReportCategory.infrastructure,
      location: const ReportLocation(
        lat: -35.6,
        lng: -59.7,
        geohash: '69y7',
        address: 'Calle 1 y 2',
        isManualAddress: true,
      ),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<_FakeReportsRepository> _pump(
  WidgetTester tester,
  Future<ReportModel?> Function(String id, int call) load, {
  String initial = '/field/task/r1',
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  final repo = _FakeReportsRepository(load);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/field',
        builder: (context, _) => Scaffold(
          body: Column(children: [
            const Text('FIELD HOME'),
            TextButton(
              onPressed: () => context.push('/field/task/r1'),
              child: const Text('abrir tarea'),
            ),
          ]),
        ),
      ),
      GoRoute(
        path: '/field/task/:id',
        builder: (_, state) =>
            TaskDetailScreen(reportId: state.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [reportsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  return repo;
}

void main() {
  testWidgets('la carga resuelve y muestra la tarea', (tester) async {
    final pending = Completer<ReportModel?>();
    await _pump(tester, (_, __) => pending.future);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(_report('r1'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bache en calle 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout muestra error y Reintentar; reintentar recupera',
      (tester) async {
    final never = Completer<ReportModel?>();
    final repo = await _pump(
        tester, (id, call) => call == 1 ? never.future : Future.value(_report(id)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.text('Bache en calle 1'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('reporte inexistente no deja spinner infinito', (tester) async {
    await _pump(tester, (_, __) async => null);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Reporte no encontrado.'), findsOneWidget);
    expect(find.byKey(const Key('field-task-back')), findsOneWidget);
  });

  testWidgets('permission-denied muestra mensaje y Reintentar sin spinner',
      (tester) async {
    await _pump(
        tester,
        (_, __) async => throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No tenés permiso'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('deep link: la flecha vuelve a /field', (tester) async {
    await _pump(tester, (id, _) async => _report(id));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('field-task-back')));
    await tester.pumpAndSettle();
    expect(find.text('FIELD HOME'), findsOneWidget);
  });

  testWidgets('deep link: back de Android vuelve a /field', (tester) async {
    await _pump(tester, (id, _) async => _report(id));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('FIELD HOME'), findsOneWidget);
    expect(find.text('Detalle de tarea'), findsNothing);
  });

  testWidgets('desde la lista: flecha y back de Android hacen pop',
      (tester) async {
    await _pump(tester, (id, _) async => _report(id), initial: '/field');
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir tarea'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de tarea'), findsOneWidget);
    await tester.tap(find.byKey(const Key('field-task-back')));
    await tester.pumpAndSettle();
    expect(find.text('FIELD HOME'), findsOneWidget);

    await tester.tap(find.text('abrir tarea'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('FIELD HOME'), findsOneWidget);
    expect(find.text('Detalle de tarea'), findsNothing);
  });
}
