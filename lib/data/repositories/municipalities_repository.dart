import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un municipio adherido a ConDi.
class Municipality {
  const Municipality({
    required this.id,
    required this.name,
    required this.province,
  });

  final String id;
  final String name;
  final String province;

  factory Municipality.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return Municipality(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      province: data['province'] as String? ?? '',
    );
  }
}

/// Municipios activos, para que el vecino elija el suyo al registrarse.
final municipalitiesProvider = FutureProvider<List<Municipality>>((ref) async {
  final snap = await FirebaseFirestore.instance
      .collection('municipalities')
      .where('active', isEqualTo: true)
      .get();
  final lista = snap.docs.map(Municipality.fromFirestore).toList();
  lista.sort((a, b) => a.name.compareTo(b.name));
  return lista;
});
