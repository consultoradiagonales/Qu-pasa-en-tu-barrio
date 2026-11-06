import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:que_pasa_en_tu_barrio/firebase_options.dart';
import 'package:que_pasa_en_tu_barrio/features/report/report_flow.dart';
import 'package:que_pasa_en_tu_barrio/features/report/screens/new_report_screen.dart';

class LocalCapture extends ReportCaptureService {
  LocalCapture(this.file);
  final XFile file;
  @override
  Future<XFile?> camera() async => file;
  @override
  Future<XFile?> recoverPhoto() async => null;
  @override
  Future<LatLng> gps() async => const LatLng(-35.6384, -59.7779);
}

class LocalDraftStorage extends ReportDraftStorage {
  @override
  Future<ReportDraft?> read() async => null;
  @override
  Future<void> write(ReportDraft? draft) async {}
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapRevealed(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _selectCategory(WidgetTester tester, String label) async {
  final dropdown = find.byKey(const Key('report-category'));
  await _tapRevealed(tester, dropdown);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Foto, GPS, comentario vacío: recepción real en Firestore y Storage',
    (tester) async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = FirebaseAuth.instance;
      await auth.signOut();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final credential = await auth.createUserWithEmailAndPassword(
        email: 'photoqa.$stamp@example.com',
        password: 'QaPhoto!$stamp',
      );
      final db = FirebaseFirestore.instance;
      final uid = credential.user!.uid;
      final profile = db.collection('users').doc(uid);
      final dir = await Directory.systemTemp.createTemp('condi-photo-');
      final file = File('${dir.path}/photo.png');
      await file.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=',
        ),
      );
      try {
        await profile.set({
          'displayName': 'QA ConDi',
          'realName': 'Prueba automática',
          'email': credential.user!.email,
          'role': 'citizen',
          'municipalityId': '060707',
          'disabled': false,
          'reportsCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'lastReportAt': null,
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reportCaptureProvider.overrideWithValue(
                LocalCapture(XFile(file.path)),
              ),
              reportDraftStorageProvider.overrideWithValue(LocalDraftStorage()),
            ],
            child: const MaterialApp(home: NewReportScreen(showMap: false)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('¿Dónde está?'), findsOneWidget);
        await _tapRevealed(tester, find.text('Usar mi ubicación'));
        await _tapRevealed(tester, find.text('Usar esta ubicación'));
        await tester.scrollUntilVisible(
          find.byKey(const Key('photo-evidence-confirmed')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('photo-evidence-confirmed')));
        await _selectCategory(tester, 'Otro');
        await tester.tap(find.text('Enviar reporte'));
        for (var i = 0;
            i < 120 && find.text('Reporte recibido').evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(
          find.text('Reporte recibido'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '),
        );
        final reports = await db
            .collection('reports')
            .where('userId', isEqualTo: uid)
            .get(const GetOptions(source: Source.server));
        expect(reports.docs.length, 1);
        final report = reports.docs.single.data();
        expect(report['description'], '');
        expect(report['title'], 'Otro');
        expect(report['status'], 'pending');
        expect(report['municipalityId'], '060707');
        expect((report['location']['lat'] as num).toDouble(), -35.6384);
        final photos = List<String>.from(report['photosReport']);
        expect(photos.length, 1);
        expect(
          await FirebaseStorage.instance.refFromURL(photos.single).getData(),
          isNotEmpty,
        );
      } finally {
        final reports = await db
            .collection('reports')
            .where('userId', isEqualTo: uid)
            .get();
        for (final report in reports.docs) {
          await report.reference.update({'hidden': true});
          for (final url in List<String>.from(
            report.data()['photosReport'] ?? [],
          )) {
            try {
              await FirebaseStorage.instance.refFromURL(url).delete();
            } catch (_) {}
          }
        }
        await profile.delete();
        await credential.user!.delete();
        await dir.delete(recursive: true);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
