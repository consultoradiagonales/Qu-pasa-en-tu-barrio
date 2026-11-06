import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/services/immutable_report_photo.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  FirebaseException missing() =>
      FirebaseException(plugin: 'firebase_storage', code: 'object-not-found');

  test('Una foto ya subida se reutiliza sin intentar sobrescribirla', () async {
    var uploads = 0;
    final url = await uploadImmutableReportPhoto(
        bytes: bytes,
        read: () async => Uint8List.fromList([1, 2, 3]),
        upload: () async {
          uploads++;
        },
        downloadUrl: () async => 'confirmed');
    expect(url, 'confirmed');
    expect(uploads, 0);
  });

  test('El primer envío carga una sola vez y devuelve su URL', () async {
    var uploads = 0;
    expect(
        await uploadImmutableReportPhoto(
            bytes: bytes,
            read: () async => throw missing(),
            upload: () async {
              uploads++;
            },
            downloadUrl: () async => 'created'),
        'created');
    expect(uploads, 1);
  });

  test(
      'Una foto distinta en la misma ruta conserva evidencia y exige nuevo reporte',
      () async {
    var uploads = 0;
    await expectLater(
        uploadImmutableReportPhoto(
            bytes: bytes,
            read: () async => Uint8List.fromList([9, 9]),
            upload: () async {
              uploads++;
            },
            downloadUrl: () async => 'wrong'),
        throwsStateError);
    expect(uploads, 0);
  });

  test(
      'Una respuesta de carga perdida se recupera sólo comparando los bytes guardados',
      () async {
    var reads = 0;
    expect(
        await uploadImmutableReportPhoto(
            bytes: bytes,
            read: () async {
              if (reads++ == 0) throw missing();
              return bytes;
            },
            upload: () async => throw FirebaseException(
                plugin: 'firebase_storage', code: 'retry-limit-exceeded'),
            downloadUrl: () async => 'recovered'),
        'recovered');
  });

  test('Una carga fallida sin objeto confirmado no se informa como éxito',
      () async {
    final failure = FirebaseException(
        plugin: 'firebase_storage', code: 'retry-limit-exceeded');
    await expectLater(
        uploadImmutableReportPhoto(
            bytes: bytes,
            read: () async => throw missing(),
            upload: () async => throw failure,
            downloadUrl: () async => 'wrong'),
        throwsA(same(failure)));
  });

  test('Un error de lectura no autoriza cargar ni sobrescribir', () async {
    var uploads = 0;
    final denied =
        FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
    await expectLater(
        uploadImmutableReportPhoto(
            bytes: bytes,
            read: () async => throw denied,
            upload: () async {
              uploads++;
            },
            downloadUrl: () async => 'wrong'),
        throwsA(same(denied)));
    expect(uploads, 0);
  });

  test('Rechaza imagen vacía o en el límite de 8 MB antes de tocar la red',
      () async {
    var reads = 0;
    for (final invalid in [Uint8List(0), Uint8List(8 * 1024 * 1024)]) {
      await expectLater(
          uploadImmutableReportPhoto(
              bytes: invalid,
              read: () async {
                reads++;
                return null;
              },
              upload: () async {},
              downloadUrl: () async => 'wrong'),
          throwsStateError);
    }
    expect(reads, 0);
  });
}
