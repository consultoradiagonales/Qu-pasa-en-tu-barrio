import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_model.dart';
import '../../core/constants/app_constants.dart';

class NotificationsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.notificationsCollection);

  Stream<List<NotificationModel>> watchNotifications(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map(NotificationModel.fromFirestore).toList());
  }

  Stream<int> watchUnreadCount(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markRead(String userId, String notifId) async {
    await _col.doc(notifId).update({'read': true});
  }

  Future<void> markAllRead(String userId) async {
    final snap = await _col
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (_) => NotificationsRepository(),
);

final notificationsProvider =
    StreamProvider.family<List<NotificationModel>, String>((ref, userId) {
  return ref.read(notificationsRepositoryProvider).watchNotifications(userId);
});

final unreadCountProvider = StreamProvider.family<int, String>((ref, userId) {
  return ref.read(notificationsRepositoryProvider).watchUnreadCount(userId);
});
