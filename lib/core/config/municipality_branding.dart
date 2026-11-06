import 'municipality_build_config.dart';

/// Identidad visual municipal resuelta por el ámbito operativo de la cuenta.
///
/// El registro es deliberadamente explícito: un municipio desconocido nunca
/// hereda el escudo de otro y conserva una presentación genérica segura.
class MunicipalityBranding {
  const MunicipalityBranding({
    required this.key,
    required this.municipalityId,
    required this.name,
    required this.displayName,
    this.crestAssetPath,
  });

  final String key;
  final String municipalityId;
  final String name;
  final String displayName;
  final String? crestAssetPath;

  bool get hasCrest => crestAssetPath != null;

  static const laPlata = MunicipalityBranding(
    key: 'la_plata',
    municipalityId: '06441',
    name: 'La Plata',
    displayName: 'Municipalidad de La Plata',
    crestAssetPath: 'assets/images/municipalities/la_plata_crest.svg',
  );
  static const buenosAiresProvince = MunicipalityBranding(
    key: 'buenos_aires_province',
    municipalityId: '06',
    name: 'Buenos Aires',
    displayName: 'Provincia de Buenos Aires',
    crestAssetPath: 'assets/images/municipalities/buenos_aires_province.svg',
  );
  static const municipalities = [
    MunicipalityBranding(
        key: 'trenque_lauquen',
        municipalityId: '060826',
        name: 'Trenque Lauquen',
        displayName: 'Municipalidad de Trenque Lauquen',
        crestAssetPath:
            'assets/images/municipalities/trenque_lauquen_official.png'),
    MunicipalityBranding(
        key: 'saladillo',
        municipalityId: '060707',
        name: 'Saladillo',
        displayName: 'Municipalidad de Saladillo',
        crestAssetPath: 'assets/images/municipalities/saladillo_official.png'),
    MunicipalityBranding(
        key: 'escobar',
        municipalityId: '060252',
        name: 'Escobar',
        displayName: 'Municipalidad de Escobar',
        crestAssetPath: 'assets/images/municipalities/escobar_official.png'),
    MunicipalityBranding(
        key: 'rivadavia',
        municipalityId: '060679',
        name: 'Rivadavia',
        displayName: 'Municipalidad de Rivadavia',
        crestAssetPath: 'assets/images/municipalities/rivadavia_official.png'),
  ];

  static MunicipalityBranding resolve({
    String? municipalityId,
    String? municipalityName,
  }) {
    final rawId = municipalityId?.trim().toLowerCase() ?? '';
    final normalizedId =
        rawId.startsWith('georef_') ? rawId.substring('georef_'.length) : rawId;
    final name = municipalityName?.trim() ?? '';
    final normalizedName = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (['06441', '060441', 'la-plata', 'la_plata'].contains(normalizedId) ||
        normalizedName == 'la plata' ||
        normalizedName == 'municipalidad de la plata') {
      return laPlata;
    }
    if (normalizedId == '06' || normalizedName == 'provincia de buenos aires') {
      return buenosAiresProvince;
    }
    for (final identity in municipalities) {
      final censusCode = identity.municipalityId.substring(0, 2) +
          identity.municipalityId.substring(3);
      if (normalizedId == identity.municipalityId ||
          normalizedId == censusCode ||
          normalizedId == identity.key ||
          normalizedId == identity.key.replaceAll('_', '-') ||
          normalizedName == identity.name.toLowerCase() ||
          normalizedName == identity.displayName.toLowerCase()) {
        return identity;
      }
    }

    return MunicipalityBranding(
      key: 'generic',
      municipalityId: normalizedId,
      name: name,
      displayName: name.isEmpty
          ? 'Municipalidad'
          : normalizedName.startsWith('municipalidad') ||
                  normalizedName.startsWith('municipio ')
              ? name
              : 'Municipalidad de $name',
    );
  }

  /// Usa primero la identidad de la cuenta y luego la edición municipal fijada
  /// durante la compilación, cuando existe.
  static MunicipalityBranding current({
    String? municipalityId,
    String? municipalityName,
  }) {
    final hasAccountIdentity = municipalityId?.trim().isNotEmpty == true ||
        municipalityName?.trim().isNotEmpty == true;
    final id = hasAccountIdentity
        ? municipalityId
        : MunicipalityBuildConfig.municipalityId;
    final name = hasAccountIdentity
        ? municipalityName
        : MunicipalityBuildConfig.municipalityName;
    return resolve(municipalityId: id, municipalityName: name);
  }
}
