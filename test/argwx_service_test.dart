import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:que_pasa_en_tu_barrio/data/services/argwx_municipalities.dart';
import 'package:que_pasa_en_tu_barrio/data/services/argwx_service.dart';
import 'package:que_pasa_en_tu_barrio/features/weather/screens/weather_screen.dart';

final _now = DateTime.utc(2026, 11, 6, 13);

Map<String, dynamic> _forecastJson({String generatedAt = '2026-11-06T12:12:43Z'}) => {
      'generated_at': generatedAt,
      'data_mode': 'live',
      'models': List.filled(9, 'M'),
      'windows': {
        '24': {
          'label': 'Próximas 24 h',
          'valid_from': '2026-11-06T12:00:00Z',
          'valid_to': '2026-11-07T12:00:00Z',
          'municipios': [
            {
              'id': 'la-plata',
              'alert_level': 'YELLOW',
              'hazard': 'tormenta',
              'confidence_label': 'Oficial SMN',
              'consensus': '8/9',
              'lluvia_mm': 13.5,
              'prob_lluvia': {
                '10': {'probabilidad': 83.8, 'confiable': true},
              },
              'drivers': ['Alerta amarilla del SMN por tormentas.'],
            },
            {'id': 'escobar', 'alert_level': 'GREEN', 'confidence_label': 'Alta'},
          ],
        },
        '48': {'label': 'De 24 a 48 h', 'municipios': []},
      },
    };

ArgwxService _service(Map<String, Map<String, dynamic>> files, {List<String>? log}) {
  final client = MockClient((request) async {
    log?.add(request.url.path);
    final body = files[request.url.path.split('/argwx/').last];
    if (body == null) return http.Response('no', 404);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  });
  return ArgwxService(client: client, now: () => _now);
}

void main() {
  test('la tabla cubre los 135 partidos y los cinco municipios iniciales', () {
    expect(argwxIdByGeorefCode.length, 135);
    expect(argwxIdByGeorefCode.values.toSet().length, 135);
    expect(ArgwxService.argwxIdFor('georef_060441'), 'la-plata');
    expect(ArgwxService.argwxIdFor('060826'), 'trenque-lauquen');
    expect(ArgwxService.argwxIdFor('georef_06707'), 'saladillo');
    expect(ArgwxService.argwxIdFor('georef_060252'), 'escobar');
    expect(ArgwxService.argwxIdFor('georef_060679'), 'rivadavia');
  });

  test('fuera de Buenos Aires no hay cobertura', () {
    expect(ArgwxService.argwxIdFor('georef_140014'), isNull); // Córdoba
    expect(ArgwxService.argwxIdFor(''), isNull);
    expect(ArgwxService.argwxIdFor(null), isNull);
  });

  test('lee el pronóstico del partido y distingue la alerta oficial', () async {
    final f = await _service({'data/alertas_pba.json': _forecastJson()})
        .forecast('la-plata');
    expect(f.isLive, isTrue);
    expect(f.isStale, isFalse);
    expect(f.modelCount, 9);
    final m = f.windows.firstWhere((w) => w.hours == 24).municipality!;
    expect(m.level, ArgwxLevel.yellow);
    expect(m.isOfficialSmn, isTrue);
    expect(m.rainOver10mmPercent, closeTo(83.8, 0.01));
    // Sin dato en 48 h: queda null, nunca "verde".
    expect(f.windows.firstWhere((w) => w.hours == 48).municipality, isNull);
  });

  test('un dato viejo queda marcado como vencido', () async {
    final f = await _service({
      'data/alertas_pba.json': _forecastJson(generatedAt: '2026-11-06T06:00:00Z'),
    }).forecast('la-plata');
    expect(f.isStale, isTrue);
  });

  test('la respuesta se reutiliza unos minutos', () async {
    final log = <String>[];
    final s = _service({'data/alertas_pba.json': _forecastJson()}, log: log);
    await s.forecast('la-plata');
    await s.forecast('escobar');
    expect(log.length, 1);
  });

  test('si el motor no responde avisa que no hay datos', () async {
    expect(_service({}).forecast('la-plata'), throwsA(isA<ArgwxUnavailable>()));
  });

  test('crecidas: sólo cursos con aviso que afectan al partido', () async {
    final floods = await _service({
      'data/crecidas.json': {
        'generated_at': '2026-11-06T12:00:00Z',
        'cursos': [
          {
            'nombre': 'Arroyo El Gato',
            'tipo': 'arroyo',
            'nivel': 'ORANGE',
            'caudal_confirmado': false,
            'partidos_afectados': ['la-plata'],
            'motivos': ['Lluvia prevista en la cuenca'],
          },
          {'nombre': 'Río Areco', 'nivel': 'YELLOW', 'partidos_afectados': ['zarate']},
          {'nombre': 'Arroyo Verde', 'nivel': 'GREEN', 'partidos_afectados': ['la-plata']},
        ],
      },
    }).floods('la-plata');
    expect(floods.courses.map((c) => c.name), ['Arroyo El Gato']);
    expect(floods.courses.single.level, ArgwxLevel.orange);
  });

  testWidgets('la pantalla muestra la fuente oficial y no descarga crecidas sola',
      (tester) async {
    final log = <String>[];
    final service = _service({'data/alertas_pba.json': _forecastJson()}, log: log);
    await tester.pumpWidget(ProviderScope(
      overrides: [argwxServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        home: Scaffold(
          body: WeatherBody(argwxId: 'la-plata', municipalityName: 'La Plata'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Alerta amarilla por tormenta'), findsOneWidget);
    expect(find.text('Fuente: alerta oficial del SMN'), findsOneWidget);
    expect(log.where((p) => p.endsWith('crecidas.json')), isEmpty);

    await tester.tap(find.text('48 h'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin dato para este período'), findsOneWidget);
  });
}
