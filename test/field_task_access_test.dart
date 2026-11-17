import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/core/router/navigation_policy.dart';
import 'package:que_pasa_en_tu_barrio/data/models/report_model.dart';
import 'package:que_pasa_en_tu_barrio/data/models/user_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/reports_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/user_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/field/screens/field_home_screen.dart';
import 'package:que_pasa_en_tu_barrio/features/field/screens/work_in_progress_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'field-user';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _workerProfile() => UserModel(
      uid: 'field-user',
      displayName: 'Operario',
      realName: '',
      email: '',
      role: UserRole.fieldWorker,
      teamId: 'team-a',
      municipalityId: 'georef_060707',
      createdAt: DateTime(2026, 1, 1),
    );

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository(this.load);

  final Future<ReportModel?> Function(String) load;

  @override
  Future<ReportModel?> getReport(String id) => load(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('el regreso tras auth conserva sólo rutas válidas de tarea', () {
    expect(signedInDestination('/field/task/report_123'),
        '/field/task/report_123');
    expect(signedInDestination('/field/task/report_123/work'),
        '/field/task/report_123/work');
    expect(
        signedInDestination('/field/task/../../admin'), citizenStartLocation);
    expect(signedInDestination('/field/task/report_123?next=/admin'),
        citizenStartLocation);
    expect(
        canOpenOperations('/field/task/report_123', 'citizen', enabled: true),
        isFalse);
  });

  test('el regreso tras auth conserva sólo IDs seguros de alertas', () {
    expect(signedInDestination('/notifications?open=weather_alert_123'),
        '/notifications?open=weather_alert_123');
    expect(signedInDestination('/notifications?open=../../admin'),
        citizenStartLocation);
    expect(signedInDestination('/notifications?open=ok&next=/admin'),
        citizenStartLocation);
    expect(signedInDestination('/notifications?open='), citizenStartLocation);
  });

  test('la consulta municipal contempla el alias GeoRef sin cruzar ámbitos',
      () {
    expect(fieldMunicipalityAliases('060707'), ['060707', 'georef_060707']);
    expect(
        fieldMunicipalityAliases('georef_060707'), ['060707', 'georef_060707']);
    expect(fieldMunicipalityAliases(''), isEmpty);
  });

  testWidgets('el perfil estable muestra las tareas del equipo',
      (tester) async {
    final profileUpdates = StreamController<UserModel?>();
    addTearDown(profileUpdates.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('field-user')
            .overrideWith((_) => profileUpdates.stream),
        teamReportsProvider((teamId: 'team-a', municipalityId: 'georef_060707'))
            .overrideWith((_) => Stream.value(<ReportModel>[])),
      ],
      child: const MaterialApp(home: FieldHomeScreen()),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sin equipo asignado.'), findsNothing);

    profileUpdates.add(_workerProfile());
    await tester.pumpAndSettle();

    expect(find.text('Sin equipo asignado.'), findsNothing);
    expect(find.text('Sin tareas asignadas.'), findsOneWidget);
  });

  testWidgets('un error de perfil ofrece reintentar', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('field-user')
            .overrideWith((_) => Stream.error(Exception('network'))),
      ],
      child: const MaterialApp(home: FieldHomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sin equipo asignado.'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('trabajo en curso espera la lectura antes de habilitar acciones',
      (tester) async {
    final pending = Completer<ReportModel?>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportsRepositoryProvider
            .overrideWith((_) => _FakeReportsRepository((_) => pending.future)),
      ],
      child: const MaterialApp(
        home: WorkInProgressScreen(reportId: 'report_123'),
      ),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Trabajo terminado'), findsNothing);

    pending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Reporte no encontrado.'), findsOneWidget);
    expect(find.text('Trabajo terminado'), findsNothing);
  });

  testWidgets('trabajo en curso muestra el error y permite reintentar',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportsRepositoryProvider.overrideWith((_) => _FakeReportsRepository(
            (_) async => throw StateError('fallo de lectura'))),
      ],
      child: const MaterialApp(
        home: WorkInProgressScreen(reportId: 'report_123'),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('fallo de lectura'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Trabajo terminado'), findsNothing);
  });
}
