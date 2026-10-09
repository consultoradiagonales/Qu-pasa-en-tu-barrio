import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/repositories/reports_repository.dart';

class WorkInProgressScreen extends ConsumerStatefulWidget {
  final String reportId;
  const WorkInProgressScreen({super.key, required this.reportId});

  @override
  ConsumerState<WorkInProgressScreen> createState() =>
      _WorkInProgressScreenState();
}

class _WorkInProgressScreenState extends ConsumerState<WorkInProgressScreen> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _arrivedAt;
  bool _submitting = false;
  bool _uploadingExtra = false;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    final report = await ref
        .read(reportsRepositoryProvider)
        .getReport(widget.reportId);
    if (!mounted) return;
    if (report?.workerArrivedAt != null) {
      _arrivedAt = report!.workerArrivedAt;
      _elapsed = DateTime.now().difference(_arrivedAt!);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_arrivedAt != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_arrivedAt!);
        });
      }
    });
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _addExtraPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() => _uploadingExtra = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);
      final url = await repo.uploadFieldPhoto(
        reportId: widget.reportId,
        file: File(photo.path),
        phase: 'progress',
      );
      await repo.updateReport(widget.reportId, {
        'photosProgress': FieldValue.arrayUnion([url]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto del proceso guardada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingExtra = false);
    }
  }

  Future<void> _finishWork() async {
    // Pedir foto del DESPUÉS — solo cámara
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto del resultado'),
        content: const Text(
          'Tomá una foto del estado final del problema, '
          'mostrando que fue resuelto.',
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

    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera, // SOLO cámara, no galería
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      final repo = ref.read(reportsRepositoryProvider);

      // Subir foto del DESPUÉS
      final afterUrl = await repo.uploadFieldPhoto(
        reportId: widget.reportId,
        file: File(photo.path),
        phase: 'after',
      );

      // Actualizar reporte como resuelto
      await repo.updateReport(widget.reportId, {
        'status': ReportStatus.resolved.value,
        'photosAfter': [afterUrl],
        'workFinishedAt': FieldValue.serverTimestamp(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'workerNotes': _notesCtrl.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Problema marcado como resuelto.'),
            backgroundColor: AppColors.statusResolved,
          ),
        );
        context.go('/field');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cerrar la tarea: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trabajo en curso'),
        backgroundColor: AppColors.statusInProgress,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cronómetro
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: AppColors.statusInProgress.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 40, color: AppColors.statusInProgress),
                  const SizedBox(height: 8),
                  Text(
                    _elapsedLabel,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.statusInProgress,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text(
                    'tiempo en el lugar',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Nota del técnico
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Nota del técnico (opcional)',
                hintText: 'Describí brevemente lo que se hizo',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Agregar foto durante el trabajo
            OutlinedButton.icon(
              onPressed: _submitting || _uploadingExtra ? null : _addExtraPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Foto del proceso (opcional)'),
            ),
            const SizedBox(height: 32),

            // Botón "Trabajo terminado"
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusResolved,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _submitting || _uploadingExtra ? null : _finishWork,
              icon: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text(
                'Trabajo terminado',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
