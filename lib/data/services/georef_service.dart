import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/search_text.dart';

class GeoRefPlace {
  const GeoRefPlace({required this.id, required this.name});

  final String id;
  final String name;

  factory GeoRefPlace.fromJson(Map<String, dynamic> json) => GeoRefPlace(
        id: json['id']?.toString() ?? '',
        name: json['nombre']?.toString() ?? '',
      );
}

/// Un municipio con su provincia, tal como se le muestra a la persona.
///
/// Hay muchos con el mismo nombre en distintas provincias (Saladillo en
/// Buenos Aires, Córdoba y San Luis; San Martín en 8 provincias), así que el
/// nombre solo no alcanza para elegir: la etiqueta lleva la provincia.
class MunicipalitySuggestion {
  const MunicipalitySuggestion({
    required this.id,
    required this.name,
    required this.provinceId,
    required this.province,
  });

  final String id;
  final String name;
  final String provinceId;
  final String province;

  /// "Saladillo, Buenos Aires"
  String get label => province.isEmpty ? name : '$name, $province';

  factory MunicipalitySuggestion.fromJson(Map<String, dynamic> json) {
    final province = json['provincia'];
    return MunicipalitySuggestion(
      id: json['id']?.toString() ?? '',
      name: json['nombre']?.toString() ?? '',
      provinceId: province is Map ? province['id']?.toString() ?? '' : '',
      province: province is Map ? province['nombre']?.toString() ?? '' : '',
    );
  }
}

/// Una ciudad o localidad con su provincia.  La provincia forma parte de la
/// etiqueta porque en Argentina hay localidades con el mismo nombre.
class LocalitySuggestion {
  const LocalitySuggestion({
    required this.id,
    required this.name,
    required this.provinceId,
    required this.province,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String provinceId;
  final String province;
  final double? latitude;
  final double? longitude;

  String get label => province.isEmpty ? name : '$name, $province';
  bool get hasCoordinates => latitude != null && longitude != null;

  factory LocalitySuggestion.fromJson(Map<String, dynamic> json) {
    final province = json['provincia'];
    final centroid = json['centroide'];
    return LocalitySuggestion(
      id: json['id']?.toString() ?? '',
      name: json['nombre']?.toString() ?? '',
      provinceId: province is Map ? province['id']?.toString() ?? '' : '',
      province: province is Map ? province['nombre']?.toString() ?? '' : '',
      latitude: centroid is Map ? (centroid['lat'] as num?)?.toDouble() : null,
      longitude: centroid is Map ? (centroid['lon'] as num?)?.toDouble() : null,
    );
  }
}

/// Ordena lo más parecido primero: nombre exacto, luego los que empiezan con
/// lo escrito, luego el resto, y a igualdad por nombre y provincia.
List<MunicipalitySuggestion> rankMunicipalitySuggestions(
  String query,
  List<MunicipalitySuggestion> items,
) {
  final needle = normalizeForSearch(query);
  int rank(MunicipalitySuggestion m) {
    final name = normalizeForSearch(m.name);
    if (name == needle) return 0;
    if (name.startsWith(needle)) return 1;
    return 2;
  }

  return [...items]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.province.compareTo(b.province);
    });
}

/// Ordena ciudades/localidades por coincidencia y, en caso de empate, por
/// provincia. Mantener los homónimos evita que se asigne una ciudad errónea.
List<LocalitySuggestion> rankLocalitySuggestions(
  String query,
  List<LocalitySuggestion> items,
) {
  final needle = normalizeForSearch(query);
  int rank(LocalitySuggestion locality) {
    final name = normalizeForSearch(locality.name);
    if (name == needle) return 0;
    if (name.startsWith(needle)) return 1;
    return 2;
  }

  return [...items]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.province.compareTo(b.province);
    });
}

/// Catálogo oficial de división territorial argentina.
///
/// Se consulta bajo demanda: no se descarga una base nacional enorme en cada
/// teléfono y la información queda actualizada sin publicar una nueva APK.
class GeoRefService {
  GeoRefService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://apis.datos.gob.ar/georef/api';
  final http.Client _client;

  Future<List<GeoRefPlace>> provinces() => _get('provincias', 'provincias');

  Future<List<GeoRefPlace>> departments(String provinceId) =>
      _get('departamentos?provincia=$provinceId', 'departamentos');

  Future<List<GeoRefPlace>> municipalities(String provinceId) =>
      _get('municipios?provincia=$provinceId', 'municipios');

  Future<List<GeoRefPlace>> localities(String provinceId) =>
      _get('localidades?provincia=$provinceId', 'localidades');

  Future<List<GeoRefPlace>> settlements(String provinceId) =>
      _get('asentamientos?provincia=$provinceId', 'asentamientos');

  /// Dónde abrir el mapa para un municipio, o null si no se pudo obtener.
  ///
  /// Acepta el id tal como se guarda en el perfil (`georef_060049`) o el
  /// código a secas. Sirve para abrir el mapa en el lugar del vecino cuando no
  /// hay GPS, sin mantener una tabla de coordenadas dentro de la app.
  ///
  /// El centroide de un partido grande suele caer en pleno campo (el de Azul
  /// queda a 17 km de la ciudad), así que primero se busca la localidad que
  /// se llama igual que el partido y se usa su centro. Si no existe, como en
  /// General Pueyrredón, se usa el centroide y un zoom más abierto.
  Future<({double lat, double lng, double zoom})?> municipalityCenter(
    String municipalityId,
  ) async {
    final id = municipalityId.replaceFirst('georef_', '');
    if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) return null;
    try {
      final municipio = await _firstOf(
        'municipios?id=$id&campos=nombre,centroide&max=1',
        'municipios',
      );
      if (municipio == null) return null;

      final name = municipio['nombre']?.toString() ?? '';
      if (name.isNotEmpty) {
        final localidad = await _firstOf(
          'localidades?municipio=$id&nombre=${Uri.encodeComponent(name)}'
          '&exacto=true&campos=centroide&max=1',
          'localidades',
        );
        final point = _point(localidad?['centroide']);
        if (point != null) return (lat: point.lat, lng: point.lng, zoom: 13.5);
      }

      final point = _point(municipio['centroide']);
      if (point == null) return null;
      return (lat: point.lat, lng: point.lng, zoom: 11.0);
    } catch (_) {
      return null;
    }
  }

  /// Municipios de todo el país cuyo nombre contiene [query], sin importar
  /// tildes ni mayúsculas, con su provincia. Lanza si el servicio no responde,
  /// para que la pantalla pueda avisar en vez de mostrar "sin resultados".
  Future<List<MunicipalitySuggestion>> searchMunicipalities(
    String query,
  ) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final response = await _client
        .get(Uri.parse(
          '$_baseUrl/municipios?nombre=${Uri.encodeQueryComponent(text)}'
          '&campos=id,nombre,provincia.id,provincia.nombre&max=40',
        ))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('No se pudo buscar el municipio.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final found = (payload['municipios'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MunicipalitySuggestion.fromJson)
        .where((m) => m.id.isNotEmpty && m.name.isNotEmpty)
        .toList();
    return rankMunicipalitySuggestions(text, found).take(12).toList();
  }

  /// Busca ciudades/localidades en todo el país. Incluye el centroide solo
  /// para abrir el reporte en la ciudad elegida cuando no hay GPS; nunca
  /// pretende geocodificar una calle a partir de esos datos.
  Future<List<LocalitySuggestion>> searchLocalities(String query) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final response = await _client
        .get(Uri.parse(
          '$_baseUrl/localidades?nombre=${Uri.encodeQueryComponent(text)}'
          '&campos=id,nombre,provincia.id,provincia.nombre,centroide&max=40',
        ))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('No se pudo buscar la ciudad.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final found = (payload['localidades'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LocalitySuggestion.fromJson)
        .where((locality) => locality.id.isNotEmpty && locality.name.isNotEmpty)
        .toList();
    return rankLocalitySuggestions(text, found).take(12).toList();
  }

  /// Municipio al que pertenece una coordenada, o null si GeoRef no responde o
  /// el punto no cae en ningún municipio (mar, límite internacional).
  ///
  /// Quien llama debe tratar null como "no se pudo verificar", nunca como un
  /// error del vecino: no tiene que bloquear un reporte por una falla de red.
  Future<GeoRefPlace?> municipalityAt(double lat, double lng) async {
    try {
      final response = await _client
          .get(Uri.parse(
            '$_baseUrl/ubicacion?lat=$lat&lon=$lng&campos=municipio',
          ))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final ubicacion = payload['ubicacion'] as Map<String, dynamic>?;
      final municipio = ubicacion?['municipio'];
      if (municipio is! Map<String, dynamic>) return null;
      final place = GeoRefPlace.fromJson(municipio);
      return place.id.isEmpty ? null : place;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _firstOf(String path, String key) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/$path'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final list = payload[key] as List<dynamic>? ?? const [];
    if (list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }

  ({double lat, double lng})? _point(Object? centroid) {
    if (centroid is! Map<String, dynamic>) return null;
    final lat = (centroid['lat'] as num?)?.toDouble();
    final lng = (centroid['lon'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  Future<List<GeoRefPlace>> _get(String path, String key) async {
    final separator = path.contains('?') ? '&' : '?';
    final response = await _client.get(
      Uri.parse('$_baseUrl/$path${separator}campos=id,nombre&max=5000'),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo cargar el catálogo territorial.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final values = (payload[key] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GeoRefPlace.fromJson)
        .where((place) => place.id.isNotEmpty && place.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return values;
  }
}
