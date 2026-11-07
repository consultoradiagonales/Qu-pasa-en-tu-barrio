import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Reutiliza una carga confirmada sólo si sus bytes son los mismos. Las fotos
/// existentes permanecen inmutables aunque haya fallado el paso posterior.
Future<String> uploadImmutableReportPhoto({
  required Uint8List bytes,
  required Future<Uint8List?> Function() read,
  required Future<void> Function() upload,
  required Future<String> Function() downloadUrl,
}) async {
  if (bytes.isEmpty || bytes.length >= 8 * 1024 * 1024) {
    throw StateError('La foto está vacía o supera el tamaño permitido.');
  }

  Future<Uint8List?> readExisting() async {
    try {
      return await read();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return null;
      rethrow;
    }
  }

  final existing = await readExisting();
  if (existing != null) {
    if (!listEquals(existing, bytes)) {
      throw StateError(
          'Este borrador ya tiene otra foto enviada. Iniciá un nuevo reporte para conservar ambas evidencias.');
    }
    return downloadUrl();
  }

  try {
    await upload();
  } catch (error, stack) {
    // Una respuesta perdida o una carga simultánea puede haber guardado la
    // imagen. Nunca se interpreta cualquier error de red como un éxito.
    try {
      final recovered = await readExisting();
      if (recovered != null && listEquals(recovered, bytes)) {
        return await downloadUrl();
      }
    } catch (_) {
      // Se conserva la causa original de la carga y el borrador local.
    }
    Error.throwWithStackTrace(error, stack);
  }
  return downloadUrl();
}
