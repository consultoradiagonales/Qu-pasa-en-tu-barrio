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
      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();
      expect(events, ['camera', 'gps']);
      await tester.tap(find.text('Usar esta ubicación'));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();
      expect(submit.calls, 1);
      expect(submit.submitted!.comment, '');
      expect(submit.submitted!.presetId, 'other');
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
    await tester.tap(find.text('Usar mi ubicación'));
    await tester.pumpAndSettle();
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
  testWidgets('Manual address can continue without GPS or a map',
      (tester) async {
    final submit = await mount(
      tester,
      FakeCapture(photo, <String>[]),
      MemoryStorage(),
    );
    await tester.enterText(
      find.byKey(const Key('manual-address')),
      'Calle 133 entre 43 y 44',
    );
    await tester.tap(find.byKey(const Key('use-manual-address')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-location')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('photo-evidence-confirmed')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(submit.calls, 1);
    expect(submit.submitted!.usesManualAddress, true);
    expect(submit.submitted!.location, isNull);
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
    await tester.tap(find.text('Usar mi ubicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar esta ubicación'));
    await tester.pumpAndSettle();
    submit.pending = Completer<String>();
    await tester.scrollUntilVisible(
      find.byKey(const Key('photo-evidence-confirmed')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
    await tester.pumpAndSettle();
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
}
