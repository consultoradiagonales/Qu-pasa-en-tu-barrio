import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id;
  final String reportId;
  final String userId;
  final String displayName;
  final String text;
  final bool isOfficialResponse; // true si es respuesta del coordinador
  final bool hidden;
  final int flaggedCount;
  final DateTime createdAt;

  const CommentModel({
    required this.id,
    required this.reportId,
    required this.userId,
    required this.displayName,
    required this.text,
    this.isOfficialResponse = false,
    this.hidden = false,
    this.flaggedCount = 0,
    required this.createdAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommentModel(
      id: doc.id,
      reportId: data['reportId'] ?? '',
      userId: data['userId'] ?? '',
      displayName: data['displayName'] ?? '',
      text: data['text'] ?? '',
      isOfficialResponse: data['isOfficialResponse'] ?? false,
      hidden: data['hidden'] ?? false,
      flaggedCount: data['flaggedCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'reportId': reportId,
        'userId': userId,
        'displayName': displayName,
        'text': text,
        'isOfficialResponse': isOfficialResponse,
        'hidden': hidden,
        'flaggedCount': flaggedCount,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
