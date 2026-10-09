import 'package:cloud_firestore/cloud_firestore.dart';

/// Roles posibles en la app
enum UserRole {
  citizen,
  fieldWorker,
  coordinator,
  moderator,
  admin;

  String get value {
    switch (this) {
      case UserRole.citizen:
        return 'citizen';
      case UserRole.fieldWorker:
        return 'field_worker';
      case UserRole.coordinator:
        return 'coordinator';
      case UserRole.moderator:
        return 'moderator';
      case UserRole.admin:
        return 'admin';
    }
  }

  static UserRole fromString(String value) {
    switch (value) {
      case 'field_worker':
        return UserRole.fieldWorker;
      case 'coordinator':
        return UserRole.coordinator;
      case 'moderator':
        return UserRole.moderator;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.citizen;
    }
  }
}

class UserModel {
  final String uid;
  final String displayName;  // "Usuario #XXXX" — visible en el mapa
  final String realName;     // nombre real — solo visible para admin/coordinador
  final String email;
  final String? photoURL;
  final UserRole role;
  final String? teamId;       // solo para field_worker
  final String municipalityId;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime? lastReportAt;
  final int reportsCount;
  final bool disabled;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.realName,
    required this.email,
    this.photoURL,
    required this.role,
    this.teamId,
    required this.municipalityId,
    this.fcmToken,
    required this.createdAt,
    this.lastReportAt,
    this.reportsCount = 0,
    this.disabled = false,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] ?? '',
      realName: data['realName'] ?? '',
      email: data['email'] ?? '',
      photoURL: data['photoURL'],
      role: UserRole.fromString(data['role'] ?? 'citizen'),
      teamId: data['teamId'],
      municipalityId: data['municipalityId'] ?? '',
      fcmToken: data['fcmToken'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastReportAt: (data['lastReportAt'] as Timestamp?)?.toDate(),
      reportsCount: data['reportsCount'] ?? 0,
      disabled: data['disabled'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'realName': realName,
      'email': email,
      'photoURL': photoURL,
      'role': role.value,
      'teamId': teamId,
      'municipalityId': municipalityId,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastReportAt': lastReportAt != null
          ? Timestamp.fromDate(lastReportAt!)
          : null,
      'reportsCount': reportsCount,
      'disabled': disabled,
    };
  }

  UserModel copyWith({
    String? displayName,
    String? realName,
    String? email,
    String? photoURL,
    UserRole? role,
    String? teamId,
    String? municipalityId,
    String? fcmToken,
    DateTime? lastReportAt,
    int? reportsCount,
    bool? disabled,
  }) {
    return UserModel(
      uid: uid,
      displayName: displayName ?? this.displayName,
      realName: realName ?? this.realName,
      email: email ?? this.email,
      photoURL: photoURL ?? this.photoURL,
      role: role ?? this.role,
      teamId: teamId ?? this.teamId,
      municipalityId: municipalityId ?? this.municipalityId,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt,
      lastReportAt: lastReportAt ?? this.lastReportAt,
      reportsCount: reportsCount ?? this.reportsCount,
      disabled: disabled ?? this.disabled,
    );
  }
}
