import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/core/utils/search_text.dart';
import 'package:que_pasa_en_tu_barrio/core/widgets/municipality_autocomplete.dart';
import 'package:que_pasa_en_tu_barrio/data/services/georef_service.dart';

MunicipalitySuggestion _m(String id, String name, String province) =>
    MunicipalitySuggestion(
      id: id,
      name: name,
      provinceId: 'p$id',
      province: province,
    );

void main() {
  group('normalizeForSearch', () {
    test('ignora tildes, mayúsculas y espacios de los bordes', () {
      expect(normalizeForSearch('  Córdoba '), 'cordoba');
      expect(normalizeForSearch('General Pueyrredón'), 'general pueyrredon');
      expect(normalizeForSearch('Ñandú'), 'nandu');
    });
  });

  group('MunicipalitySuggestion', () {
    test('la etiqueta lleva la provincia para distinguir homónimos', () {
      expect(_m('1', 'Saladillo', 'Buenos Aires').label,
          'Saladillo, Buenos Aires');
      expect(_m('2', 'Saladillo', 'San Luis').label, 'Saladillo, San Luis');
    });

    test('se arma desde la respuesta de GeoRef', () {
      final m = MunicipalitySuggestion.fromJson({
        'id': '060707',
        'nombre': 'Saladillo',
        'provincia': {'id': '06', 'nombre': 'Buenos Aires'},
      });
      expect(m.id, '060707');
      expect(m.provinceId, '06');
      expect(m.label, 'Saladillo, Buenos Aires');
    });

    test('sin provincia no deja una coma colgando', () {
      expect(_m('1', 'Azul', '').label, 'Azul');
    });
  });

  group('rankMunicipalitySuggestions', () {
    final items = [
      _m('1', 'Rosario del Saladillo', 'Córdoba'),
      _m('2', 'Saladillo', 'San Luis'),
      _m('3', 'Saladillo', 'Buenos Aires'),
    ];

    test('lo exacto y lo que empieza igual va antes que lo que solo contiene',
        () {
      final r = rankMunicipalitySuggestions('saladillo', items);
      expect(r.first.name, 'Saladillo');
      expect(r.last.name, 'Rosario del Saladillo');
    });

    test('a igual nombre ordena por provincia', () {
      final r = rankMunicipalitySuggestions('saladillo', items);
      expect(
        r.where((m) => m.name == 'Saladillo').map((m) => m.province),
        ['Buenos Aires', 'San Luis'],
      );
    });

    test('ignora tildes al ordenar', () {
      final r = rankMunicipalitySuggestions('cordoba', [
        _m('1', 'Villa Córdoba', 'X'),
        _m('2', 'Córdoba', 'Córdoba'),
      ]);
      expect(r.first.name, 'Córdoba');
    });
  });

  group('MunicipalityAutocomplete', () {
    Future<void> montar(
      WidgetTester tester, {
      required MunicipalitySearch search,
      required ValueChanged<MunicipalitySuggestion?> onSelected,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MunicipalityAutocomplete(search: search, onSelected: onSelected),
        ),
      ));
    }

    testWidgets('sugiere los homónimos con su provincia y devuelve el elegido',
        (tester) async {
      MunicipalitySuggestion? elegido;
      await montar(
        tester,
        search: (q) async => [
          _m('1', 'Saladillo', 'Buenos Aires'),
          _m('2', 'Saladillo', 'San Luis'),
        ],
        onSelected: (m) => elegido = m,
      );

      await tester.enterText(
          find.byKey(const Key('municipality-input')), 'salad');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Saladillo, Buenos Aires'), findsOneWidget);
      expect(find.text('Saladillo, San Luis'), findsOneWidget);

      await tester.tap(find.text('Saladillo, San Luis'));
      await tester.pumpAndSettle();
      expect(elegido?.id, '2');
      expect(find.text('Elegiste Saladillo, San Luis'), findsOneWidget);
    });

    testWidgets('si se edita el texto, la elección anterior deja de valer',
        (tester) async {
      final llamadas = <MunicipalitySuggestion?>[];
      await montar(
        tester,
        search: (q) async => [_m('1', 'Azul', 'Buenos Aires')],
        onSelected: llamadas.add,
      );
      await tester.enterText(
          find.byKey(const Key('municipality-input')), 'azu');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Azul, Buenos Aires'));
      await tester.pumpAndSettle();
      expect(llamadas.last?.id, '1');

      await tester.enterText(
          find.byKey(const Key('municipality-input')), 'Azul, Buenos Aire');
      await tester.pumpAndSettle();
      expect(llamadas.last, isNull);
    });

    testWidgets('avisa cuando no hay resultados', (tester) async {
      await montar(
        tester,
        search: (q) async => const [],
        onSelected: (_) {},
      );
      await tester.enterText(
          find.byKey(const Key('municipality-input')), 'zzzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('No encontramos ese municipio'),
          findsOneWidget);
    });

    testWidgets('avisa cuando falla la búsqueda en vez de decir sin resultados',
        (tester) async {
      await montar(
        tester,
        search: (q) async => throw Exception('sin red'),
        onSelected: (_) {},
      );
      await tester.enterText(
          find.byKey(const Key('municipality-input')), 'azul');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos buscar ahora'), findsOneWidget);
      expect(find.textContaining('No encontramos ese municipio'), findsNothing);
    });

    testWidgets('con una sola letra no busca', (tester) async {
      var busquedas = 0;
      await montar(
        tester,
        search: (q) async {
          busquedas++;
          return const [];
        },
        onSelected: (_) {},
      );
      await tester.enterText(find.byKey(const Key('municipality-input')), 'a');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(busquedas, 0);
    });
  });
}
