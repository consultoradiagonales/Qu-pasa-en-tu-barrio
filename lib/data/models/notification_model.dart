import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  newReport,
  reportAssigned,
  workerArrived,
  reportResolved,
  officialComment,
  newSupport;

  String get value {
    switch (this) {
      case NotificationType.newReport:
        return 'new_report';
      case NotificationType.reportAssigned:
        return 'report_assigned';
      case NotificationType.workerArrived:
        return 'worker_arrived';
      case NotificationType.reportResolved:
        return 'report_resolved';
      case NotificationType.officialComment:
        return 'official_comment';
      case NotificationType.newSupport:
        return 'new_support';
    }
  }

  static NotificationType fromString(String value) {
    switch (value) {
      case 'new_report':
        return NotificationType.newReport;
      case 'report_assigned':
        return NotificationType.reportAssigned;
      case 'worker_arrived':
        return NotificationType.workerArrived;
      case 'report_resolved':
        return NotificationType.reportResolved;
      case 'official_comment':
        return NotificationType.officialComment;
      case 'new_support':
        return NotificationType.newSupport;
      default:
        return NotificationType.reportAssigned;
    }
  }
}

class NotificationModel {
  final String id;
  final String userId;
  final NotificationType type;
  final String reportId;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.reportId,
    required this.title,
    required this.body,
    this.read = false,
    required this.createdAt,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: NotificationType.fromString(data['type'] ?? ''),
      reportId: data['reportId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      read: data['read'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'type': type.value,
        'reportId': reportId,
        'title': title,
        'body': body,
        'read': read,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  NotificationModel copyWith({bool? read}) {
    return NotificationModel(
      id: id,
      userId: userId,
      type: type,
      reportId: reportId,
      title: title,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}
