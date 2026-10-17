import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardAiReport {
  const DashboardAiReport({
    required this.status,
    this.periodDays = 30,
    this.totalReports = 0,
    this.summary = '',
    this.priorities = const [],
    this.strategies = const [],
    this.risks = const [],
    this.questions = const [],
  });

  final String status;
  final int periodDays;
  final int totalReports;
  final String summary;
  final List<Map<String, String>> priorities;
  final List<Map<String, String>> strategies;
  final List<String> risks;
  final List<String> questions;

  factory DashboardAiReport.fromMap(Map<String, dynamic> map) {
    List<Map<String, String>> readPriorities(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => <String, String>{
                'title': '${item["title"] ?? ""}',
                'evidence': '${item["evidence"] ?? ""}',
                'action': '${item["action"] ?? ""}',
              })
          .toList();
    }

    List<Map<String, String>> readStrategies(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => <String, String>{
                'title': '${item["title"] ?? ""}',
                'objective': '${item["objective"] ?? ""}',
                'action': '${item["action"] ?? ""}',
                'resourceImpact': '${item["resourceImpact"] ?? ""}',
              })
          .toList();
    }

    List<String> readStrings(Object? value) => value is List
        ? value
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList()
        : const [];

    return DashboardAiReport(
      status: '${map["status"] ?? "unavailable"}',
      periodDays: (map['periodDays'] as num?)?.toInt() ?? 30,
      totalReports: (map['totalReports'] as num?)?.toInt() ?? 0,
      summary: '${map["summary"] ?? ""}',
      priorities: readPriorities(map['priorities']),
      strategies: readStrategies(map['strategies']),
      risks: readStrings(map['risks']),
      questions: readStrings(map['questions']),
    );
  }
}

class DashboardAiService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  Future<DashboardAiReport> generate({
    required String municipalityId,
    int periodDays = 30,
  }) async {
    final callable = _functions.httpsCallable('generateMunicipalityReport');
    final result = await callable.call({
      'municipalityId': municipalityId,
      'periodDays': periodDays.clamp(7, 90),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DashboardAiReport.fromMap(data);
  }
}

final dashboardAiServiceProvider = Provider<DashboardAiService>(
  (_) => DashboardAiService(),
);
