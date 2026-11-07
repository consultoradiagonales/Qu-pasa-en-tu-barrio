import 'package:firebase_core/firebase_core.dart';

/// Traduce cualquier excepción a un mensaje que se le pueda mostrar a un
/// vecino. Nunca devuelve códigos, nombres de servicios ni stack traces: un
/// "[cloud_firestore/permission-denied] Missing or insufficient permissions"
/// en pantalla no le sirve a nadie y expone el funcionamiento interno.
String mensajeDeError(Object error) {
  if (error is StateError) return error.message.toString();
  final texto = error is FirebaseException
      ? '${error.plugin}/${error.code} ${error.message ?? ''}'.toLowerCase()
      : error.toString().toLowerCase();

  bool tiene(String aguja) => texto.contains(aguja);

  if (tiene('permission-denied') || tiene('unauthenticated')) {
    return 'No tenés permiso para ver esto. '
        'Si creés que es un error, escribinos a info.consultoradiagonales@gmail.com.';
  }
  if (tiene('unavailable') ||
      tiene('network') ||
      tiene('socket') ||
      tiene('timeout') ||
      tiene('deadline-exceeded')) {
    return 'Sin conexión. Revisá tu internet e intentá de nuevo.';
  }
  if (tiene('not-found')) {
    return 'No encontramos lo que buscabas.';
  }
  if (tiene('resource-exhausted') || tiene('quota')) {
    return 'El servicio está saturado. Probá en unos minutos.';
  }
  if (tiene('cancelled')) {
    return 'La operación se canceló.';
  }
  if (tiene('unauthorized') || tiene('storage/')) {
    return 'No pudimos subir la imagen. Intentá de nuevo.';
  }
  return 'Algo salió mal. Intentá de nuevo en unos minutos.';
}
