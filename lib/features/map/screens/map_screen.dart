import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';

import '../../../data/repositories/reports_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/georef_service.dart';

import '../widgets/report_card_bottom_sheet.dart';

// Posición por defecto: Saladillo, municipio activo de la beta.
const _defaultPosition = CameraPosition(
  target: LatLng(-35.6384, -59.7779),
  zoom: 14,
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  ReportStatus? _activeFilter;
  Set<Marker> _markers = {};
  StreamSubscription? _reportsSub;
  bool _locationPermissionGranted = false;
  bool _pickingReportLocation = false;
  LatLng? _pickedReportLocation;

  @override
  void initState() {
    super.initState();
    _subscribeToReports();
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Abre el mapa en el municipio del vecino. Si no tiene municipio cargado o
  /// GeoRef no responde, queda la posición por defecto de la beta (Saladillo).
  Future<void> _centerOnMunicipality() async {
    final municipalityId = ref.read(currentUserMunicipalityProvider);
    if (municipalityId == null || municipalityId.isEmpty) return;
    final center = await GeoRefService().municipalityCenter(municipalityId);
    if (center == null || !mounted) return;
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(center.lat, center.lng), zoom: center.zoom),
      ),
    );
  }

  Future<void> _initLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        final grant = await _showLocationRationale();
        if (!grant) return;
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      if (!await Geolocator.isLocationServiceEnabled()) return;
      // En Chrome, google_maps_flutter_web ya recibe la ubicación a través de
      // Geolocator. Activar myLocationEnabled después del permiso intenta
      // crear una segunda capa nativa y puede dejar el canvas blanco.
      if (mounted && !_locationPermissionGranted && !kIsWeb) {
        setState(() => _locationPermissionGranted = true);
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 14),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos obtener tu ubicación. Podés elegir el lugar en el mapa.',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _showLocationRationale() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Permiso de ubicación'),
        content: const Text(
          'Usamos tu ubicación para centrar el mapa en tu zona '
          'y facilitar el reporte de problemas cercanos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
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

  void _subscribeToReports() {
    final repo = ref.read(reportsRepositoryProvider);
    _reportsSub?.cancel();
    _reportsSub = repo.watchReports(status: _activeFilter).listen((reports) {
      if (mounted) _buildMarkers(reports);
    });
  }

  void _buildMarkers(List<ReportModel> reports) {
    final markers = reports.where((r) => !r.location.isManualAddress).map((r) {
      final color = _markerHue(r.status);
      return Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.location.lat, r.location.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(color),
        infoWindow: InfoWindow(title: r.title),
        onTap: () => _showReportCard(r),
      );
    }).toSet();

    setState(() => _markers = markers);
  }

  double _markerHue(ReportStatus status) {
    switch (status) {
      case ReportStatus.resolved:
      case ReportStatus.closed:
        return BitmapDescriptor.hueGreen;
      case ReportStatus.inProgress:
        return BitmapDescriptor.hueYellow;
      case ReportStatus.assigned:
        return BitmapDescriptor.hueOrange;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  void _showReportCard(ReportModel report) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReportCardBottomSheet(
        report: report,
        onViewDetail: () {
          Navigator.pop(context);
          context.push('/report/${report.id}');
        },
      ),
    );
  }

  void _setFilter(ReportStatus? status) {
    setState(() => _activeFilter = status);
    _subscribeToReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mapa
          GoogleMap(
            initialCameraPosition: _defaultPosition,
            markers: _markers,
            // Google Maps no permite activar la capa azul antes de que Android
            // conceda el permiso. Hacerlo antes podía dejar el PlatformView
            // negro al volver del diálogo de permisos.
            myLocationEnabled: !kIsWeb && _locationPermissionGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onTap: _pickingReportLocation
                ? (point) => setState(() => _pickedReportLocation = point)
                : null,
            onMapCreated: (c) {
              _mapController = c;
              _centerOnMunicipality();
            },
          ),
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 64,
            child: FloatingActionButton.small(
              heroTag: 'locate-map',
              tooltip: 'Centrar en mi ubicación',
              onPressed: _initLocation,
              child: const Icon(Icons.my_location),
            ),
          ),

          // Filtros en la parte superior
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _FilterBar(
              activeFilter: _activeFilter,
              onFilterChanged: _setFilter,
            ),
          ),
          if (_pickingReportLocation)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pickedReportLocation == null
                            ? 'Tocá el mapa para marcar el problema'
                            : 'Punto seleccionado',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _pickingReportLocation = false),
                            child: const Text('Cancelar'),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: _pickedReportLocation == null
                                ? null
                                : () {
                                    final point = _pickedReportLocation!;
                                    context.go(
                                      '/report/new?lat=${point.latitude}&lng=${point.longitude}&mode=map',
                                    );
                                  },
                            child: const Text('Usar este punto'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),

      // FAB solo para ciudadanos
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/report/new?mode=camera'),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Reportar'),
      ),
    );
  }
}

// ─── Barra de filtros ─────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final ReportStatus? activeFilter;
  final ValueChanged<ReportStatus?> onFilterChanged;

  const _FilterBar({required this.activeFilter, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: AppColors.primary),
            tooltip: 'Menú',
            onSelected: (route) => context.go(route),
            itemBuilder: (_) => const [
              PopupMenuItem(value: '/map', child: Text('Inicio')),
              PopupMenuItem(
                value: '/report/new?mode=camera',
                child: Text('Nuevo reporte con foto'),
              ),
              PopupMenuItem(value: '/my-reports', child: Text('Mis reportes')),
              PopupMenuItem(value: '/profile', child: Text('Perfil')),
            ],
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 8),
              children: [
                _FilterChip(
                  label: 'Todos',
                  isActive: activeFilter == null,
                  color: AppColors.primary,
                  onTap: () => onFilterChanged(null),
                ),
                _FilterChip(
                  label: 'Pendientes',
                  isActive: activeFilter == ReportStatus.pending,
                  color: AppColors.statusPending,
                  onTap: () => onFilterChanged(ReportStatus.pending),
                ),
                _FilterChip(
                  label: 'En curso',
                  isActive: activeFilter == ReportStatus.inProgress,
                  color: AppColors.statusInProgress,
                  onTap: () => onFilterChanged(ReportStatus.inProgress),
                ),
                _FilterChip(
                  label: 'Resueltos',
                  isActive: activeFilter == ReportStatus.resolved,
                  color: AppColors.statusResolved,
                  onTap: () => onFilterChanged(ReportStatus.resolved),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
