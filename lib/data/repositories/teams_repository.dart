import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../models/team_model.dart';

List<String> municipalityIdAliases(String municipalityId) {
  final id = municipalityId.trim();
  if (id.isEmpty) return const [];
  if (RegExp(r'^georef_\d+$').hasMatch(id)) {
    return [id, id.substring('georef_'.length)];
  }
  if (RegExp(r'^\d+$').hasMatch(id)) return [id, 'georef_$id'];
  return [id];
}

class TeamsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<TeamModel>> watchActiveTeams(String municipalityId) {
    final aliases = municipalityIdAliases(municipalityId);
    if (aliases.isEmpty) return Stream.value(const []);
    return _db
        .collection(AppConstants.teamsCollection)
        // Los perfiles y reportes históricos alternan entre el id GeoRef y
        // su código numérico. Consultar ambos evita ocultar cuadrillas válidas.
        .where('municipalityId', whereIn: aliases)
        .snapshots()
        .map((snapshot) {
      final teams = snapshot.docs
          .map(TeamModel.fromFirestore)
          .where((team) => team.active)
          .toList();
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
