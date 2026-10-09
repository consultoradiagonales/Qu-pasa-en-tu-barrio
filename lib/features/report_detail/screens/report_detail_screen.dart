import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/services/auth_service.dart';
import '../widgets/before_after_slider_widget.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<ReportDetailScreen> createState() =>
      _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  bool _voting = false;
  bool _flagging = false;

  Future<void> _toggleSupport(ReportModel report) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    setState(() => _voting = true);
    try {
      await ref
          .read(reportsRepositoryProvider)
          .addSupportVote(report.id, uid);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _flagReport(ReportModel report) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _FlagDialog(),
    );
    if (reason == null || !mounted) return;

    setState(() => _flagging = true);
    try {
      await ref
          .read(reportsRepositoryProvider)
          .flagContent(
            reportedBy: uid,
            targetType: 'report',
            targetId: report.id,
            reportId: report.id,
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reporte enviado al moderador.')),
        );
      }
    } finally {
      if (mounted) setState(() => _flagging = false);
    }
  }

  Future<void> _rateReport(ReportModel report) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    if (report.status != ReportStatus.resolved &&
        report.status != ReportStatus.closed) return;

    int? rating;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RatingSheet(
        onRate: (r) {
          rating = r;
          Navigator.pop(context);
        },
      ),
    );

    if (rating == null) return;
    await ref.read(reportsRepositoryProvider).updateReport(report.id, {
      'rating': rating,
    });
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(
      FutureProvider((ref) =>
          ref.read(reportsRepositoryProvider).getReport(widget.reportId)),
    );
    final uid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del reporte'),
        actions: [
          reportAsync.whenData((r) {
            if (r == null) return const SizedBox.shrink();
            return IconButton(
              icon: _flagging
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.flag_outlined),
              tooltip: 'Reportar contenido',
              onPressed: () => _flagReport(r),
            );
          }).value ??
              const SizedBox.shrink(),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (report) {
          if (report == null) {
            return const Center(child: Text('Reporte no encontrado.'));
          }
          return _buildBody(report, uid);
        },
      ),
    );
  }

  Widget _buildBody(ReportModel report, String uid) {
    final hasBeforeAfter =
        report.photosBefore.isNotEmpty && report.photosAfter.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chips de estado y categoría
          Wrap(
            spacing: 8,
            children: [
              _Chip(
                label: statusLabel(report.status.value),
                color: statusColor(report.status.value),
              ),
              _Chip(
                label: categoryLabel(report.category.value),
                color: categoryColor(report.category.value),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Título
          Text(
            report.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),

          // Dirección y tiempo
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  report.location.address ?? 'Ubicación en el mapa',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeago.format(report.createdAt, locale: 'es'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Descripción
          Text(report.description, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 16),

          // ── SLIDER ANTES/DESPUÉS ──────────────────────────────
          if (hasBeforeAfter) ...[
            const _SectionTitle(text: 'Evolución del problema'),
            const SizedBox(height: 8),
            BeforeAfterSliderWidget(
              urlBefore: report.photosBefore.first,
              urlAfter: report.photosAfter.first,
            ),
            const SizedBox(height: 16),
          ],

          // Fotos del ciudadano
          if (report.photosReport.isNotEmpty) ...[
            const _SectionTitle(text: 'Fotos del reporte'),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.photosReport.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: report.photosReport[i],
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mini mapa
          if (report.photosProgress.isNotEmpty) ...[
            const _SectionTitle(text: 'Fotos del proceso'),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.photosProgress.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: report.photosProgress[i],
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          const _SectionTitle(text: 'Ubicación'),
          const SizedBox(height: 8),
          Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(report.location.lat, report.location.lng),
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('r'),
                    position:
                        LatLng(report.location.lat, report.location.lng),
                  ),
                },
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                zoomGesturesEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nota del técnico
          if (report.workerNotes != null &&
              report.workerNotes!.isNotEmpty) ...[
            const _SectionTitle(text: 'Respuesta oficial'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(report.workerNotes!,
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Acciones: apoyo y calificación
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _voting ? null : () => _toggleSupport(report),
                  icon: _voting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.thumb_up_outlined),
                  label: Text('${report.supportCount} apoyos'),
                ),
              ),
              const SizedBox(width: 12),
              if (uid == report.userId &&
                  (report.status == ReportStatus.resolved ||
                      report.status == ReportStatus.closed))
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent),
                    onPressed: () => _rateReport(report),
                    icon: const Icon(Icons.star_outline),
                    label: Text(report.rating != null
                        ? '${report.rating}/5'
                        : 'Calificar'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Volver al mapa
          TextButton.icon(
            onPressed: () => context.go('/map'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver en el mapa'),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FlagDialog extends StatefulWidget {
  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
  String _reason = 'Contenido inapropiado';

  @override
  Widget build(BuildContext context) {
    const options = [
      'Contenido inapropiado',
      'Información falsa',
      'Spam',
      'Otro',
    ];
    return AlertDialog(
      title: const Text('Reportar contenido'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options
            .map((o) => RadioListTile<String>(
                  title: Text(o),
                  value: o,
                  groupValue: _reason,
                  onChanged: (v) => setState(() => _reason = v!),
                  dense: true,
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _reason),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _RatingSheet extends StatefulWidget {
  final void Function(int) onRate;
  const _RatingSheet({required this.onRate});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('¿Qué tan bien se resolvió el problema?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    i < _stars ? Icons.star : Icons.star_border,
                    color: AppColors.accent,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _stars > 0 ? () => widget.onRate(_stars) : null,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('Enviar calificación'),
          ),
        ],
      ),
    );
  }
}
