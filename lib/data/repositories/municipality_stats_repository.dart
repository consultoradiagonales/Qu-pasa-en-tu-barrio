import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/municipality_stats.dart';

final municipalityStatsProvider =
    StreamProvider.family<MunicipalityStats?, String>((ref, municipalityId) {
  return FirebaseFirestore.instance
      .collection('municipalityStats')
      .doc(municipalityId)
      .snapshots()
      .map((doc) => doc.exists ? MunicipalityStats.fromFirestore(doc) : null);
});
