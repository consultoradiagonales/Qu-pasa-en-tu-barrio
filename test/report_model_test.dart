import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/models/report_model.dart';

void main() {
  final instant = DateTime.utc(2026, 10, 11, 12);

  test('serializa un reporte listo para enviar', () {
    final report = ReportModel(
      id: 'qa-1',
      userId: 'citizen-1',
      municipalityId: 'la-plata',
      title: 'Bache peligroso',
      description: 'Frente a la plaza',
      category: ReportCategory.infrastructure,
      photosReport: const ['https://example.com/photo.jpg'],
      location: const ReportLocation(
        lat: -34.9214,
        lng: -57.9544,
        geohash: '69y7p',
        address: 'Calle 7 y 50',
        isManualAddress: true,
      ),
      createdAt: instant,
      updatedAt: instant,
    );

    final data = report.toFirestore();
    expect(data['status'], 'pending');
    expect(data['location']['lat'], -34.9214);
    expect(data['location']['isManualAddress'], true);
    expect(data['photosReport'], hasLength(1));
    expect(data['createdAt'], isA<Timestamp>());
  });

  test('interpreta estados y fechas de Firestore', () {
    expect(ReportStatus.fromString('in_progress'), ReportStatus.inProgress);
    expect(ReportStatus.fromString('desconocido'), ReportStatus.pending);
    expect(ReportCategory.fromString('lighting'), ReportCategory.lighting);
    expect(ReportCategory.fromString('x'), ReportCategory.other);
  });

  test('la ubicación conserva coordenadas y dirección manual', () {
    final location = ReportLocation.fromMap(const {
      'lat': -34.9,
      'lng': -57.95,
      'geohash': '69y7p',
      'address': 'Diagonal 80 y 49',
      'isManualAddress': true,
    });
    expect(location.latLng.latitude, -34.9);
    expect(location.address, 'Diagonal 80 y 49');
    expect(location.isManualAddress, true);
  });
}
