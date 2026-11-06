import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Sólo compara lo enviado por el vecino; una reasignación o resolución
/// posterior no convierte un reintento en una nueva solicitud.
bool matchesReportSubmission(
    Map<String, dynamic> stored, Map<String, dynamic> proposed) {
  const fields = [
    'userId',
    'municipalityId',
    'municipalityName',
    'provinceId',
    'province',
    'departmentId',
    'department',
    'localityId',
    'locality',
    'settlementId',
    'settlement',
    'title',
    'description',
    'category',
    'aiRequested',
    'aiConsentVersion',
  ];
  for (final field in fields) {
    if (stored[field] != proposed[field]) return false;
  }
  return listEquals(
          stored['photosReport'] as List?, proposed['photosReport'] as List?) &&
      mapEquals(stored['location'] as Map?, proposed['location'] as Map?);
}

/// Diez posiciones protegidas por reglas: cada una se puede reutilizar
/// únicamente después de 24 horas de reloj del servidor. El cliente elige
/// una libre o la más antigua; nunca decide si la cuota está autorizada.
String nextReportQuotaSlot(Map<String, dynamic> slots) {
  String oldest = '0';
  for (var index = 0; index < 10; index++) {
    final slot = '$index';
    final value = slots[slot];
    if (value is! Timestamp) return slot;
    if (value.compareTo(slots[oldest] as Timestamp) < 0) oldest = slot;
  }
  return oldest;
}
