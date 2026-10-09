import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Categorías de problemas urbanos
enum ReportCategory {
  infrastructure,
  lighting,
  garbage,
  security,
  health,
  transport,
  environment,
  other;

  String get value => name;

  static ReportCategory fromString(String value) {
    return ReportCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReportCategory.other,
    );
  }
}

/// Estados del ciclo de vida de un reporte
enum ReportStatus {
  pending,
  assigned,
  inProgress,
  resolved,
  rejected,
  closed;

  String get value {
    switch (this) {
      case ReportStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }

  static ReportStatus fromString(String value) {
    switch (value) {
      case 'in_progress':
        return ReportStatus.inProgress;
      default:
        return ReportStatus.values.firstWhere(
          (e) => e.name == value,
          orElse: () => ReportStatus.pending,
        );
    }
  }
}

/// Ubicación de un reporte con GeoHash para consultas eficientes
class ReportLocation {
  final double lat;
  final double lng;
  final String geohash;
  final String? address;

  const ReportLocation({
    required this.lat,
    required this.lng,
    required this.geohash,
    this.address,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory ReportLocation.fromMap(Map<String, dynamic> map) {
    return ReportLocation(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      geohash: map['geohash'] ?? '',
      address: map['address'],
    );
  }

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'geohash': geohash,
        'address': address,
      };

  ReportLocation copyWith({double? lat, double? lng, String? geohash, String? address}) {
    return ReportLocation(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      geohash: geohash ?? this.geohash,
      address: address ?? this.address,
    );
  }
}

/// Modelo principal de un reporte ciudadano
class ReportModel {
  final String id;
  final String userId;
  final String municipalityId;

  // Datos del problema
  final String title;
  final String description;
  final ReportCategory category;

  // Fotos por etapa
  final List<String> photosReport;  // ciudadano al reportar
  final List<String> photosBefore;  // equipo al llegar
  final List<String> photosProgress; // equipo durante el trabajo
  final List<String> photosAfter;   // equipo al terminar

  // Ubicación
  final ReportLocation location;

  // Estado y asignación
  final ReportStatus status;
  final int priority;           // 1-5, mayor = más urgente
  final int supportCount;       // votos de apoyo de vecinos

  final String? assignedTeamId;
  final String? assignedWorkerId;
  final DateTime? assignedAt;

  // Datos del trabajo de campo
  final DateTime? workerArrivedAt;
  final DateTime? workStartedAt;
  final DateTime? workFinishedAt;
  final String? workerNotes;

  // Resolución
  final DateTime? resolvedAt;
  final String? rejectionReason;

  // Moderación
  final bool hidden;
  final int flaggedCount;

  // Metadatos
  final int commentsCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Calificación del ciudadano
  final int? rating;            // 1-5, null si no calificó
  final String? ratingComment;

  const ReportModel({
    required this.id,
    required this.userId,
    required this.municipalityId,
    required this.title,
    required this.description,
    required this.category,
    this.photosReport = const [],
    this.photosBefore = const [],
    this.photosProgress = const [],
    this.photosAfter = const [],
    required this.location,
    this.status = ReportStatus.pending,
    this.priority = 1,
    this.supportCount = 0,
    this.assignedTeamId,
    this.assignedWorkerId,
    this.assignedAt,
    this.workerArrivedAt,
    this.workStartedAt,
    this.workFinishedAt,
    this.workerNotes,
    this.resolvedAt,
    this.rejectionReason,
    this.hidden = false,
    this.flaggedCount = 0,
    this.commentsCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.rating,
    this.ratingComment,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReportModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      municipalityId: data['municipalityId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: ReportCategory.fromString(data['category'] ?? 'other'),
      photosReport: List<String>.from(data['photosReport'] ?? []),
      photosBefore: List<String>.from(data['photosBefore'] ?? []),
      photosProgress: List<String>.from(data['photosProgress'] ?? []),
      photosAfter: List<String>.from(data['photosAfter'] ?? []),
      location: ReportLocation.fromMap(
        data['location'] as Map<String, dynamic>? ?? {},
      ),
      status: ReportStatus.fromString(data['status'] ?? 'pending'),
      priority: data['priority'] ?? 1,
      supportCount: data['supportCount'] ?? 0,
      assignedTeamId: data['assignedTeamId'],
      assignedWorkerId: data['assignedWorkerId'],
      assignedAt: _readDate(data['assignedAt']),
      workerArrivedAt: _readDate(data['workerArrivedAt']),
      workStartedAt: _readDate(data['workStartedAt']),
      workFinishedAt: _readDate(data['workFinishedAt']),
      workerNotes: data['workerNotes'],
      resolvedAt: _readDate(data['resolvedAt']),
      rejectionReason: data['rejectionReason'],
      hidden: data['hidden'] ?? false,
      flaggedCount: data['flaggedCount'] ?? 0,
      commentsCount: data['commentsCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rating: data['rating'],
      ratingComment: data['ratingComment'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'municipalityId': municipalityId,
      'title': title,
      'description': description,
      'category': category.value,
      'photosReport': photosReport,
      'photosBefore': photosBefore,
      'photosProgress': photosProgress,
      'photosAfter': photosAfter,
      'location': location.toMap(),
      'status': status.value,
      'priority': priority,
      'supportCount': supportCount,
      'assignedTeamId': assignedTeamId,
      'assignedWorkerId': assignedWorkerId,
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'workerArrivedAt': workerArrivedAt != null ? Timestamp.fromDate(workerArrivedAt!) : null,
      'workStartedAt': workStartedAt != null ? Timestamp.fromDate(workStartedAt!) : null,
      'workFinishedAt': workFinishedAt != null ? Timestamp.fromDate(workFinishedAt!) : null,
      'workerNotes': workerNotes,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'rejectionReason': rejectionReason,
      'hidden': hidden,
      'flaggedCount': flaggedCount,
      'commentsCount': commentsCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'rating': rating,
      'ratingComment': ratingComment,
    };
  }

  ReportModel copyWith({
    String? title,
    String? description,
    ReportCategory? category,
    List<String>? photosReport,
    List<String>? photosBefore,
    List<String>? photosProgress,
    List<String>? photosAfter,
    ReportLocation? location,
    ReportStatus? status,
    int? priority,
    int? supportCount,
    String? assignedTeamId,
    String? assignedWorkerId,
    DateTime? assignedAt,
    DateTime? workerArrivedAt,
    DateTime? workStartedAt,
    DateTime? workFinishedAt,
    String? workerNotes,
    DateTime? resolvedAt,
    String? rejectionReason,
    bool? hidden,
    int? flaggedCount,
    int? commentsCount,
    DateTime? updatedAt,
    int? rating,
    String? ratingComment,
  }) {
    return ReportModel(
      id: id,
      userId: userId,
      municipalityId: municipalityId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      photosReport: photosReport ?? this.photosReport,
      photosBefore: photosBefore ?? this.photosBefore,
      photosProgress: photosProgress ?? this.photosProgress,
      photosAfter: photosAfter ?? this.photosAfter,
      location: location ?? this.location,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      supportCount: supportCount ?? this.supportCount,
      assignedTeamId: assignedTeamId ?? this.assignedTeamId,
      assignedWorkerId: assignedWorkerId ?? this.assignedWorkerId,
      assignedAt: assignedAt ?? this.assignedAt,
      workerArrivedAt: workerArrivedAt ?? this.workerArrivedAt,
      workStartedAt: workStartedAt ?? this.workStartedAt,
      workFinishedAt: workFinishedAt ?? this.workFinishedAt,
      workerNotes: workerNotes ?? this.workerNotes,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      hidden: hidden ?? this.hidden,
      flaggedCount: flaggedCount ?? this.flaggedCount,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rating: rating ?? this.rating,
      ratingComment: ratingComment ?? this.ratingComment,
    );
  }
}
