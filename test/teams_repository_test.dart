import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/teams_repository.dart';

void main() {
  test('resuelve ambas variantes del identificador GeoRef', () {
    expect(municipalityIdAliases('060707'), ['060707', 'georef_060707']);
    expect(municipalityIdAliases('georef_060707'),
        ['georef_060707', '060707']);
  });

  test('preserva identificadores no numéricos y rechaza vacíos', () {
    expect(municipalityIdAliases('la-plata'), ['la-plata']);
    expect(municipalityIdAliases('  '), isEmpty);
  });
}
