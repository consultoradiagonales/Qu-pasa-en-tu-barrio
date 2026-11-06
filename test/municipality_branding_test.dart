import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/core/config/municipality_branding.dart';
import 'package:que_pasa_en_tu_barrio/core/widgets/municipality_identity.dart';

void main() {
  test('La Plata resolves by raw id, georef id and municipality name', () {
    for (final branding in [
      MunicipalityBranding.resolve(municipalityId: '06441'),
      MunicipalityBranding.resolve(municipalityId: 'georef_06441'),
      MunicipalityBranding.resolve(municipalityId: 'georef_060441'),
      MunicipalityBranding.resolve(municipalityName: 'La Plata'),
    ]) {
      expect(branding.key, 'la_plata');
      expect(branding.displayName, 'Municipalidad de La Plata');
      expect(branding.crestAssetPath,
          'assets/images/municipalities/la_plata_crest.svg');
    }
  });

  test(
      'Las identidades solicitadas tienen un escudo propio sin mezclar jurisdicciones',
      () {
    for (final entry in {
      '060826': 'Trenque Lauquen',
      '060707': 'Saladillo',
      '060252': 'Escobar',
      '060679': 'Rivadavia',
    }.entries) {
      final branding =
          MunicipalityBranding.resolve(municipalityId: 'georef_${entry.key}');
      expect(branding.name, entry.value);
      expect(branding.hasCrest, isTrue);
      expect(branding.key, isNot('la_plata'));
    }
    final province = MunicipalityBranding.resolve(municipalityId: '06');
    expect(province.displayName, 'Provincia de Buenos Aires');
    expect(province.hasCrest, isTrue);
  });

  test('An unknown municipality keeps its own name and generic identity', () {
    final branding = MunicipalityBranding.resolve(
      municipalityId: '99999',
      municipalityName: 'Municipio de prueba',
    );

    expect(branding.key, 'generic');
    expect(branding.displayName, 'Municipio de prueba');
    expect(branding.hasCrest, isFalse);
  });

  testWidgets('Municipality identity renders La Plata crest and name',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MunicipalityIdentity(
            municipalityId: 'georef_06441',
            municipalityName: 'La Plata',
            subtitle: 'Tu municipio',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const Key('municipality-crest-la_plata')), findsOneWidget);
    expect(find.text('Municipalidad de La Plata'), findsOneWidget);
    expect(find.text('Tu municipio'), findsOneWidget);
  });

  testWidgets('Municipality identity uses a generic crest for other cities',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MunicipalityIdentity(
            municipalityId: '12345',
            municipalityName: 'Otra ciudad',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('municipality-crest-generic')), findsOneWidget);
    expect(find.text('Municipalidad de Otra ciudad'), findsOneWidget);
    expect(find.byKey(const Key('municipality-crest-la_plata')), findsNothing);
  });
}
