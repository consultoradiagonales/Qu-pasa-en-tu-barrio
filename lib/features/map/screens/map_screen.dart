import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/repositories/user_repository.dart';
import '../widgets/report_card_bottom_sheet.dart';

// Posición por defecto: Buenos Aires
const _defaultPosition = CameraPosition(
  target: LatLng(-34.6037, -58.3816),
  zoom: 13,
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

  @override
  void initState() {
    super.initState();
    _initLocation();
    _subscribeToReports();
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
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
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 14,
          ),
        ),
      );
    } catch (_) {
      // Falla silenciosa: el mapa queda en la posición por defecto
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
    _reportsSub = repo
        .watchReports(status: _activeFilter)
        .listen((reports) {
      if (mounted) _buildMarkers(reports);
    });
  }

  void _buildMarkers(List<ReportModel> reports) {
    final markers = reports.map((r) {
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
          context.go('/report/${report.id}');
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
    final user = ref.watch(authStateProvider).valueOrNull;
    final userAsync = user != null
        ? ref.watch(StreamProvider((ref) =>
            ref.read(userRepositoryProvider).watchUser(user.uid)))
        : null;
    final isCitizen = userAsync?.valueOrNull?.role == UserRole.citizen ||
        userAsync?.valueOrNull == null;

    return Scaffold(
      body: Stack(
        children: [
          // Mapa
          GoogleMap(
            initialCameraPosition: _defaultPosition,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              _initLocation();
            },
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
        ],
      ),

      // FAB solo para ciudadanos
      floatingActionButton: isCitizen
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/report/new'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Reportar'),
            )
          : null,
    );
  }
}

// ─── Barra de filtros ─────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final ReportStatus? activeFilter;
  final ValueChanged<ReportStatus?> onFilterChanged;

  const _FilterBar({
    required this.activeFilter,
    required this.onFilterChanged,
  });

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
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
