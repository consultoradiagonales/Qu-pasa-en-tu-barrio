import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../services/auth_service.dart';
import 'user_repository.dart';

/// Alcance de un envío: cuánta gente lo recibe y cuánta con push en el celular.
/// Solo son números; nunca se leen ni se muestran tokens ni datos personales.
class PushReach {
  const PushReach({required this.total, required this.withPush});

  final int total;
  final int withPush;

  int get inAppOnly => total - withPush < 0 ? 0 : total - withPush;
}

abstract class PushReachRepository {
  /// [municipalityId] null = todos los usuarios (solo administrador).
  Future<PushReach> reach({String? municipalityId});
}

class FirestorePushReachRepository implements PushReachRepository {
  FirestorePushReachRepository([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _base(String? municipalityId) {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.usersCollection)
        .where('disabled', isEqualTo: false);
    if (municipalityId != null) {
      q = q.where('municipalityId', isEqualTo: municipalityId);
    }
    return q;
  }

  Future<int> _count(Query<Map<String, dynamic>> q) async {
    final snap = await q.count().get();
    return snap.count ?? 0;
  }

  @override
  Future<PushReach> reach({String? municipalityId}) async {
    final total = await _count(_base(municipalityId));
    try {
      // Requiere un índice compuesto (disabled, [municipalityId,] fcmToken).
      // No se crea ninguno: si falta, se usa el plan alternativo de abajo.
      final withPush = await _count(
          _base(municipalityId).where('fcmToken', isGreaterThan: ''));
      return PushReach(total: total, withPush: withPush);
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
    }
    if (municipalityId == null) {
      // Sin índice compuesto: solo filtro por token (índice simple). Puede
      // incluir cuentas deshabilitadas, así que se acota al total.
      final withPush = await _count(_db
          .collection(AppConstants.usersCollection)
          .where('fcmToken', isGreaterThan: ''));
      return PushReach(
          total: total, withPush: withPush > total ? total : withPush);
    }
    // Coordinador: consulta de igualdad (índice simple) y conteo local de un
    // solo campo; el límite evita descargas enormes.
    final docs = await _db
        .collection(AppConstants.usersCollection)
        .where('municipalityId', isEqualTo: municipalityId)
        .limit(5000)
        .get();
    var withPush = 0;
    for (final d in docs.docs) {
      final data = d.data();
      final token = data['fcmToken'];
      if (data['disabled'] != true && token is String && token.isNotEmpty) {
        withPush++;
      }
    }
    return PushReach(total: total, withPush: withPush);
  }
}

final pushReachRepositoryProvider =
    Provider<PushReachRepository>((_) => FirestorePushReachRepository());

/// Municipio del usuario actual (vacío si aún no se conoce).
final reachMunicipalityIdProvider = Provider<String>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return '';
  return ref.watch(currentUserProfileProvider(uid)).valueOrNull?.municipalityId ??
      '';
});

/// Clave: municipalityId, o null para "todos".
final pushReachProvider = FutureProvider.autoDispose
    .family<PushReach, String?>((ref, municipalityId) {
  return ref
      .read(pushReachRepositoryProvider)
      .reach(municipalityId: municipalityId);
});
