import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/models/team_model.dart';
import '../../../data/models/municipality_stats.dart';
import '../../../data/repositories/municipality_stats_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/repositories/teams_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class CoordinatorHomeScreen extends ConsumerStatefulWidget {
  const CoordinatorHomeScreen({super.key});

  @override
  ConsumerState<CoordinatorHomeScreen> createState() =>
      _CoordinatorHomeScreenState();
}

class _CoordinatorHomeScreenState
    extends ConsumerState<CoordinatorHomeScreen> {
  ReportStatus? _filter;

  Future<void> _assign(ReportModel report, String municipalityId) async {
    final selectedTeam = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TeamPicker(
        municipalityId: municipalityId,
        category: report.category.value,
        currentTeamId: report.assignedTeamId,
      ),
    );
    if (selectedTeam == null || !mounted) return;
    try {
      await ref.read(reportsRepositoryProvider).assignTeam(report.id, selectedTeam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equipo asignado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo asignar el equipo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final profileAsync = uid == null
        ? null
        : ref.watch(currentUserProfileProvider(uid));
    final municipalityId = profileAsync?.valueOrNull?.municipalityId;
    final reportsAsync = municipalityId == null || municipalityId.isEmpty
        ? null
        : ref.watch(municipalityReportsProvider(municipalityId));
    final stats = municipalityId == null || municipalityId.isEmpty
        ? null
        : ref.watch(municipalityStatsProvider(municipalityId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel coordinador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/coordinator/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros de estado
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _FilterChip(
                    label: 'Todos',
                    active: _filter == null,
                    onTap: () => setState(() => _filter = null)),
                _FilterChip(
                    label: 'Pendientes',
                    active: _filter == ReportStatus.pending,
                    color: AppColors.statusPending,
                    onTap: () =>
                        setState(() => _filter = ReportStatus.pending)),
                _FilterChip(
                    label: 'Asignados',
                    active: _filter == ReportStatus.assigned,
                    color: AppColors.statusAssigned,
                    onTap: () =>
                        setState(() => _filter = ReportStatus.assigned)),
                _FilterChip(
                    label: 'En curso',
                    active: _filter == ReportStatus.inProgress,
                    color: AppColors.statusInProgress,
                    onTap: () =>
                        setState(() => _filter = ReportStatus.inProgress)),
                _FilterChip(
                    label: 'Resueltos',
                    active: _filter == ReportStatus.resolved,
                    color: AppColors.statusResolved,
                    onTap: () =>
                        setState(() => _filter = ReportStatus.resolved)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (stats != null) _StatsCard(stats: stats),
          Expanded(
            child: reportsAsync == null
                ? Center(
                    child: profileAsync?.hasError == true
                        ? Text('No se pudo cargar el perfil: ${profileAsync!.error}')
                        : profileAsync?.hasValue == true
                            ? const Text('Tu usuario no tiene municipio asignado.')
                            : const CircularProgressIndicator(),
                  )
                : reportsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (allReports) {
                final reports = _filter == null
                    ? allReports
                    : allReports.where((r) => r.status == _filter).toList();
                if (reports.isEmpty) {
                  return const Center(
                    child: Text('Sin reportes.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: reports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ReportTile(
                      report: reports[i],
                      onAssign: reports[i].status == ReportStatus.pending ||
                              reports[i].status == ReportStatus.assigned
                          ? () => _assign(reports[i], municipalityId!)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final MunicipalityStats stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final active = (stats.statusCounts['assigned'] ?? 0) +
        (stats.statusCounts['in_progress'] ?? 0);
    final average = stats.averageResolutionHours;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pulso del municipio · en vivo',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatValue('Pendientes', stats.statusCounts['pending'] ?? 0),
              _StatValue('En gestión', active),
              _StatValue('Resueltos', stats.statusCounts['resolved'] ?? 0),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${stats.total} reportes · ${stats.supports} apoyos · '
            'resolución promedio: ${average == null ? '—' : '${average.toStringAsFixed(1)} h'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  final String label;
  final int value;
  const _StatValue(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ],
      );
}

class _ReportTile extends StatelessWidget {
  final ReportModel report;
  final VoidCallback? onAssign;
  const _ReportTile({required this.report, this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/report/${report.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: statusColor(report.status.value),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      categoryLabel(report.category.value),
                      style: TextStyle(
                          fontSize: 11,
                          color: categoryColor(report.category.value)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor(report.status.value).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel(report.status.value),
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor(report.status.value),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(report.createdAt, locale: 'es'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (onAssign != null)
                    TextButton(
                      onPressed: onAssign,
                      child: Text(report.assignedTeamId == null
                          ? 'Asignar equipo'
                          : 'Reasignar'),
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

class _TeamPicker extends ConsumerWidget {
  final String municipalityId;
  final String category;
  final String? currentTeamId;

  const _TeamPicker({
    required this.municipalityId,
    required this.category,
    this.currentTeamId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(activeTeamsProvider(municipalityId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Asignar equipo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            teamsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('No se pudieron cargar los equipos: $e'),
              data: (teams) {
                if (teams.isEmpty) {
                  return const Text('No hay equipos activos en este municipio.');
                }
                final sorted = [...teams]..sort((a, b) {
                  final aMatch = a.categories.isEmpty || a.categories.contains(category);
                  final bMatch = b.categories.isEmpty || b.categories.contains(category);
                  if (aMatch != bMatch) return aMatch ? -1 : 1;
                  return a.name.compareTo(b.name);
                });
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    itemBuilder: (_, index) {
                      final TeamModel team = sorted[index];
                      final fits = team.categories.isEmpty || team.categories.contains(category);
                      return ListTile(
                        title: Text(team.name),
                        subtitle: Text(fits ? 'Apto para esta categoría' : 'Otra especialidad'),
                        trailing: team.id == currentTeamId
                            ? const Icon(Icons.check_circle, color: AppColors.primary)
                            : null,
                        onTap: () => Navigator.pop(context, team.id),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    this.color = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
