import 'package:flutter/material.dart';
import '../../advertising/ads_management_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/condi_logo.dart';
import '../../../core/widgets/municipality_identity.dart';
import '../../../data/models/municipality_stats.dart';
import '../../../data/models/report_model.dart';
import '../../../data/models/team_model.dart';
import '../../../data/repositories/municipality_stats_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/repositories/teams_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/utils/error_text.dart';
import '../widgets/dashboard_ai_card.dart';
import '../widgets/html_report_view.dart';
import '../widgets/municipality_map_view.dart';
import '../widgets/send_message_view.dart';

/// Consola web propia de ConDi. Los streams vienen directamente de Firestore,
/// por eso una alta, asignación o resolución aparece sin recargar la página.
class AdminConsoleScreen extends ConsumerStatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  ConsumerState<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends ConsumerState<AdminConsoleScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  ReportStatus? _filter;
  String _search = '';
  int _section = 0;

  Future<void> _assign(ReportModel report, String municipalityId) async {
    final teamId = await showDialog<String>(
      context: context,
      builder: (_) => _AssignDialog(
        municipalityId: municipalityId,
        report: report,
      ),
    );
    if (teamId == null || !mounted) return;
    try {
      await ref.read(reportsRepositoryProvider).assignTeam(report.id, teamId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equipo asignado.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeDeError(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final profile =
        uid == null ? null : ref.watch(currentUserProfileProvider(uid));
    final profileModel = profile?.valueOrNull;
    final municipalityId = profileModel?.municipalityId ?? '';
    final reports = municipalityId.isEmpty
        ? null
        : ref.watch(adminMunicipalityReportsProvider(municipalityId));
    final stats = municipalityId.isEmpty
        ? null
        : ref.watch(municipalityStatsProvider(municipalityId)).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F7FC),
      body: Row(
        children: [
          if (wide)
            _Sidebar(
                section: _section,
                onChanged: (v) => setState(() => _section = v)),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _Header(
                    wide: wide,
                    municipalityId: municipalityId,
                    municipalityName: profileModel?.municipalityName,
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onProfile: () => context.go('/profile'),
                  ),
                  Expanded(
                    child: reports == null
                        ? const Center(child: CircularProgressIndicator())
                        : reports.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (_, __) => const _EmptyState(
                              icon: Icons.cloud_off_outlined,
                              text: 'No pudimos cargar los datos en vivo.',
                            ),
                            data: (items) => _ConsoleBody(
                              section: _section,
                              stats: stats,
                              reports: items,
                              search: _search,
                              filter: _filter,
                              municipalityId: municipalityId,
                              isAdmin: profileModel?.isCentralAdmin == true,
                              onSearch: (v) => setState(() => _search = v),
                              onFilter: (v) => setState(() => _filter = v),
                              onAssign: (r) => _assign(r, municipalityId),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                  child: _Sidebar(
                      section: _section,
                      onChanged: (v) {
                        setState(() => _section = v);
                        Navigator.pop(context);
                      }))),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.wide,
      required this.municipalityId,
      required this.municipalityName,
      required this.onMenu,
      required this.onProfile});
  final bool wide;
  final String municipalityId;
  final String? municipalityName;
  final VoidCallback onMenu;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Colors.white,
        child: Row(children: [
          if (!wide)
            IconButton(onPressed: onMenu, icon: const Icon(Icons.menu)),
          Expanded(
            child: MunicipalityIdentity(
              municipalityId: municipalityId,
              municipalityName: municipalityName,
              crestSize: 43,
              subtitle: 'Centro de gestión · Operación en tiempo real',
            ),
          ),
          const _LiveBadge(),
          const SizedBox(width: 10),
          IconButton(
              onPressed: onProfile,
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Perfil'),
        ]),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section, required this.onChanged});
  final int section;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: 244,
        color: const Color(0xFF0A1220),
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: CondiLogo(fontSize: 30)),
          const Padding(
              padding: EdgeInsets.fromLTRB(12, 5, 12, 28),
              child: Text('Administración municipal',
                  style: TextStyle(color: Color(0xFF9CA9BF), fontSize: 11))),
          _NavItem(
              icon: Icons.dashboard_outlined,
              label: 'Resumen',
              selected: section == 0,
              onTap: () => onChanged(0)),
          _NavItem(
              icon: Icons.assignment_outlined,
              label: 'Reportes',
              selected: section == 1,
              onTap: () => onChanged(1)),
          _NavItem(
              icon: Icons.groups_outlined,
              label: 'Cuadrillas',
              selected: section == 2,
              onTap: () => onChanged(2)),
          _NavItem(
              icon: Icons.storefront_outlined,
              label: 'Publicidad',
              selected: section == 3,
              onTap: () => onChanged(3)),
          _NavItem(
              icon: Icons.map_outlined,
              label: 'Mapa operativo',
              selected: section == 4,
              onTap: () => onChanged(4)),
          _NavItem(
              icon: Icons.description_outlined,
              label: 'Informes HTML',
              selected: section == 5,
              onTap: () => onChanged(5)),
          _NavItem(
              icon: Icons.campaign_outlined,
              label: 'Enviar mensaje',
              selected: section == 6,
              onTap: () => onChanged(6)),
          const Spacer(),
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('CONDI · CONSULTORA DIAGONALES',
                  style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF74809A),
                      fontWeight: FontWeight.w700))),
        ]),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
            color: selected ? const Color(0xFF1C315A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(children: [
                  Icon(icon,
                      size: 20,
                      color: selected ? Colors.white : const Color(0xFFAAB6CA)),
                  const SizedBox(width: 12),
                  Text(label,
                      style: TextStyle(
                          color:
                              selected ? Colors.white : const Color(0xFFAAB6CA),
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500))
                ]),
              ),
            )),
      );
}

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody(
      {required this.section,
      required this.stats,
      required this.reports,
      required this.search,
      required this.filter,
      required this.municipalityId,
      required this.isAdmin,
      required this.onSearch,
      required this.onFilter,
      required this.onAssign});
  final int section;
  final MunicipalityStats? stats;
  final List<ReportModel> reports;
  final String search;
  final ReportStatus? filter;
  final String municipalityId;
  final bool isAdmin;
  final ValueChanged<String> onSearch;
  final ValueChanged<ReportStatus?> onFilter;
  final ValueChanged<ReportModel> onAssign;

  @override
  Widget build(BuildContext context) {
    if (section == 3) return AdsManagementView(municipalityId: municipalityId);
    if (section == 4) return MunicipalityMapView(reports: reports);
    if (section == 5) return HtmlReportView(reports: reports);
    if (section == 6) return SendMessageView(isAdmin: isAdmin);
    if (section == 2) return _TeamsView(municipalityId: municipalityId);
    final visible = reports.where((r) {
      final term = search.toLowerCase().trim();
      return (filter == null || r.status == filter) &&
          (term.isEmpty ||
              r.title.toLowerCase().contains(term) ||
              r.description.toLowerCase().contains(term));
    }).toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      if (section == 0) ...[
        const Text('Resumen operativo',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17213A))),
        const SizedBox(height: 5),
        const Text('Indicadores actualizados automáticamente con cada reporte.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 22),
        _KpiGrid(stats: stats, reports: reports),
        const SizedBox(height: 22),
        _Analytics(reports: reports),
        const SizedBox(height: 22),
        DashboardAiCard(municipalityId: municipalityId),
        const SizedBox(height: 28),
        const Text('Últimos reportes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
      ],
      if (section == 1) ...[
        const Text('Reportes',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17213A))),
        const SizedBox(height: 18),
      ],
      _ReportControls(
          search: search,
          filter: filter,
          onSearch: onSearch,
          onFilter: onFilter),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        const _EmptyState(
            icon: Icons.inbox_outlined,
            text: 'No hay reportes para este filtro.')
      else
        _ReportsTable(
            reports: section == 0 ? visible.take(6).toList() : visible,
            onAssign: onAssign),
    ]);
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.stats, required this.reports});
  final MunicipalityStats? stats;
  final List<ReportModel> reports;
  @override
  Widget build(BuildContext context) {
    final counts = _statusCounts(reports);
    final active = (counts['assigned'] ?? 0) + (counts['in_progress'] ?? 0);
    return LayoutBuilder(builder: (_, c) {
      final columns = c.maxWidth >= 900
          ? 4
          : c.maxWidth >= 550
              ? 2
              : 1;
      final cards = [
        _Kpi('Reportes recibidos', reports.length, Icons.inbox_outlined,
            AppColors.brandBlue),
        _Kpi('Pendientes', counts['pending'] ?? 0, Icons.priority_high_outlined,
            AppColors.statusPending),
        _Kpi('En gestión', active, Icons.engineering_outlined,
            AppColors.statusAssigned),
        _Kpi('Resueltos', counts['resolved'] ?? 0, Icons.task_alt_outlined,
            AppColors.statusResolved),
      ];
      return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: columns == 1 ? 3.8 : 2.05,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: cards);
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color)),
            const SizedBox(width: 14),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$value',
                      style: const TextStyle(
                          fontSize: 25, fontWeight: FontWeight.w800)),
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))
                ])
          ])));
}

class _Analytics extends StatelessWidget {
  const _Analytics({required this.reports});
  final List<ReportModel> reports;
  @override
  Widget build(BuildContext context) {
    final counts = _statusCounts(reports);
    final max =
        [for (final v in counts.values) v, 1].reduce((a, b) => a > b ? a : b);
    return Card(
        elevation: 0,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Estado de la operación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              for (final state in ReportStatus.values.where((s) =>
                  s != ReportStatus.closed && s != ReportStatus.rejected))
                _StatusBar(
                    label: statusLabel(state.value),
                    value: counts[state.value] ?? 0,
                    max: max,
                    color: statusColor(state.value))
            ])));
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.label,
      required this.value,
      required this.max,
      required this.color});
  final String label;
  final int value;
  final int max;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: value / max,
                    minHeight: 10,
                    color: color,
                    backgroundColor: color.withOpacity(.12)))),
        const SizedBox(width: 10),
        SizedBox(
            width: 22,
            child: Text('$value',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700)))
      ]));
}

class _ReportControls extends StatelessWidget {
  const _ReportControls(
      {required this.search,
      required this.filter,
      required this.onSearch,
      required this.onFilter});
  final String search;
  final ReportStatus? filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<ReportStatus?> onFilter;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 310,
            child: TextField(
                onChanged: onSearch,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar reporte',
                    isDense: true))),
        DropdownButton<ReportStatus?>(
          value: filter,
          hint: const Text('Todos los estados'),
          items: [
            const DropdownMenuItem<ReportStatus?>(
                value: null, child: Text('Todos los estados')),
            ...ReportStatus.values.map((s) => DropdownMenuItem<ReportStatus?>(
                value: s, child: Text(statusLabel(s.value))))
          ],
          onChanged: onFilter,
        ),
      ]);
}

class _ReportsTable extends StatefulWidget {
  const _ReportsTable({required this.reports, required this.onAssign});
  final List<ReportModel> reports;
  final ValueChanged<ReportModel> onAssign;
  @override
  State<_ReportsTable> createState() => _ReportsTableState();
}

class _ReportsTableState extends State<_ReportsTable> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final lastPage =
        widget.reports.isEmpty ? 0 : (widget.reports.length - 1) ~/ 50;
    final page = _page.clamp(0, lastPage);
    final reports = widget.reports.skip(page * 50).take(50).toList();
    final onAssign = widget.onAssign;
    return Column(children: [
      Card(
          elevation: 0,
          child: LayoutBuilder(builder: (_, c) {
            if (c.maxWidth < 680)
              return Column(children: [
                for (final r in reports)
                  _MobileReport(report: r, onAssign: onAssign)
              ]);
            return Column(children: [
              const Padding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(children: [
                    Expanded(
                        flex: 4, child: Text('REPORTE', style: _tableHeading)),
                    Expanded(
                        flex: 2,
                        child: Text('CATEGORÍA', style: _tableHeading)),
                    Expanded(
                        flex: 2, child: Text('ESTADO', style: _tableHeading)),
                    SizedBox(width: 126)
                  ])),
              const Divider(height: 1),
              for (final r in reports)
                _DesktopReport(report: r, onAssign: onAssign)
            ]);
          })),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
            icon: const Icon(Icons.chevron_left)),
        Text(
            '${widget.reports.length} reportes · Página ${page + 1} de ${lastPage + 1}'),
        IconButton(
            onPressed:
                page < lastPage ? () => setState(() => _page = page + 1) : null,
            icon: const Icon(Icons.chevron_right)),
      ]),
    ]);
  }
}

const _tableHeading = TextStyle(
    fontSize: 10,
    letterSpacing: .8,
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w800);

class _DesktopReport extends StatelessWidget {
  const _DesktopReport({required this.report, required this.onAssign});
  final ReportModel report;
  final ValueChanged<ReportModel> onAssign;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push('/report/${report.id}'),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(children: [
              Expanded(
                  flex: 4,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(report.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(timeago.format(report.createdAt, locale: 'es'),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary))
                      ])),
              Expanded(
                  flex: 2,
                  child: Text(categoryLabel(report.category.value),
                      style: TextStyle(
                          fontSize: 12,
                          color: categoryColor(report.category.value)))),
              Expanded(flex: 2, child: _StateChip(report.status)),
              SizedBox(
                  width: 126,
                  child: report.status == ReportStatus.pending ||
                          report.status == ReportStatus.assigned
                      ? TextButton(
                          onPressed: () => onAssign(report),
                          child: Text(report.assignedTeamId == null
                              ? 'Asignar'
                              : 'Reasignar'))
                      : const SizedBox()),
            ])),
      );
}

class _MobileReport extends StatelessWidget {
  const _MobileReport({required this.report, required this.onAssign});
  final ReportModel report;
  final ValueChanged<ReportModel> onAssign;
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: () => context.push('/report/${report.id}'),
      title: Text(report.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${categoryLabel(report.category.value)} · ${timeago.format(report.createdAt, locale: 'es')}'),
      trailing: report.status == ReportStatus.pending
          ? IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => onAssign(report))
          : _StateChip(report.status));
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.status);
  final ReportStatus status;
  @override
  Widget build(BuildContext context) {
    final color = statusColor(status.value);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(statusLabel(status.value),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)));
  }
}

class _TeamsView extends ConsumerWidget {
  const _TeamsView({required this.municipalityId});
  final String municipalityId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(activeTeamsProvider(municipalityId));
    return teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'No pudimos cargar las cuadrillas.'),
        data: (data) => ListView(padding: const EdgeInsets.all(24), children: [
              const Text('Cuadrillas activas',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17213A))),
              const SizedBox(height: 6),
              const Text('Equipos habilitados para recibir asignaciones.',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              if (data.isEmpty)
                const _EmptyState(
                    icon: Icons.groups_outlined,
                    text: 'No hay cuadrillas activas.')
              else
                Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [for (final t in data) _TeamCard(t)])
            ]));
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard(this.team);
  final TeamModel team;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 300,
      child: Card(
          elevation: 0,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.groups_2_outlined,
                        color: AppColors.brandBlue),
                    const SizedBox(height: 12),
                    Text(team.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: team.categories.isEmpty
                            ? [
                                const Text('Todas las especialidades',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary))
                              ]
                            : team.categories
                                .map((c) => Chip(
                                    label: Text(categoryLabel(c),
                                        style: const TextStyle(fontSize: 10)),
                                    visualDensity: VisualDensity.compact))
                                .toList()),
                  ]))));
}

class _AssignDialog extends ConsumerWidget {
  const _AssignDialog({required this.municipalityId, required this.report});
  final String municipalityId;
  final ReportModel report;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(activeTeamsProvider(municipalityId));
    return AlertDialog(
        title: Text('Asignar: ${report.title}'),
        content: SizedBox(
            width: 420,
            child: teams.when(
                loading: () => const SizedBox(
                    height: 90,
                    child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text(mensajeDeError(e)),
                data: (items) {
                  final sorted = [...items]..sort((a, b) {
                      final am = a.categories.isEmpty ||
                          a.categories.contains(report.category.value);
                      final bm = b.categories.isEmpty ||
                          b.categories.contains(report.category.value);
                      return am == bm
                          ? a.name.compareTo(b.name)
                          : (am ? -1 : 1);
                    });
                  return items.isEmpty
                      ? const Text('No hay cuadrillas activas.')
                      : ListView(shrinkWrap: true, children: [
                          for (final team in sorted)
                            ListTile(
                                leading: Icon(Icons.groups_outlined,
                                    color: (team.categories.isEmpty ||
                                            team.categories.contains(
                                                report.category.value))
                                        ? AppColors.brandGreen
                                        : AppColors.textSecondary),
                                title: Text(team.name),
                                subtitle: Text(team.categories.isEmpty ||
                                        team.categories
                                            .contains(report.category.value)
                                    ? 'Apta para esta categoría'
                                    : 'Otra especialidad'),
                                onTap: () => Navigator.pop(context, team.id))
                        ]);
                })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'))
        ]);
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFE8F7ED),
          borderRadius: BorderRadius.circular(20)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, color: AppColors.brandGreen, size: 9),
        SizedBox(width: 6),
        Text('EN VIVO',
            style: TextStyle(
                fontSize: 10,
                color: Color(0xFF147534),
                fontWeight: FontWeight.w800))
      ]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(45),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary))
      ])));
}

Map<String, int> _statusCounts(List<ReportModel> reports) {
  final values = <String, int>{};
  for (final report in reports) {
    values.update(report.status.value, (v) => v + 1, ifAbsent: () => 1);
  }
  return values;
}
