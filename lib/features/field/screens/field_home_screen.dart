import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class FieldHomeScreen extends ConsumerStatefulWidget {
  const FieldHomeScreen({super.key});

  @override
  ConsumerState<FieldHomeScreen> createState() => _FieldHomeScreenState();
}

class _FieldHomeScreenState extends ConsumerState<FieldHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Position? _myPosition;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadPosition();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) setState(() => _myPosition = pos);
    } catch (_) {}
  }

  String _distance(ReportModel r) {
    if (_myPosition == null) return '';
    final meters = Geolocator.distanceBetween(
      _myPosition!.latitude,
      _myPosition!.longitude,
      r.location.lat,
      r.location.lng,
    );
    return meters < 1000
        ? '${meters.round()} m'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final userAsync = ref.watch(
      StreamProvider((ref) => ref.read(userRepositoryProvider).watchUser(user.uid)),
    );
    final teamId = userAsync.valueOrNull?.teamId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis tareas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/field/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Asignadas'),
            Tab(text: 'En curso'),
            Tab(text: 'Hoy'),
          ],
        ),
      ),
      body: teamId == null
          ? const Center(child: Text('Sin equipo asignado.'))
          : TabBarView(
              controller: _tabs,
              children: [
                _TaskList(
                    teamId: teamId,
                    status: ReportStatus.assigned,
                    distanceFn: _distance),
                _TaskList(
                    teamId: teamId,
                    status: ReportStatus.inProgress,
                    distanceFn: _distance),
                _TaskList(
                    teamId: teamId,
                    status: ReportStatus.resolved,
                    distanceFn: _distance,
                    todayOnly: true),
              ],
            ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  final String teamId;
  final ReportStatus status;
  final String Function(ReportModel) distanceFn;
  final bool todayOnly;

  const _TaskList({
    required this.teamId,
    required this.status,
    required this.distanceFn,
    this.todayOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(teamReportsProvider(teamId));

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allReports) {
        var reports = allReports.where((r) => r.status == status).toList();
        if (todayOnly) {
          final today = DateTime.now();
          reports = reports.where((r) {
            final resolved = r.resolvedAt;
            return resolved != null &&
                resolved.day == today.day &&
                resolved.month == today.month &&
                resolved.year == today.year;
          }).toList();
        }

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  status == ReportStatus.assigned
                      ? 'Sin tareas asignadas.'
                      : status == ReportStatus.inProgress
                          ? 'Sin tareas en curso.'
                          : 'Sin tareas resueltas hoy.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(teamReportsProvider(teamId).future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _TaskCard(
              report: reports[i],
              distance: distanceFn(reports[i]),
            ),
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ReportModel report;
  final String distance;
  const _TaskCard({required this.report, required this.distance});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/field/task/${report.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: statusColor(report.status.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      report.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (distance.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.near_me_outlined,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 3),
                          Text(
                            distance,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: categoryColor(report.category.value)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      categoryLabel(report.category.value),
                      style: TextStyle(
                          fontSize: 11,
                          color: categoryColor(report.category.value),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeago.format(report.createdAt, locale: 'es'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
