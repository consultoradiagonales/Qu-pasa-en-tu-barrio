import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/services/report_submission_policy.dart';

void main() {
  Map<String, dynamic> submission() => {
        'userId': 'neighbor-a',
        'municipalityId': 'municipality-a',
        'title': 'Luminaria apagada',
        'description': 'No enciende',
        'category': 'lighting',
        'aiRequested': false,
        'aiConsentVersion': 0,
        'photosReport': ['https://example.test/photo'],
        'location': {
          'lat': -34.5,
          'lng': -58.5,
          'geohash': '69y',
          'address': null,
          'isManualAddress': false
        },
      };

  test('Un reintento reconoce el caso aun después de asignarlo o resolverlo',
      () {
    final stored = {
      ...submission(),
      'status': 'resolved',
      'assignedTeamId': 'team',
      'priority': 4
    };
    expect(matchesReportSubmission(stored, submission()), isTrue);
  });

  test(
      'Un UUID no se reutiliza con otro autor, ámbito, texto, consentimiento, foto o punto',
      () {
    for (final change in <Map<String, dynamic>>[
      {'userId': 'neighbor-b'},
      {'municipalityId': 'municipality-b'},
      {'description': 'Otra descripción'},
      {'aiRequested': true, 'aiConsentVersion': 1},
      {
        'photosReport': ['https://example.test/other']
      },
      {
        'location': {...submission()['location'] as Map, 'lat': -35.0}
      },
    ]) {
      expect(
          matchesReportSubmission(submission(), {...submission(), ...change}),
          isFalse);
    }
  });

  test('La cuota elige una posición libre sin depender de la hora del teléfono',
      () {
    expect(nextReportQuotaSlot({}), '0');
    expect(
        nextReportQuotaSlot({'0': Timestamp(100, 0), '1': Timestamp(200, 0)}),
        '2');
  });

  test(
      'Con diez posiciones elige la más antigua para que el servidor valide 24 h',
      () {
    final slots = {
      for (var index = 0; index < 10; index++)
        '$index': Timestamp(100 + index, 0)
    };
    slots['7'] = Timestamp(10, 0);
    expect(nextReportQuotaSlot(slots), '7');
  });
}
