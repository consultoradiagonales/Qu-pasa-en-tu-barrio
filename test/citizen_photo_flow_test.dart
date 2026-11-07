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
  @override
  bool get signedIn => true;
  @override
  Future<String> submit(ReportDraft draft) async {
    calls++;
    submitted = draft;
    return pending == null ? 'report-confirmed' : await pending!.future;
  }
}

void main() {
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
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
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
      expect(sendBeforeReview.onPressed, isNull);
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
    expect(button.onPressed, isNull);
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
    expect(button.onPressed, isNull);
    expect(submit.calls, 0);
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
    expect(send.onPressed, isNull);
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
}
