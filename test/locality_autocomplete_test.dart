import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/core/widgets/locality_autocomplete.dart';
import 'package:que_pasa_en_tu_barrio/data/services/georef_service.dart';

LocalitySuggestion _locality(
  String id,
  String name,
  String province, {
  double? latitude,
  double? longitude,
}) =>
    LocalitySuggestion(
      id: id,
      name: name,
      provinceId: 'p$id',
      province: province,
      latitude: latitude,
      longitude: longitude,
    );

void main() {
  group('LocalitySuggestion', () {
    test('muestra la provincia para distinguir ciudades homónimas', () {
      expect(
        _locality('1', 'San Martín', 'Buenos Aires').label,
        'San Martín, Buenos Aires',
      );
      expect(
        _locality('2', 'San Martín', 'San Luis').label,
        'San Martín, San Luis',
      );
    });

    test('lee el centroide que usará como referencia manual', () {
      final locality = LocalitySuggestion.fromJson({
        'id': '06421',
        'nombre': 'Saladillo',
        'provincia': {'id': '06', 'nombre': 'Buenos Aires'},
        'centroide': {'lat': -35.6384, 'lon': -59.7779},
      });
      expect(locality.label, 'Saladillo, Buenos Aires');
      expect(locality.hasCoordinates, isTrue);
      expect(locality.latitude, -35.6384);
      expect(locality.longitude, -59.7779);
    });
  });

  test('prioriza la coincidencia exacta y ordena homónimos por provincia', () {
    final results = rankLocalitySuggestions('saladillo', [
      _locality('1', 'Paraje Saladillo', 'Córdoba'),
      _locality('2', 'Saladillo', 'San Luis'),
      _locality('3', 'Saladillo', 'Buenos Aires'),
    ]);
    expect(results.map((item) => item.label), [
      'Saladillo, Buenos Aires',
      'Saladillo, San Luis',
      'Paraje Saladillo, Córdoba',
    ]);
  });

  testWidgets('permite elegir un homónimo por su provincia', (tester) async {
    LocalitySuggestion? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalityAutocomplete(
            search: (_) async => [
              _locality('1', 'Saladillo', 'Buenos Aires'),
              _locality('2', 'Saladillo', 'San Luis'),
            ],
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('locality-input')), 'salad');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Saladillo, Buenos Aires'), findsOneWidget);
    expect(find.text('Saladillo, San Luis'), findsOneWidget);

    await tester.tap(find.text('Saladillo, San Luis'));
    await tester.pumpAndSettle();
    expect(selected?.id, '2');
    expect(find.text('Elegiste Saladillo, San Luis'), findsOneWidget);
  });
}
