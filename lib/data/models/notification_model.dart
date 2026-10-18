import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  newReport,
  reportAssigned,
  workerArrived,
  reportResolved,
  reportProgress,
  reportRejected,
  officialComment,
  newSupport,
  weatherAlert,
  municipalityMessage;

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
      case NotificationType.reportProgress:
        return 'report_progress';
      case NotificationType.reportRejected:
        return 'report_rejected';
      case NotificationType.officialComment:
        return 'official_comment';
      case NotificationType.newSupport:
        return 'new_support';
      case NotificationType.weatherAlert:
        return 'weather_alert';
      case NotificationType.municipalityMessage:
        return 'municipality_message';
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
      case 'report_progress':
        return NotificationType.reportProgress;
      case 'report_rejected':
        return NotificationType.reportRejected;
      case 'official_comment':
        return NotificationType.officialComment;
      case 'new_support':
        return NotificationType.newSupport;
      case 'weather_alert':
        return NotificationType.weatherAlert;
      case 'municipality_message':
        return NotificationType.municipalityMessage;
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
  final String? imageUrl;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.reportId,
    required this.title,
    required this.body,
    this.imageUrl,
    this.read = false,
    required this.createdAt,
  });

  bool get hasReport => reportId.isNotEmpty;

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: NotificationType.fromString(data['type'] ?? ''),
      reportId: data['reportId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      imageUrl: data['imageUrl'] as String?,
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
        'imageUrl': imageUrl,
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
      imageUrl: imageUrl,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}
