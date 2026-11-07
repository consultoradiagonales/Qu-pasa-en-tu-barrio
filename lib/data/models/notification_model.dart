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
  // Body is the complete persisted message. Presentation layers may make a
  // preview, but must use this value for the conversation/detail view.
  final String body;
  final String? actionUrl;
  final String? imageUrl;
  final String? threadId;
  final String? parentNotificationId;
  final String? municipalityName;
  final String? province;
  final List<String> affectedZones;
  final String? affectedArea;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.reportId,
    required this.title,
    required this.body,
    this.actionUrl,
    this.imageUrl,
    this.threadId,
    this.parentNotificationId,
    this.municipalityName,
    this.province,
    this.affectedZones = const [],
    this.affectedArea,
    this.read = false,
    required this.createdAt,
  });

  bool get hasReport => reportId.isNotEmpty;
  String get conversationId => threadId ?? reportId;

  static String _stringValue(dynamic value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _optionalString(dynamic value) {
    final parsed = _stringValue(value);
    return parsed.isEmpty ? null : parsed;
  }

  static List<String> _stringList(dynamic value) {
    final values = value is Iterable ? value : const [];
    final seen = <String>{};
    return values
        .map(_stringValue)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item.toLowerCase()))
        .toList(growable: false);
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return NotificationModel(
      id: doc.id,
      userId: _stringValue(data['userId']),
      type: NotificationType.fromString(_stringValue(data['type'])),
      reportId: _stringValue(data['reportId']),
      title: _stringValue(data['title']),
      body: _stringValue(data['body']),
      actionUrl: _optionalString(data['actionUrl']),
      imageUrl: _optionalString(data['imageUrl']),
      threadId: _optionalString(data['threadId']),
      parentNotificationId: _optionalString(data['parentNotificationId']),
      municipalityName: _optionalString(data['municipalityName']),
      province: _optionalString(data['province']),
      affectedZones: _stringList(data['affectedZones']),
      affectedArea: _optionalString(data['affectedArea']),
      read: data['read'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'type': type.value,
        'reportId': reportId,
        'title': title,
        'body': body,
        if (actionUrl != null) 'actionUrl': actionUrl,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (threadId != null) 'threadId': threadId,
        if (parentNotificationId != null)
          'parentNotificationId': parentNotificationId,
        if (municipalityName != null) 'municipalityName': municipalityName,
        if (province != null) 'province': province,
        if (affectedZones.isNotEmpty) 'affectedZones': affectedZones,
        if (affectedArea != null) 'affectedArea': affectedArea,
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
      actionUrl: actionUrl,
      imageUrl: imageUrl,
      threadId: threadId,
      parentNotificationId: parentNotificationId,
      municipalityName: municipalityName,
      province: province,
      affectedZones: affectedZones,
      affectedArea: affectedArea,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}
