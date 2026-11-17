/// Browser errors vary in their wording; DOMException names are standardized.
String webCameraErrorMessage(Object error) {
  final description = error.toString();
  if (description.contains('NotAllowedError') ||
      description.contains('PermissionDeniedError') ||
      description.contains('SecurityError')) {
    return 'No se habilitó la cámara. Permití su uso desde el candado o los '
        'permisos del navegador y volvé a intentar.';
  }
  if (description.contains('NotFoundError') ||
      description.contains('DevicesNotFoundError')) {
    return 'No encontramos una cámara. Conectá una webcam o abrí ConDi en '
        'un celular con cámara.';
  }
  if (description.contains('NotReadableError') ||
      description.contains('TrackStartError') ||
      description.contains('AbortError')) {
    return 'No se pudo iniciar la cámara. Cerrá las otras aplicaciones que '
        'la estén usando y volvé a intentar.';
  }
  return 'No se pudo abrir la cámara. Revisá sus permisos o probá con '
      'Safari o Chrome actualizado.';
}
