import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:que_pasa_en_tu_barrio/features/report/report_flow.dart';
import 'package:que_pasa_en_tu_barrio/features/report/report_insight.dart';
import 'package:que_pasa_en_tu_barrio/features/report/screens/new_report_screen.dart';
import 'package:que_pasa_en_tu_barrio/core/router/navigation_policy.dart';
import 'package:que_pasa_en_tu_barrio/data/models/user_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/reports_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/georef_service.dart';

class FakeReportGeoRef extends GeoRefService {
  FakeReportGeoRef({this.hasCenter = true});
  final bool hasCenter;

  @override
  Future<({double lat, double lng, double zoom})?> municipalityCenter(
          String id) async =>
      !hasCenter
          ? null
          : id == 'georef_060707'
              ? (lat: -35.6384, lng: -59.7779, zoom: 13.0)
              : (lat: -34.92145, lng: -57.95453, zoom: 13.0);

  @override
  Future<List<LocalitySuggestion>> searchLocalities(String query) async =>
      const [
        LocalitySuggestion(
          id: '06441010',
          name: 'La Plata',
          provinceId: '06',
          province: 'Buenos Aires',
          latitude: -34.92145,
          longitude: -57.95453,
        ),
      ];

  @override
  Future<List<MunicipalitySuggestion>> searchMunicipalities(
          String query) async =>
      const [
        MunicipalitySuggestion(
            id: '060707',
            name: 'Saladillo',
            provinceId: '06',
            province: 'Buenos Aires')
      ];

  @override
  Future<GeoRefPlace?> municipalityAt(double lat, double lng) async => null;
}

class MemoryStorage extends ReportDraftStorage {
  ReportDraft? value;
  @override
  Future<ReportDraft?> read() async => value;
  @override
  Future<void> write(ReportDraft? draft) async {
    value = draft;
  }
}

class FakeCapture extends ReportCaptureService {
  FakeCapture(this.photo, this.events);
  XFile? photo;
  final List<String> events;
  bool gpsDenied = false;
  @override
  Future<Uint8List> readPhoto(String path) async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=',
      );
  @override
  Future<XFile?> recoverPhoto() async => null;
  @override
  Future<XFile?> camera() async {
    events.add('camera');
    return photo;
  }

  @override
  Future<LatLng> gps() async {
    events.add('gps');
    if (gpsDenied) throw StateError('Marcá el punto en el mapa.');
    return const LatLng(-34.92145, -57.95453);
  }
}

class FakeSubmit extends ReportSubmitService {
  FakeSubmit(super.ref);
  int calls = 0;
  ReportDraft? submitted;
  Completer<String>? pending;
  Object? failOnce;
  @override
  bool get signedIn => true;
  @override
  Future<String> submit(ReportDraft draft) async {
    calls++;
    submitted = draft;
    if (failOnce != null) {
      final error = failOnce!;
      failOnce = null;
      throw error;
    }
    return pending == null ? 'report-confirmed' : await pending!.future;
  }
}

class FakeReportsRepository implements ReportsRepository {
  final updates = <(String, Map<String, dynamic>)>[];
  Object? failOnce;

  @override
  Future<void> updateReport(String id, Map<String, dynamic> fields) async {
    updates.add((id, fields));
    if (failOnce case final error?) {
      failOnce = null;
      throw error;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final homeProfile = UserModel(
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
  final photo = XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=',
    ),
    path: '/test/photo.png',
  );

  Future<FakeSubmit> mount(
    WidgetTester tester,
    FakeCapture capture,
    MemoryStorage storage, {
    bool dark = false,
    double scale = 1,
    UserModel? profile,
    GeoRefService? geoRef,
    FakeReportsRepository? reports,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    late FakeSubmit submit;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportInsightProvider.overrideWith((ref, id) => Stream.value(null)),
          reportCaptureProvider.overrideWithValue(capture),
          reportDraftStorageProvider.overrideWithValue(storage),
          reportSubmitProvider.overrideWith((ref) => submit = FakeSubmit(ref)),
          reportProfileProvider.overrideWithValue(AsyncData(profile)),
          reportGeoRefProvider.overrideWithValue(geoRef ?? FakeReportGeoRef()),
          if (reports != null)
            reportsRepositoryProvider.overrideWithValue(reports),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: InkRipple.splashFactory,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const NewReportScreen(showMap: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Force creation if the screen has not requested submission yet.
    final c = ProviderScope.containerOf(
      tester.element(find.byType(NewReportScreen)),
    );
    c.read(reportSubmitProvider);
    return submit;
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    for (var attempt = 0;
        attempt < 12 && finder.evaluate().isEmpty;
        attempt++) {
      await tester.drag(scrollable, const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> selectCategory(WidgetTester tester, String label) async {
    final dropdown = find.byKey(const Key('report-category'));
    await reveal(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapRevealed(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test(
    'Default login destination never chooses management based on the role',
    () {
      expect(signedInDestination(null), citizenStartLocation);
      expect(
        signedInDestination('https://other.example'),
        citizenStartLocation,
      );
      expect(signedInDestination('report'), '/report/new?resume=1');
      expect(canOpenOperations('/admin', 'admin', enabled: false), false);
      expect(canOpenOperations('/admin', 'citizen', enabled: true), false);
      expect(canOpenOperations('/admin', 'admin', enabled: true), true);
    },
  );
  testWidgets(
    'Camera waits for an explicit location request and sends reviewed evidence',
    (tester) async {
      final events = <String>[];
      final storage = MemoryStorage();
      final submit = await mount(tester, FakeCapture(photo, events), storage);
      expect(events, ['camera']);
      expect(find.text('¿Dónde está?'), findsOneWidget);
      expect(find.text('Centro de gestión'), findsNothing);
      await tapRevealed(tester, find.text('Usar mi ubicación'));
      expect(events, ['camera', 'gps']);
      await tapRevealed(tester, find.text('Usar esta ubicación'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('photo-evidence-confirmed')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final sendBeforeReview = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enviar reporte'),
      );
      expect(sendBeforeReview.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
      await selectCategory(tester, 'Bache');
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();
      expect(submit.calls, 1);
      expect(submit.submitted!.comment, '');
      expect(submit.submitted!.presetId, 'pothole');
      expect(submit.submitted!.locationConfirmed, true);
      expect(find.text('Reporte recibido'), findsOneWidget);
      expect(storage.value, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cancelling camera leaves an actionable screen without asking GPS',
    (tester) async {
      final events = <String>[];
      await mount(tester, FakeCapture(null, events), MemoryStorage());
      expect(events, ['camera']);
      expect(find.text('Sacar foto'), findsOneWidget);
      expect(find.text('Enviar reporte'), findsNothing);
    },
  );
  testWidgets('la foto pendiente conserva el borrador y permite reintentar',
      (tester) async {
    final storage = MemoryStorage();
    final submit = await mount(tester, FakeCapture(photo, <String>[]), storage);
    await tapRevealed(tester, find.text('Usar mi ubicación'));
    await tapRevealed(tester, find.text('Usar esta ubicación'));
    await tapRevealed(
        tester, find.byKey(const Key('photo-evidence-confirmed')));
    await selectCategory(tester, 'Bache');
    submit.failOnce = ReportSubmissionException(
      'La foto quedó pendiente.',
      photoPending: true,
    );
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar foto'), findsOneWidget);
    expect(storage.value, isNotNull);
    await tester.tap(find.text('Reintentar foto'));
    await tester.pumpAndSettle();
    expect(submit.calls, 2);
    expect(find.text('Reporte recibido'), findsOneWidget);
    expect(storage.value, isNull);
  });
  testWidgets(
      'descartar foto pendiente oculta primero el reporte y conserva el borrador si falla',
      (tester) async {
    final storage = MemoryStorage();
    final reports = FakeReportsRepository();
    final submit = await mount(tester, FakeCapture(photo, <String>[]), storage,
        reports: reports);
    await tapRevealed(tester, find.text('Usar mi ubicación'));
    await tapRevealed(tester, find.text('Usar esta ubicación'));
    await tapRevealed(
        tester, find.byKey(const Key('photo-evidence-confirmed')));
    await selectCategory(tester, 'Bache');
    submit.failOnce = ReportSubmissionException(
      'La foto quedó pendiente.',
      photoPending: true,
    );
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    final pendingId = storage.value!.id;

    reports.failOnce = StateError('Sin conexión');
    await tester.tap(find.byKey(const Key('discard-report-draft')));
    await tester.pumpAndSettle();
    expect(find.text('Desistir del reporte pendiente'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(reports.updates, hasLength(1));
    expect(reports.updates.single.$1, pendingId);
    expect(reports.updates.single.$2, {'hidden': true});
    expect(storage.value!.id, pendingId);
    expect(find.text('Reintentar foto'), findsOneWidget);
    expect(find.textContaining('Conservamos el borrador'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discard-report-draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(reports.updates, hasLength(2));
    expect(reports.updates.last.$1, pendingId);
    expect(reports.updates.last.$2, {'hidden': true});
    expect(storage.value, isNull);
    expect(find.text('Reintentar foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('descartar un borrador sin enviar no toca el reporte remoto',
      (tester) async {
    final storage = MemoryStorage();
    final reports = FakeReportsRepository();
    await mount(tester, FakeCapture(photo, <String>[]), storage,
        reports: reports);
    expect(storage.value, isNotNull);
    await tester.tap(find.byKey(const Key('discard-report-draft')));
    await tester.pumpAndSettle();
    expect(find.text('Descartar reporte inconcluso'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(reports.updates, isEmpty);
    expect(storage.value, isNull);
    expect(find.text('Sacar foto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Denied GPS does not invent a location or enable sending', (
    tester,
  ) async {
    final capture = FakeCapture(photo, <String>[])..gpsDenied = true;
    await mount(tester, capture, MemoryStorage());
    await tapRevealed(tester, find.text('Usar mi ubicación'));
    await tester.scrollUntilVisible(
      find.text('Marcá el punto en el mapa.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Marcá el punto en el mapa.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Usar esta ubicación'),
    );
    expect(button.onPressed, isNotNull);
  });
  testWidgets('Manual address requires choosing a city from the suggestions',
      (tester) async {
    const address =
        'Av. 7 Nº 1234, Torre A - 2° B, entre 48/49. Frente al parque.';
    final storage = MemoryStorage();
    final submit = await mount(
      tester,
      FakeCapture(photo, <String>[]),
      storage,
    );
    await tester.enterText(
      find.byKey(const Key('manual-address')),
      address,
    );
    await tester.pumpAndSettle();
    expect(storage.value?.address, address);
    expect(find.byKey(const Key('manual-intersection')), findsNothing);
    expect(find.byKey(const Key('manual-height')), findsNothing);
    await tapRevealed(tester, find.byKey(const Key('use-manual-address')));
    expect(
      find.text('Elegí una ciudad o localidad de la lista.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-location')),
    );
    expect(button.onPressed, isNotNull);
    expect(submit.calls, 0);
  });

  testWidgets('Manual address button advances with the municipality reference',
      (tester) async {
    final events = <String>[];
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, events), storage,
        profile: homeProfile);
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tapRevealed(tester, find.byKey(const Key('use-manual-address')));

    expect(find.text('Listo para enviar'), findsOneWidget);
    expect(storage.value!.locationConfirmed, true);
    expect(storage.value!.usesManualAddress, true);
    expect(storage.value!.location, const LatLng(-34.92145, -57.95453));
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
    expect(storage.value!.reportsAwayFromHome, false);
    expect(events, ['camera']);
  });

  testWidgets('Legacy municipality without a name accepts its manual address',
      (tester) async {
    final legacyProfile = UserModel(
      uid: 'legacy-citizen',
      displayName: 'Vecino',
      realName: 'Vecino de prueba',
      email: 'vecino@example.test',
      role: UserRole.citizen,
      municipalityId: 'la-plata',
      createdAt: DateTime(2026, 1, 1),
    );
    final events = <String>[];
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, events), storage,
        profile: legacyProfile);
    await tester.enterText(
        find.byKey(const Key('manual-address')), '46 N 1236');
    await tapRevealed(tester, find.byKey(const Key('use-manual-address')));

    expect(find.text('Listo para enviar'), findsOneWidget);
    expect(storage.value!.territory, 'La Plata');
    expect(storage.value!.location, const LatLng(-34.92145, -57.95453));
    expect(storage.value!.locationConfirmed, true);
    expect(storage.value!.usesManualAddress, true);
    expect(storage.value!.reportMunicipalityId, isNull);
    expect(legacyProfile.municipalityId, 'la-plata');
    expect(events, ['camera']);
  });

  testWidgets('Manual address advances with a selected locality without GPS',
      (tester) async {
    final events = <String>[];
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, events), storage);
    await tester.enterText(find.byKey(const Key('locality-input')), 'La Plata');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La Plata, Buenos Aires').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tapRevealed(tester, find.byKey(const Key('use-manual-address')));

    expect(find.text('Listo para enviar'), findsOneWidget);
    expect(storage.value!.locationConfirmed, true);
    expect(storage.value!.usesManualAddress, true);
    expect(storage.value!.location, const LatLng(-34.92145, -57.95453));
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
    expect(events, ['camera']);
  });

  testWidgets('Clearing a selected locality invalidates its old coordinates',
      (tester) async {
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, <String>[]), storage);
    await tester.enterText(find.byKey(const Key('locality-input')), 'La Plata');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La Plata, Buenos Aires').last);
    await tester.pumpAndSettle();
    expect(storage.value!.location, isNotNull);

    await tester.enterText(
        find.byKey(const Key('locality-input')), 'Otra ciudad');
    await tester.pumpAndSettle();
    expect(storage.value!.territory, isEmpty);
    expect(storage.value!.location, isNull);
    expect(storage.value!.locationConfirmed, false);
  });

  testWidgets('Manual address never invents a missing municipality reference',
      (tester) async {
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, <String>[]), storage,
        profile: homeProfile, geoRef: FakeReportGeoRef(hasCenter: false));
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tapRevealed(tester, find.byKey(const Key('use-manual-address')));

    expect(find.text('Listo para enviar'), findsNothing);
    expect(storage.value!.location, isNull);
    expect(storage.value!.locationConfirmed, false);
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
  });

  testWidgets('A category must be selected before sending', (tester) async {
    final submit = await mount(
      tester,
      FakeCapture(photo, <String>[]),
      MemoryStorage(),
    );
    await tapRevealed(tester, find.text('Usar mi ubicación'));
    await tapRevealed(tester, find.text('Usar esta ubicación'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('photo-evidence-confirmed')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
    await tester.pumpAndSettle();
    var send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enviar reporte'),
    );
    expect(send.onPressed, isNotNull);
    await selectCategory(tester, 'Bache');
    send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enviar reporte'),
    );
    expect(send.onPressed, isNotNull);
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(submit.calls, 1);
    expect(submit.submitted!.presetId, 'pothole');
  });
  testWidgets(
    'Saved draft survives authentication/recreation without reopening camera',
    (tester) async {
      final events = <String>[];
      final store = MemoryStorage()
        ..value = ReportDraft(
          photoPath: photo.path,
          location: const LatLng(-34.92, -57.95),
          locationConfirmed: true,
          comment: 'Frente a la plaza',
          presetId: 'light',
        );
      await mount(tester, FakeCapture(photo, events), store);
      expect(events, isEmpty);
      expect(find.text('Listo para enviar'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('optional-comment')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('optional-comment')))
            .controller!
            .text,
        'Frente a la plaza',
      );
    },
  );
  testWidgets('Repeated send taps do not submit twice', (tester) async {
    final submit = await mount(
      tester,
      FakeCapture(photo, <String>[]),
      MemoryStorage(),
    );
    await tapRevealed(tester, find.text('Usar mi ubicación'));
    await tapRevealed(tester, find.text('Usar esta ubicación'));
    submit.pending = Completer<String>();
    await tester.scrollUntilVisible(
      find.byKey(const Key('photo-evidence-confirmed')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
    await selectCategory(tester, 'Bache');
    await tester.tap(find.text('Enviar reporte'));
    await tester.pump();
    await tester.tap(find.text('Enviando…'));
    await tester.pump();
    expect(submit.calls, 1);
    submit.pending!.complete('report-confirmed');
    await tester.pumpAndSettle();
  });
  testWidgets('Dark mode and large text fit without layout exceptions', (
    tester,
  ) async {
    await mount(
      tester,
      FakeCapture(null, <String>[]),
      MemoryStorage(),
      dark: true,
      scale: 2,
    );
    expect(find.text('Sacar foto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'El municipio de la cuenta queda elegido y sólo se pide dirección',
      (tester) async {
    final events = <String>[];
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, events), storage,
        profile: homeProfile);
    expect(
        find.byKey(const Key('report-municipality-summary')), findsOneWidget);
    expect(find.text('La Plata, Buenos Aires'), findsOneWidget);
    expect(find.byKey(const Key('manual-locality')), findsNothing);
    expect(find.byKey(const Key('territory-municipality')), findsNothing);
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tapRevealed(tester, find.byKey(const Key('confirm-location')));
    expect(find.text('Listo para enviar'), findsOneWidget);
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
    expect(storage.value!.reportsAwayFromHome, false);
    expect(storage.value!.usesManualAddress, true);
    expect(events, ['camera']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('La dirección faltante se muestra en el campo y recibe el foco',
      (tester) async {
    await mount(tester, FakeCapture(photo, <String>[]), MemoryStorage(),
        profile: homeProfile);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tapRevealed(tester, find.byKey(const Key('confirm-location')));
    final address =
        tester.widget<TextField>(find.byKey(const Key('manual-address')));
    expect(address.focusNode!.hasFocus, true);
    expect(address.decoration!.errorText,
        'Completá la dirección o una referencia del lugar.');
    expect(
        find.byKey(const Key('manual-address')).hitTestable(), findsOneWidget);
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('manual-address')))
            .decoration!
            .errorText,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Enviar lleva primero a confirmar la foto y después a la categoría',
      (tester) async {
    final store = MemoryStorage()
      ..value = ReportDraft(
        photoPath: photo.path,
        location: const LatLng(-34.92, -57.95),
        locationConfirmed: true,
      );
    final submit = await mount(tester, FakeCapture(photo, <String>[]), store);
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(
        find.text('Confirmá que la foto muestra el problema.'), findsOneWidget);
    expect(find.byKey(const Key('photo-evidence-confirmed')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    final category = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('report-category')));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'report-category');
    expect(category.decoration.errorText,
        'Elegí el tipo de problema para enviar el reporte.');
    expect(
        find.byKey(const Key('report-category')).hitTestable(), findsOneWidget);
    expect(submit.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Otro municipio se aplica sólo al reporte y se puede volver al habitual',
      (tester) async {
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, <String>[]), storage,
        profile: homeProfile);
    await tapRevealed(
        tester, find.byKey(const Key('change-report-municipality')));
    await tester.enterText(
        find.byKey(const Key('municipality-input')), 'Saladillo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saladillo, Buenos Aires').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-report-municipality')));
    await tester.pumpAndSettle();
    expect(storage.value!.reportMunicipalityId, 'georef_060707');
    expect(storage.value!.territory, 'Saladillo, Buenos Aires');
    expect(storage.value!.location!.latitude, closeTo(-35.6384, .0001));
    expect(homeProfile.municipalityId, 'georef_06441');
    await tapRevealed(tester, find.byKey(const Key('use-home-municipality')));
    expect(storage.value!.reportsAwayFromHome, false);
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
    expect(storage.value!.location!.latitude, closeTo(-34.92145, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Un reporte nuevo vuelve a usar el municipio habitual',
      (tester) async {
    final storage = MemoryStorage();
    await mount(tester, FakeCapture(photo, <String>[]), storage,
        profile: homeProfile);
    await tester.enterText(find.byKey(const Key('manual-address')), '7 y 48');
    await tapRevealed(tester, find.byKey(const Key('confirm-location')));
    await tapRevealed(
        tester, find.byKey(const Key('photo-evidence-confirmed')));
    await selectCategory(tester, 'Bache');
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reportar otro problema'));
    await tester.pumpAndSettle();
    expect(find.text('La Plata, Buenos Aires'), findsOneWidget);
    expect(storage.value!.territory, 'La Plata, Buenos Aires');
    expect(storage.value!.reportMunicipalityId, isNull);
    expect(storage.value!.address, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('New report options are available once and keep broad categories', () {
    final byLabel = {for (final preset in reportPresets) preset.label: preset};
    expect(
      byLabel.keys,
      containsAll(const [
        'Agua estancada',
        'Plagas',
        'Ruidos molestos',
        'Venta de droga',
        'Picada motos o autos',
        'Robos reiterados',
        'Calle anegada',
        'Disturbios',
        'Otro',
      ]),
    );
    expect(reportPresets.where((preset) => preset.label == 'Otro').length, 1);
    expect(byLabel['Venta de droga']!.category.value, 'security');
    expect(byLabel['Calle anegada']!.category.value, 'infrastructure');
  });

  test('El borrador conserva un municipio temporal sin cambiar el habitual',
      () {
    final draft = ReportDraft(
      reportMunicipalityId: 'georef_060707',
      reportMunicipalityName: 'Saladillo',
      reportProvinceId: '06',
      reportProvince: 'Buenos Aires',
    );
    final restored = ReportDraft.fromJson(draft.toJson());
    expect(restored.reportsAwayFromHome, true);
    expect(restored.reportMunicipalityId, 'georef_060707');
    expect(restored.reportMunicipalityName, 'Saladillo');
    expect(restored.copyWith(clearReportMunicipality: true).reportsAwayFromHome,
        false);
  });
}
