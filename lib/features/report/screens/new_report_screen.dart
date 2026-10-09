import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class NewReportScreen extends ConsumerStatefulWidget {
  const NewReportScreen({super.key});

  @override
  ConsumerState<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends ConsumerState<NewReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  ReportCategory _category = ReportCategory.infrastructure;
  List<XFile> _photos = [];
  LatLng? _location;
  bool _loading = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _getGps();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _getGps() async {
    setState(() => _locating = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Mostrar rationale antes de pedir
        final granted = await _showLocationRationale();
        if (!granted) return;
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) setState(() => _location = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // Si falla, el usuario puede elegir manualmente
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<bool> _showLocationRationale() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permiso de ubicación'),
        content: const Text(
          'Necesitamos tu ubicación para marcar el problema en el mapa. '
          'Podés ajustarla manualmente si preferís.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pickPhotos() async {
    if (_photos.length >= AppConstants.maxPhotosPerReport) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Máximo ${AppConstants.maxPhotosPerReport} fotos por reporte.',
          ),
        ),
      );
      return;
    }

    // Rationale para cámara/galería
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar foto'),
        content: const Text('Tomá una foto del problema o seleccioná una de tu galería.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final file = await ImagePicker()
                  .pickImage(source: ImageSource.camera, imageQuality: 85);
              if (file != null && mounted) {
                setState(() => _photos.add(file));
              }
            },
            child: const Text('Cámara'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final files = await ImagePicker().pickMultiImage(imageQuality: 85);
              if (files.isNotEmpty && mounted) {
                setState(() {
                  _photos.addAll(files);
                  if (_photos.length > AppConstants.maxPhotosPerReport) {
                    _photos = _photos.sublist(0, AppConstants.maxPhotosPerReport);
                  }
                });
              }
            },
            child: const Text('Galería'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor marcá la ubicación del problema.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) return;

      // Verificar rate limit
      final userModel = await ref.read(userRepositoryProvider).getUser(user.uid);
      if (userModel?.lastReportAt != null) {
        final diff = DateTime.now().difference(userModel!.lastReportAt!);
        if (diff.inHours < 24) {
          final reportsRepo = ref.read(reportsRepositoryProvider);
          final count = await reportsRepo.countUserReportsToday(user.uid);
          if (count >= AppConstants.maxReportsPerDay) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Alcanzaste el límite de 10 reportes por día.'),
                ),
              );
            }
            return;
          }
        }
      }

      // Comprimir y subir fotos
      final reportsRepo = ref.read(reportsRepositoryProvider);
      List<File> compressed = [];
      for (final xf in _photos) {
        final result = await FlutterImageCompress.compressAndGetFile(
          xf.path,
          '${xf.path}_compressed.jpg',
          minWidth: AppConstants.maxImagePixels,
          minHeight: AppConstants.maxImagePixels,
          quality: 80,
        );
        if (result != null) compressed.add(File(result.path));
      }

      // Calcular geohash
      final geoPoint = GeoFirePoint(GeoPoint(
        _location!.latitude,
        _location!.longitude,
      ));

      final reportId = const Uuid().v4();
      final photoUrls = await reportsRepo.uploadReportPhotos(
        reportId: reportId,
        files: compressed,
      );

      final report = ReportModel(
        id: reportId,
        userId: user.uid,
        municipalityId: userModel?.municipalityId ?? 'default',
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _category,
        photosReport: photoUrls,
        location: ReportLocation(
          lat: _location!.latitude,
          lng: _location!.longitude,
          geohash: geoPoint.geohash,
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await reportsRepo.createReport(report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reporte enviado. Podés seguir su estado en Mis reportes.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/my-reports');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar el reporte: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar problema')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Título
              TextFormField(
                controller: _titleCtrl,
                maxLength: AppConstants.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'Título del problema *',
                  hintText: 'Ej: Pozo en la calzada',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá un título';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Descripción
              TextFormField(
                controller: _descCtrl,
                maxLength: AppConstants.maxDescriptionLength,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción *',
                  hintText: 'Describí el problema con detalle',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá una descripción';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Categoría
              DropdownButtonFormField<ReportCategory>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoría *',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: ReportCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: categoryColor(cat.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(categoryLabel(cat.value)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 16),

              // Fotos
              Text(
                'Fotos (${_photos.length}/${AppConstants.maxPhotosPerReport})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Botón agregar
                    GestureDetector(
                      onTap: _pickPhotos,
                      child: Container(
                        width: 90,
                        height: 90,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.background,
                        ),
                        child: const Icon(Icons.add_a_photo_outlined,
                            size: 32, color: AppColors.primary),
                      ),
                    ),
                    // Fotos seleccionadas
                    ..._photos.map((xf) => Stack(
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: FileImage(File(xf.path)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _photos.remove(xf)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Ubicación
              Text(
                'Ubicación *',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.background,
                ),
                child: Row(
                  children: [
                    Icon(
                      _location != null
                          ? Icons.location_on
                          : Icons.location_off,
                      color: _location != null
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _locating
                          ? const Text('Obteniendo ubicación...')
                          : _location != null
                              ? Text(
                                  '${_location!.latitude.toStringAsFixed(5)}, '
                                  '${_location!.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(fontSize: 13),
                                )
                              : const Text('Ubicación no disponible'),
                    ),
                    TextButton(
                      onPressed: _getGps,
                      child: const Text('Usar GPS'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Botón enviar
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: const Text('Enviar reporte'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
