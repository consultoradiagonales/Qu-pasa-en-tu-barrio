import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../models/team_model.dart';

class TeamsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<TeamModel>> watchActiveTeams(String municipalityId) {
    return _db
        .collection(AppConstants.teamsCollection)
        .where('municipalityId', isEqualTo: municipalityId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final teams = snapshot.docs.map(TeamModel.fromFirestore).toList();
      teams.sort((a, b) => a.name.compareTo(b.name));
      return teams;
    });
  }
}

final teamsRepositoryProvider = Provider<TeamsRepository>((_) => TeamsRepository());

final activeTeamsProvider = StreamProvider.family<List<TeamModel>, String>(
  (ref, municipalityId) =>
      ref.read(teamsRepositoryProvider).watchActiveTeams(municipalityId),
);
