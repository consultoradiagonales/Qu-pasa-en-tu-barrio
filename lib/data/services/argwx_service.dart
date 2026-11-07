import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'argwx_municipalities.dart';

/// Lectura del motor meteorológico ARGWX (carpeta `MOTOR METEOROLOGICO`).
///
/// El motor se actualiza cada hora y publica JSON estáticos. La app sólo los
/// consulta cuando la persona abre "Clima y prevención": nunca al iniciar,
/// nunca en segundo plano y nunca genera notificaciones.
///
/// Regla de lectura: un dato ausente o vencido no significa "sin riesgo".
class ArgwxService {
  ArgwxService({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  static const baseUrl =
      'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx';
  static const dashboardUrl = '$baseUrl/';

  /// El motor corre cada hora; pasado este margen se avisa que el dato es viejo.
  static const staleAfter = Duration(hours: 3);
  static const _cacheFor = Duration(minutes: 10);
  static const _timeout = Duration(seconds: 20);

  final http.Client _client;
  final DateTime Function() _now;

  ({DateTime at, Map<String, dynamic> json})? _forecastCache;
  ({DateTime at, Map<String, dynamic> json})? _floodsCache;

  /// Identificador ARGWX del municipio guardado en el perfil
  /// (`georef_060441` → `la-plata`), o null si no está cubierto.
  static String? argwxIdFor(String? municipalityId) {
    if (municipalityId == null) return null;
    var code = municipalityId.trim().replaceFirst('georef_', '');
    // Código de departamento (06441) → código de municipio (060441).
    if (RegExp(r'^06\d{3}$').hasMatch(code)) code = '060${code.substring(2)}';
    return argwxIdByGeorefCode[code];
  }

  Future<ArgwxForecast> forecast(String argwxId) async {
    final json = await _load('data/alertas_pba.json', isFloods: false);
    return ArgwxForecast.fromJson(json, argwxId, now: _now());
  }

  /// Cursos de agua con aviso que afectan al partido. El archivo completo
  /// pesa varios MB, así que sólo se pide cuando la persona lo solicita.
  Future<ArgwxFloods> floods(String argwxId) async {
    final json = await _load('data/crecidas.json', isFloods: true);
    return ArgwxFloods.fromJson(json, argwxId, now: _now());
  }

  Future<Map<String, dynamic>> _load(String path,
      {required bool isFloods}) async {
    final cached = isFloods ? _floodsCache : _forecastCache;
    if (cached != null && _now().difference(cached.at) < _cacheFor) {
      return cached.json;
    }
    final response =
        await _client.get(Uri.parse('$baseUrl/$path')).timeout(_timeout);
    if (response.statusCode != 200) {
      throw const ArgwxUnavailable();
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) throw const ArgwxUnavailable();
    final entry = (at: _now(), json: decoded);
    if (isFloods) {
      _floodsCache = entry;
    } else {
      _forecastCache = entry;
    }
    return decoded;
  }
}

class ArgwxUnavailable implements Exception {
  const ArgwxUnavailable();
  @override
  String toString() => 'Datos meteorológicos no disponibles por el momento.';
}

/// Nivel de aviso con los colores y textos del motor.
enum ArgwxLevel {
  green('Verde', 'Sin fenómenos significativos', 0xFF2E9D4F),
  yellow('Amarilla', 'Posibles inconvenientes puntuales', 0xFFF2C200),
  orange('Naranja', 'Fenómenos potencialmente peligrosos', 0xFFF07C00),
  red('Roja', 'Fenómenos severos', 0xFFD62828),
  purple('Púrpura', 'Evento extremo', 0xFF7B2CBF),
  unknown('Sin dato', 'No hay información para este período', 0xFF6B7280);

  const ArgwxLevel(this.label, this.meaning, this.color);
  final String label;
  final String meaning;
  final int color;

  static ArgwxLevel parse(Object? value) => switch (value) {
        'GREEN' => green,
        'YELLOW' => yellow,
        'ORANGE' => orange,
        'RED' => red,
        'PURPLE' => purple,
        _ => unknown,
      };
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

double? _num(Object? value) => value is num ? value.toDouble() : null;

class ArgwxForecast {
  const ArgwxForecast({
    required this.generatedAt,
    required this.isLive,
    required this.isStale,
    required this.modelCount,
    required this.windows,
  });

  final DateTime? generatedAt;

  /// false cuando el motor corre en modo demostración (datos simulados).
  final bool isLive;
  final bool isStale;
  final int modelCount;
  final List<ArgwxWindow> windows;

  factory ArgwxForecast.fromJson(
    Map<String, dynamic> json,
    String argwxId, {
    required DateTime now,
  }) {
    final generatedAt = _date(json['generated_at']);
    final rawWindows = json['windows'];
    final windows = <ArgwxWindow>[];
    if (rawWindows is Map) {
      for (final key in const ['24', '48', '72']) {
        final w = rawWindows[key];
        if (w is! Map) continue;
        final municipios = w['municipios'];
        Map? match;
        if (municipios is List) {
          for (final m in municipios) {
            if (m is Map && m['id'] == argwxId) {
              match = m;
              break;
            }
          }
        }
        windows.add(ArgwxWindow(
          hours: int.parse(key),
          label: w['label']?.toString() ?? 'Próximas $key h',
          validFrom: _date(w['valid_from']),
          validTo: _date(w['valid_to']),
          municipality:
              match == null ? null : ArgwxMunicipalForecast.fromJson(match),
        ));
      }
    }
    final models = json['models'];
    return ArgwxForecast(
      generatedAt: generatedAt,
      isLive: json['data_mode'] == 'live',
      isStale: generatedAt == null ||
          now.toUtc().difference(generatedAt) > ArgwxService.staleAfter,
      modelCount: models is List ? models.length : 0,
      windows: windows,
    );
  }
}

class ArgwxWindow {
  const ArgwxWindow({
    required this.hours,
    required this.label,
    required this.validFrom,
    required this.validTo,
    required this.municipality,
  });

  final int hours;
  final String label;
  final DateTime? validFrom;
  final DateTime? validTo;

  /// null si el motor no trajo dato para el partido en esta ventana.
  final ArgwxMunicipalForecast? municipality;
}

class ArgwxMunicipalForecast {
  const ArgwxMunicipalForecast({
    required this.level,
    required this.hazard,
    required this.isOfficialSmn,
    required this.confidenceLabel,
    required this.consensus,
    required this.rainMm,
    required this.rainOver10mmPercent,
    required this.drivers,
  });

  final ArgwxLevel level;
  final String? hazard;

  /// true cuando el nivel proviene de una alerta oficial vigente del SMN.
  final bool isOfficialSmn;
  final String confidenceLabel;
  final String? consensus;
  final double? rainMm;

  /// Probabilidad calibrada de superar 10 mm, sólo si el motor la considera
  /// confiable (muestra suficiente).
  final double? rainOver10mmPercent;
  final List<String> drivers;

  factory ArgwxMunicipalForecast.fromJson(Map json) {
    final confidence = json['confidence_label']?.toString() ?? '';
    double? prob10;
    final probs = json['prob_lluvia'];
    if (probs is Map && probs['10'] is Map) {
      final p = probs['10'] as Map;
      if (p['confiable'] == true) prob10 = _num(p['probabilidad']);
    }
    final drivers = json['drivers'];
    return ArgwxMunicipalForecast(
      level: ArgwxLevel.parse(json['alert_level']),
      hazard: json['hazard']?.toString(),
      isOfficialSmn: confidence == 'Oficial SMN',
      confidenceLabel: confidence,
      consensus: json['consensus']?.toString(),
      rainMm: _num(json['lluvia_mm']),
      rainOver10mmPercent: prob10,
      drivers: drivers is List
          ? drivers.map((d) => d.toString()).toList()
          : const [],
    );
  }
}

class ArgwxFloods {
  const ArgwxFloods({
    required this.generatedAt,
    required this.isStale,
    required this.courses,
  });

  final DateTime? generatedAt;
  final bool isStale;

  /// Sólo cursos con aviso (amarillo o superior) que afectan al partido.
  final List<ArgwxWaterCourse> courses;

  factory ArgwxFloods.fromJson(
    Map<String, dynamic> json,
    String argwxId, {
    required DateTime now,
  }) {
    final generatedAt = _date(json['generated_at']);
    final courses = <ArgwxWaterCourse>[];
    final raw = json['cursos'];
    if (raw is List) {
      for (final c in raw) {
        if (c is! Map) continue;
        final level = ArgwxLevel.parse(c['nivel']);
        if (level == ArgwxLevel.green || level == ArgwxLevel.unknown) continue;
        final partidos = c['partidos_afectados'];
        if (partidos is! List || !partidos.contains(argwxId)) continue;
        final reasons = c['motivos'];
        courses.add(ArgwxWaterCourse(
          name: c['nombre']?.toString() ?? 'Curso sin nombre',
          type: c['tipo']?.toString() ?? '',
          level: level,
          flowConfirmed: c['caudal_confirmado'] == true,
          reasons: reasons is List
              ? reasons.map((r) => r.toString()).toList()
              : const [],
        ));
      }
    }
    courses.sort((a, b) => b.level.index.compareTo(a.level.index));
    return ArgwxFloods(
      generatedAt: generatedAt,
      isStale: generatedAt == null ||
          now.toUtc().difference(generatedAt) > ArgwxService.staleAfter,
      courses: courses,
    );
  }
}

class ArgwxWaterCourse {
  const ArgwxWaterCourse({
    required this.name,
    required this.type,
    required this.level,
    required this.flowConfirmed,
    required this.reasons,
  });

  final String name;
  final String type;
  final ArgwxLevel level;

  /// true cuando el aviso se apoya en una medición de caudal y no sólo en
  /// modelos de lluvia.
  final bool flowConfirmed;
  final List<String> reasons;
}

final argwxServiceProvider = Provider<ArgwxService>((ref) => ArgwxService());

final argwxForecastProvider =
    FutureProvider.autoDispose.family<ArgwxForecast, String>(
  (ref, argwxId) => ref.watch(argwxServiceProvider).forecast(argwxId),
);
