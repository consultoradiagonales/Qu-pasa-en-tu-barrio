import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:que_pasa_en_tu_barrio/data/models/user_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/reports_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/georef_service.dart';
import 'package:que_pasa_en_tu_barrio/features/report/report_flow.dart';
import 'package:que_pasa_en_tu_barrio/features/report/report_insight.dart';
import 'package:que_pasa_en_tu_barrio/features/report/screens/new_report_screen.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=';

class _GeoRef extends GeoRefService {
  @override
  Future<({double lat, double lng, double zoom})?> municipalityCenter(
          String id) async =>
      (lat: -34.92145, lng: -57.95453, zoom: 13.0);
  @override
  Future<GeoRefPlace?> municipalityAt(double lat, double lng) async => null;
}

class _Storage extends ReportDraftStorage {
  _Storage(this.events);
  final List<String> events;
  ReportDraft? value;
  @override
  Future<ReportDraft?> read() async => value;
  @override
  Future<void> write(ReportDraft? draft) async {
    if (draft == null) events.add('clear');
    value = draft;
  }
}

class _Capture extends ReportCaptureService {
  @override
  Future<Uint8List> readPhoto(String path) async => base64Decode(_png);
  @override
  Future<XFile?> recoverPhoto() async => null;
  @override
  Future<XFile?> camera() async =>
      XFile.fromData(base64Decode(_png), path: '/test/photo.png');
  @override
  Future<LatLng> gps() async => const LatLng(-34.92145, -57.95453);
}

class _Submit extends ReportSubmitService {
  _Submit(super.ref);
  final failures = <Object>[];
  final ids = <String>[];
  @override
  bool get signedIn => true;
  @override
  Future<String> submit(ReportDraft draft) async {
    ids.add(draft.id);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return draft.id;
  }
}

class _Reports implements ReportsRepository {
  _Reports(this.events);
  final List<String> events;
  final updates = <(String, Map<String, dynamic>)>[];
  Completer<void>? gate;
  Object? failOnce;
  @override
  Future<void> updateReport(String id, Map<String, dynamic> fields) async {
    events.add('hide');
    updates.add((id, fields));
    if (gate != null) await gate!.future;
    if (failOnce case final e?) {
      failOnce = null;
      throw e;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _profile = UserModel(
  uid: 'citizen-home',
  displayName: 'Vecino',
  realName: 'Vecino de prueba',
  email: 'vecino@example.test',
  role: UserRole.citizen,
  municipalityId: 'georef_06441',
  municipalityName: 'La Plata',
  provinceId: '06',
  province: 'Buenos Aires',
  createdAt: DateTime(2026, 1, 1),
);

Future<_Submit> _mount(
    WidgetTester tester, _Storage storage, _Reports reports) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  late _Submit submit;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reportInsightProvider.overrideWith((ref, id) => Stream.value(null)),
      reportCaptureProvider.overrideWithValue(_Capture()),
      reportDraftStorageProvider.overrideWithValue(storage),
      reportSubmitProvider.overrideWith((ref) => submit = _Submit(ref)),
      reportProfileProvider.overrideWithValue(AsyncData(_profile)),
      reportGeoRefProvider.overrideWithValue(_GeoRef()),
      reportsRepositoryProvider.overrideWithValue(reports),
    ],
    child: const MaterialApp(home: NewReportScreen(showMap: false)),
  ));
  await tester.pumpAndSettle();
  ProviderScope.containerOf(tester.element(find.byType(NewReportScreen)))
      .read(reportSubmitProvider);
  return submit;
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lleva el flujo hasta "foto pendiente" (alta recibida, foto falló).
Future<void> _toPending(WidgetTester tester, _Submit submit) async {
  await _tap(tester, find.text('Usar mi ubicación'));
  await _tap(tester, find.text('Usar esta ubicación'));
  await _tap(tester, find.byKey(const Key('photo-evidence-confirmed')));
  final dropdown = find.byKey(const Key('report-category'));
  await _tap(tester, dropdown);
  await tester.tap(find.text('Bache').last);
  await tester.pumpAndSettle();
  submit.failures
      .add(ReportSubmissionException('Foto pendiente.', photoPending: true));
  await _tap(tester, find.text('Enviar reporte'));
  expect(find.text('Reintentar foto'), findsOneWidget);
}

Future<void> _discard(WidgetTester tester, {String button = 'Descartar'}) async {
  await tester.tap(find.byKey(const Key('discard-report-draft')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(button));
}

void main() {
  testWidgets('descarte fallido conserva foto, datos del borrador y botón de reintento',
      (tester) async {
    final events = <String>[];
    final storage = _Storage(events);
    final reports = _Reports(events);
    final submit = await _mount(tester, storage, reports);
    await _toPending(tester, submit);
    final before = storage.value!;

    reports.failOnce = StateError('Sin conexión');
    await _discard(tester);
    await tester.pumpAndSettle();

    final after = storage.value!;
    expect(after.id, before.id);
    expect(after.photoPath, before.photoPath);
    expect(after.presetId, 'pothole');
    expect(after.locationConfirmed, isTrue);
    expect(after.photoConfirmed, isTrue);
    expect(events.contains('clear'), isFalse);
    expect(find.byType(Image), findsWidgets, reason: 'la vista previa sigue');
    expect(find.text('Reintentar foto'), findsOneWidget);
    expect(find.textContaining('Conservamos el borrador'), findsOneWidget);
  });

  testWidgets('descarte exitoso oculta el reporte ANTES de borrar el borrador',
      (tester) async {
    final events = <String>[];
    final storage = _Storage(events);
    final reports = _Reports(events);
    final submit = await _mount(tester, storage, reports);
    await _toPending(tester, submit);
    final id = storage.value!.id;

    reports.gate = Completer<void>();
    await _discard(tester);
    await tester.pump();
    await tester.pump();
    // Mientras el ocultamiento está en vuelo, el borrador sigue intacto.
    expect(events, ['hide']);
    expect(storage.value?.id, id);
    final discardBtn = tester
        .widget<IconButton>(find.byKey(const Key('discard-report-draft')));
    expect(discardBtn.onPressed, isNull, reason: 'evita doble descarte');

    reports.gate!.complete();
    await tester.pumpAndSettle();
    expect(events, ['hide', 'clear']);
    expect(reports.updates.single.$1, id);
    expect(reports.updates.single.$2, {'hidden': true});
    expect(storage.value, isNull);
    expect(find.text('Reintentar foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Conservar" no oculta ni borra nada', (tester) async {
    final events = <String>[];
    final storage = _Storage(events);
    final reports = _Reports(events);
    final submit = await _mount(tester, storage, reports);
    await _toPending(tester, submit);
    await _discard(tester, button: 'Conservar');
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    expect(storage.value, isNotNull);
    expect(find.text('Reintentar foto'), findsOneWidget);
  });

  testWidgets('reintento de foto reutiliza el mismo id y si vuelve a fallar sigue pendiente',
      (tester) async {
    final events = <String>[];
    final storage = _Storage(events);
    final reports = _Reports(events);
    final submit = await _mount(tester, storage, reports);
    await _toPending(tester, submit);
    final id = storage.value!.id;

    submit.failures
        .add(ReportSubmissionException('Otra vez.', photoPending: true));
    await _tap(tester, find.text('Reintentar foto'));
    expect(find.text('Reintentar foto'), findsOneWidget);
    expect(storage.value?.id, id);

    await _tap(tester, find.text('Reintentar foto'));
    expect(submit.ids, [id, id, id], reason: 'nunca crea otro reporte');
    expect(find.text('Reporte recibido'), findsOneWidget);
    expect(storage.value, isNull);
    expect(reports.updates, isEmpty);
  });

  testWidgets(
      'tras reabrir la app, un borrador con foto pendiente sigue ofreciendo reintento y descarte con ocultamiento',
      (tester) async {
    final events = <String>[];
    final storage = _Storage(events);
    final reports = _Reports(events);
    final submit = await _mount(tester, storage, reports);
    await _toPending(tester, submit);
    final saved = storage.value!;

    // Simula cierre y reapertura: nueva pantalla, mismo almacenamiento.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final reopened = _Storage(events)..value = saved;
    await _mount(tester, reopened, reports);
    await _reveal(tester, find.byKey(const Key('discard-report-draft')));
    expect(find.text('Reintentar foto'), findsOneWidget,
        reason: 'el estado "foto pendiente" no se persiste en el borrador');
    await _discard(tester);
    await tester.pumpAndSettle();
    expect(reports.updates, isNotEmpty,
        reason: 'el reporte ya recibido debe ocultarse antes de borrar');
  });
}
