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
import '../../../core/utils/error_text.dart';

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
  bool _sendingUpdate = false;
  late Future<ReportModel?> _reportFuture;
  final _notesCtrl = TextEditingController();
  final _updateCtrl = TextEditingController();

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/field/task/${widget.reportId}');
    }
  }

  @override
  void initState() {
    super.initState();
    _reportFuture = _loadReport();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notesCtrl.dispose();
    _updateCtrl.dispose();
    super.dispose();
  }

  Future<ReportModel?> _loadReport() async {
    final report = await ref
        .read(reportsRepositoryProvider)
        .getReport(widget.reportId)
        .timeout(const Duration(seconds: 20));
    if (!mounted) return report;
    if (report?.workerArrivedAt != null) {
      _arrivedAt = report!.workerArrivedAt;
      _elapsed = DateTime.now().difference(_arrivedAt!);
      _startTimer();
    }
    return report;
  }

  void _retryLoad() {
    _timer?.cancel();
    _timer = null;
    _arrivedAt = null;
    _elapsed = Duration.zero;
    setState(() => _reportFuture = _loadReport());
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
          SnackBar(content: Text(mensajeDeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingExtra = false);
    }
  }

  Future<void> _sendUpdate() async {
    final message = _updateCtrl.text.trim();
    if (message.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribí una novedad para enviar.')),
      );
      return;
    }
    setState(() => _sendingUpdate = true);
    try {
      await ref
          .read(reportsRepositoryProvider)
          .sendReportUpdate(widget.reportId, message);
      _updateCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Novedad enviada al vecino.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeDeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingUpdate = false);
    }
  }

  Future<void> _finishWork() async {
    // Pedir foto del DESPU�?S �?" solo cámara
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

      // Subir foto del DESPU�?S
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
            content: Text('�o. Problema marcado como resuelto.'),
            backgroundColor: AppColors.statusResolved,
          ),
        );
        context.go('/field');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeDeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('field-work-back'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver al detalle',
            onPressed: _goBack,
          ),
          title: const Text('Trabajo en curso'),
          backgroundColor: AppColors.statusInProgress,
        ),
        body: FutureBuilder<ReportModel?>(
          future: _reportFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(mensajeDeError(snapshot.error!)),
                  TextButton(
                      onPressed: _retryLoad, child: const Text('Reintentar')),
                ]),
              );
            }
            if (snapshot.data == null) {
              return const Center(child: Text('Reporte no encontrado.'));
            }
            if (snapshot.data!.status != ReportStatus.inProgress) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('La tarea ya no está en curso.'),
                  TextButton(
                      onPressed: _goBack,
                      child: const Text('Volver al detalle')),
                ]),
              );
            }
            return SingleChildScrollView(
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

                  TextFormField(
                    controller: _updateCtrl,
                    maxLines: 3,
                    maxLength: 280,
                    decoration: const InputDecoration(
                      labelText: 'Novedad para el vecino',
                      hintText: 'Informá una demora, complicación o avance',
                      prefixIcon: Icon(Icons.message_outlined),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _submitting || _sendingUpdate ? null : _sendUpdate,
                    icon: _sendingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: const Text('Enviar novedad al vecino'),
                  ),
                  const SizedBox(height: 16),

                  // Agregar foto durante el trabajo
                  OutlinedButton.icon(
                    onPressed:
                        _submitting || _uploadingExtra ? null : _addExtraPhoto,
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
                    onPressed:
                        _submitting || _uploadingExtra ? null : _finishWork,
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
            );
          },
        ),
      ),
    );
  }
}
