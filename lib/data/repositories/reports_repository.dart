import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report_model.dart';
import '../../core/constants/app_constants.dart';

class ReportsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.reportsCollection);

  // ─── Lectura ─────────────────────────────────────────────────────────────

  Stream<List<ReportModel>> watchReports({
    String? municipalityId,
    ReportStatus? status,
  }) {
    Query<Map<String, dynamic>> q = _col.where('hidden', isEqualTo: false);
    if (municipalityId != null) {
      q = q.where('municipalityId', isEqualTo: municipalityId);
    }
    if (status != null) {
      q = q.where('status', isEqualTo: status.value);
    }
    q = q.orderBy('createdAt', descending: true).limit(200);
    return q.snapshots().map(
          (snap) => snap.docs.map(ReportModel.fromFirestore).toList(),
        );
  }

  Stream<List<ReportModel>> watchUserReports(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ReportModel.fromFirestore).toList());
  }

  Stream<List<ReportModel>> watchTeamReports(String teamId) {
    return _col
        .where('assignedTeamId', isEqualTo: teamId)
        .where('hidden', isEqualTo: false)
        .orderBy('priority', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ReportModel.fromFirestore).toList());
  }

  Future<ReportModel?> getReport(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return ReportModel.fromFirestore(doc);
  }

  Future<int> countUserReportsToday(String userId) async {
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final snap = await _col
        .where('userId', isEqualTo: userId)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─── Escritura ────────────────────────────────────────────────────────────

  Future<String> createReport(ReportModel report) async {
    await _col.doc(report.id).set(report.toFirestore());
    // Actualizar contador del usuario
    await _db
        .collection(AppConstants.usersCollection)
        .doc(report.userId)
        .update({
      'reportsCount': FieldValue.increment(1),
      'lastReportAt': FieldValue.serverTimestamp(),
    });
    return report.id;
  }

  Future<void> updateReport(String id, Map<String, dynamic> fields) async {
    await _col.doc(id).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// La función valida rol, municipio, estado y equipo antes de asignar.
  Future<void> assignTeam(String reportId, String teamId) async {
    await FirebaseFunctions.instance.httpsCallable('assignReportTeam').call({
      'reportId': reportId,
      'teamId': teamId,
    });
  }

  // ─── Votos de apoyo ───────────────────────────────────────────────────────

  Future<void> addSupportVote(String reportId, String userId) async {
    final voteRef = _col
        .doc(reportId)
        .collection(AppConstants.supportVotesCollection)
        .doc(userId);
    final existing = await voteRef.get();
    if (existing.exists) return; // ya votó

    final batch = _db.batch();
    batch.set(voteRef, {
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_col.doc(reportId), {
      'supportCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<bool> hasVoted(String reportId, String userId) async {
    final doc = await _col
        .doc(reportId)
        .collection(AppConstants.supportVotesCollection)
        .doc(userId)
        .get();
    return doc.exists;
  }

  // ─── Fotos ────────────────────────────────────────────────────────────────

  Future<List<String>> uploadReportPhotos({
    required String reportId,
    required List<File> files,
  }) async {
    final urls = <String>[];
    for (int i = 0; i < files.length; i++) {
      final ref = _storage.ref(
        'reports/$reportId/citizen/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
      );
      await ref.putFile(
        files[i],
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<String> uploadFieldPhoto({
    required String reportId,
    required File file,
    required String phase, // 'before' o 'after'
  }) async {
    final ref = _storage.ref(
      'reports/$reportId/$phase/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  // ─── Moderación ──────────────────────────────────────────────────────────

  Future<void> flagContent({
    required String reportedBy,
    required String targetType,
    required String targetId,
    required String reportId,
    required String reason,
  }) async {
    await _db.collection(AppConstants.contentFlagsCollection).add({
      'reportedBy': reportedBy,
      'targetType': targetType,
      'targetId': targetId,
      'reportId': reportId,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Incrementar contador de denuncias en el item
    if (targetType == 'report') {
      await _col.doc(targetId)
          .update({'flaggedCount': FieldValue.increment(1)});
    }
  }
}

// ─── Proveedores ─────────────────────────────────────────────────────────────

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (_) => ReportsRepository(),
);

final municipalityReportsProvider =
    StreamProvider.family<List<ReportModel>, String>((ref, municipalityId) {
  return ref.read(reportsRepositoryProvider).watchReports(
        municipalityId: municipalityId,
      );
});

/// Stream de reportes del usuario para "Mis reportes"
final myReportsProvider =
    StreamProvider.family<List<ReportModel>, String>((ref, userId) {
  return ref.read(reportsRepositoryProvider).watchUserReports(userId);
});

/// Stream de reportes del equipo de campo
final teamReportsProvider =
    StreamProvider.family<List<ReportModel>, String>((ref, teamId) {
  return ref.read(reportsRepositoryProvider).watchTeamReports(teamId);
});
