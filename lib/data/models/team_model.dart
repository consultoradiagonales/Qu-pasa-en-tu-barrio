import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String name;
  final String municipalityId;
  final List<String> categories;
  final bool active;

  const TeamModel({
    required this.id,
    required this.name,
    required this.municipalityId,
    required this.categories,
    required this.active,
  });

  factory TeamModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TeamModel(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      municipalityId: data['municipalityId'] as String? ?? '',
      categories: List<String>.from(data['categories'] ?? const []),
      active: data['active'] == true,
    );
  }
}
