/// Identidad opcional de una edición municipal de ConDi.
///
/// La edición general no define ninguna variable y mantiene el selector de
/// municipio. Las ediciones entregadas a un municipio quedan fijadas desde la
/// compilación, evitando que una cuenta municipal opere sobre otro ámbito.
class MunicipalityBuildConfig {
  static const municipalityId =
      String.fromEnvironment('CONDI_MUNICIPALITY_ID');
  static const municipalityName =
      String.fromEnvironment('CONDI_MUNICIPALITY_NAME');
  static const provinceId = String.fromEnvironment('CONDI_PROVINCE_ID');
  static const provinceName =
      String.fromEnvironment('CONDI_PROVINCE_NAME');

  static bool get isLocked =>
      municipalityId.isNotEmpty && municipalityName.isNotEmpty;

  static String get firestoreMunicipalityId => municipalityId.startsWith('georef_')
      ? municipalityId
      : 'georef_$municipalityId';
}
