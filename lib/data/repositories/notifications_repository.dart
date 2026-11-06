import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../models/notification_model.dart';

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.nextCursor,
  });

  final List<NotificationModel> items;
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  bool get hasMore => nextCursor != null;
}

class NotificationsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.notificationsCollection);

  Query<Map<String, dynamic>> _forUser(String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return _col.where('userId', isEqualTo: userId);
  }

  List<NotificationModel> _ordered(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs.map(NotificationModel.fromFirestore).toList();
    // Firestore orders by timestamp. The id tie breaker makes same-millisecond
    // messages deterministic for list rendering and pagination.
    items.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return items;
  }

  Stream<List<NotificationModel>> watchNotifications(String userId) {
    return _forUser(userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => _ordered(snap.docs));
  }

  Future<NotificationPage> fetchNotificationsPage(
    String userId, {
    DocumentSnapshot<Map<String, dynamic>>? after,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }

    Query<Map<String, dynamic>> query =
        _forUser(userId).orderBy('createdAt', descending: true).limit(limit);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.get();
    return NotificationPage(
      items: _ordered(snapshot.docs),
      nextCursor: snapshot.docs.length == limit ? snapshot.docs.last : null,
    );
  }

  Stream<int> watchUnreadCount(String userId) {
    return _forUser(userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markRead(String userId, String notifId) async {
    await _updateOwnedNotification(userId, notifId, const {'read': true});
  }

  Future<void> deleteNotification(String userId, String notifId) async {
    if (notifId.isEmpty) {
      throw ArgumentError.value(notifId, 'notifId', 'must not be empty');
    }
    final ref = _col.doc(notifId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      _verifyOwnership(snapshot, userId, notifId);
      transaction.delete(ref);
    });
  }

  Future<void> _updateOwnedNotification(
    String userId,
    String notifId,
    Map<String, dynamic> changes,
  ) async {
    if (notifId.isEmpty) {
      throw ArgumentError.value(notifId, 'notifId', 'must not be empty');
    }
    final ref = _col.doc(notifId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = _verifyOwnership(snapshot, userId, notifId);
      if (data['read'] != true) transaction.update(ref, changes);
    });
  }

  Map<String, dynamic> _verifyOwnership(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String userId,
    String notifId,
  ) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['userId'] != userId) {
      throw StateError('Notification $notifId is not owned by $userId.');
    }
    return data;
  }

  Future<void> markAllRead(String userId) async {
    final snap = await _forUser(userId).where('read', isEqualTo: false).get();
    for (var start = 0; start < snap.docs.length; start += 500) {
      final batch = _db.batch();
      final end =
          start + 500 < snap.docs.length ? start + 500 : snap.docs.length;
      for (final doc in snap.docs.sublist(start, end)) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    }
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
