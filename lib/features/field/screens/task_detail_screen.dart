import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/services/auth_service.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const TaskDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _uploading = false;

  Future<void> _navigateToLocation(ReportModel r) async {
    final lat = r.location.lat;
    final lng = r.location.lng;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir Google Maps.')),
        );
      }
    }
  }

  Future<void> _arrivedOnSite(ReportModel report) async {
    // Explicar qué foto se va a tomar
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto del estado actual'),
        content: const Text(
          'Por favor tomá una foto del estado actual del problema, '
          'antes de comenzar el trabajo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir cámara'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Foto SOLO con cámara — no galería
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);
      final uid = ref.read(authStateProvider).valueOrNull?.uid ?? '';

      // Subir foto del ANTES
      final url = await repo.uploadFieldPhoto(
        reportId: report.id,
        file: File(photo.path),
        phase: 'before',
      );

      // Actualizar reporte
      await repo.updateReport(report.id, {
        'status': ReportStatus.inProgress.value,
        'workerArrivedAt': FieldValue.serverTimestamp(),
        'workStartedAt': FieldValue.serverTimestamp(),
        'assignedWorkerId': uid,
        'photosBefore': [url],
      });

      if (mounted) {
        context.go('/field/task/${report.id}/work');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir la foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(
      FutureProvider((ref) =>
          ref.read(reportsRepositoryProvider).getReport(widget.reportId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de tarea')),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (report) {
          if (report == null) {
            return const Center(child: Text('Reporte no encontrado.'));
          }
          return _buildBody(report);
        },
      ),
    );
  }

  Widget _buildBody(ReportModel report) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Estado y categoría
          Row(
            children: [
              _Chip(
                label: statusLabel(report.status.value),
                color: statusColor(report.status.value),
              ),
              const SizedBox(width: 8),
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Descripción
          Text(report.description),
          const SizedBox(height: 16),

          // Fotos del ciudadano
          if (report.photosReport.isNotEmpty) ...[
            const Text('Fotos del reporte',
                style: TextStyle(fontWeight: FontWeight.w600)),
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
          Container(
            height: 180,
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
                    markerId: const MarkerId('report'),
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
          const SizedBox(height: 24),

          // Botones de acción
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
            ),
            onPressed: () => _navigateToLocation(report),
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Navegar al lugar'),
          ),
          const SizedBox(height: 12),

          if (report.status == ReportStatus.assigned)
            ElevatedButton.icon(
              onPressed: _uploading ? null : () => _arrivedOnSite(report),
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.pin_drop_outlined),
              label: const Text('Estoy en el lugar'),
            ),

          if (report.status == ReportStatus.inProgress)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusInProgress),
              onPressed: () => context.go('/field/task/${report.id}/work'),
              icon: const Icon(Icons.engineering_outlined),
              label: const Text('Continuar trabajo en curso'),
            ),
        ],
      ),
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
