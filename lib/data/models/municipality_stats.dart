import 'package:cloud_firestore/cloud_firestore.dart';

class MunicipalityStats {
  final int total;
  final int supports;
  final Map<String, int> statusCounts;
  final Map<String, int> categoryCounts;
  final int resolutionCount;
  final double resolutionHoursSum;

  const MunicipalityStats({
    required this.total,
    required this.supports,
    required this.statusCounts,
    required this.categoryCounts,
    required this.resolutionCount,
    required this.resolutionHoursSum,
  });

  double? get averageResolutionHours => resolutionCount == 0
      ? null
      : resolutionHoursSum / resolutionCount;

  factory MunicipalityStats.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    Map<String, int> counts(Object? value) {
      if (value is! Map) return const {};
      return value.map((key, count) => MapEntry(
            key.toString(),
            count is num ? count.toInt() : 0,
          ));
    }

    return MunicipalityStats(
      total: (data['total'] as num?)?.toInt() ?? 0,
      supports: (data['supports'] as num?)?.toInt() ?? 0,
      statusCounts: counts(data['statusCounts']),
      categoryCounts: counts(data['categoryCounts']),
      resolutionCount: (data['resolutionCount'] as num?)?.toInt() ?? 0,
      resolutionHoursSum: (data['resolutionHoursSum'] as num?)?.toDouble() ?? 0,
    );
  }
}
