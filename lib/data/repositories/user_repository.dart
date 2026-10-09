import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.usersCollection);

  /// Obtener un usuario por UID
  Future<UserModel?> getUser(String uid) async {
    final doc = await _col.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Stream en tiempo real del usuario actual
  Stream<UserModel?> watchUser(String uid) {
    return _col.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    });
  }

  /// Crear un nuevo usuario en Firestore
  Future<void> createUser(UserModel user) async {
    await _col.doc(user.uid).set(user.toFirestore());
  }

  /// Actualizar campos del usuario
  Future<void> updateUser(String uid, Map<String, dynamic> fields) async {
    await _col.doc(uid).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Actualizar el FCM token al hacer login
  Future<void> refreshFcmToken(String uid) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _col.doc(uid).update({'fcmToken': token});
      }
    } catch (_) {
      // No es crítico; no interrumpir el login si falla
    }
  }

  /// Eliminar todos los datos del usuario (GDPR + Play Store)
  /// No borra los reportes físicamente — los marca como hidden=true
  Future<void> deleteUserData(String uid) async {
    final batch = _db.batch();

    // Marcar reportes como hidden
    final reportsSnap = await _db
        .collection(AppConstants.reportsCollection)
        .where('userId', isEqualTo: uid)
        .get();
    for (final doc in reportsSnap.docs) {
      batch.update(doc.reference, {'hidden': true});
    }

    // Eliminar documento del usuario
    batch.delete(_col.doc(uid));

    await batch.commit();
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);

final currentUserProfileProvider = StreamProvider.family<UserModel?, String>(
  (ref, uid) => ref.read(userRepositoryProvider).watchUser(uid),
);
