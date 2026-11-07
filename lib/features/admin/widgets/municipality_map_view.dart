import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/report_model.dart';

const _fallbackMapPosition = CameraPosition(
  target: LatLng(-35.6384, -59.7779),
  zoom: 13,
);

class MunicipalityMapView extends StatefulWidget {
  const MunicipalityMapView({super.key, required this.reports});

  final List<ReportModel> reports;

  @override
  State<MunicipalityMapView> createState() => _MunicipalityMapViewState();
}

class _MunicipalityMapViewState extends State<MunicipalityMapView> {
  GoogleMapController? _mapController;
  ReportStatus? _status;
  bool _onlyOpen = false;
  bool _framed = false;
  String? _selectedZone;

  List<ReportModel> get _visibleReports => widget.reports.where((report) {
        final matchesStatus = _status == null || report.status == _status;
        final isOpen = !{
          ReportStatus.resolved,
          ReportStatus.closed,
          ReportStatus.rejected,
        }.contains(report.status);
        return matchesStatus && (!_onlyOpen || isOpen);
      }).toList();

  List<ReportModel> get _mapReports =>
      _visibleReports.where((report) => !report.location.isManualAddress).toList();

  List<_MapZone> get _zones => _groupReports(_mapReports);

  @override
  void didUpdateWidget(covariant MunicipalityMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_framed && oldWidget.reports.isEmpty && widget.reports.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _frameReports());
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _frameReports() async {
    final controller = _mapController;
    final reports = _mapReports;
    if (controller == null || reports.isEmpty) return;
    _framed = true;
    if (reports.length == 1) {
      final point = reports.first.location.latLng;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 15)),
      );
      return;
    }
    var south = reports.first.location.lat;
    var north = south;
    var west = reports.first.location.lng;
    var east = west;
    for (final report in reports.skip(1)) {
      south = report.location.lat < south ? report.location.lat : south;
      north = report.location.lat > north ? report.location.lat : north;
      west = report.location.lng < west ? report.location.lng : west;
      east = report.location.lng > east ? report.location.lng : east;
    }
    if ((north - south).abs() < .0001 && (east - west).abs() < .0001) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(north, east), zoom: 15),
        ),
      );
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        56,
      ),
    );
  }

  void _setStatus(ReportStatus? value) {
    setState(() {
      _status = value;
      if (value == ReportStatus.resolved || value == ReportStatus.closed) {
        _onlyOpen = false;
      }
    });
  }

  void _focusZone(_MapZone zone) {
    setState(() => _selectedZone = zone.key);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
            target: zone.center, zoom: zone.reports.length == 1 ? 16 : 14),
      ),
    );
  }

  void _showZoneReports(_MapZone zone) {
    setState(() => _selectedZone = zone.key);
    final reports = [...zone.reports]..sort((a, b) {
        final priority = b.priority.compareTo(a.priority);
        return priority != 0 ? priority : b.createdAt.compareTo(a.createdAt);
      });
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(
                  '${zone.reports.length} reportes en la zona',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final report = reports[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _statusColor(report.status).withOpacity(.14),
                        child: Icon(
                          _statusIcon(report.status),
                          color: _statusColor(report.status),
                          size: 20,
                        ),
                      ),
                      title: Text(report.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${categoryLabel(report.category.value)} · prioridad ${report.priority}/5 · ${statusLabel(report.status.value)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        context.push('/report/${report.id}');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Set<Marker> _markers(List<_MapZone> zones) => zones.map((zone) {
        final single = zone.reports.length == 1;
        final report = single ? zone.reports.first : null;
        return Marker(
          markerId: MarkerId(single ? report!.id : 'zone-${zone.key}'),
          position: zone.center,
          icon: BitmapDescriptor.defaultMarkerWithHue(_markerHue(zone)),
          infoWindow: InfoWindow(
            title: single
                ? report!.title
                : '${zone.reports.length} reportes concentrados',
            snippet: single
                ? '${statusLabel(report!.status.value)} · prioridad ${report.priority}/5'
                : '${zone.active} abiertos · ${zone.highPriority} de prioridad alta',
          ),
          onTap: () => _showZoneReports(zone),
        );
      }).toSet();

  Set<Circle> _circles(List<_MapZone> zones) =>
      zones.where((zone) => zone.reports.length > 1).map((zone) {
        final color = _zoneColor(zone);
        return Circle(
          circleId: CircleId('zone-${zone.key}'),
          center: zone.center,
          radius:
              (330 + (zone.reports.length > 18 ? 18 : zone.reports.length) * 45)
                  .toDouble(),
          fillColor: color.withOpacity(.16),
          strokeColor: color.withOpacity(.72),
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => _showZoneReports(zone),
        );
      }).toSet();

  @override
  Widget build(BuildContext context) {
    final zones = _zones;
    final reports = _mapReports;
    final manualAddressCount = _visibleReports.length - reports.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final map = _MapCanvas(
          zones: zones,
          reports: reports,
          selectedZone: _selectedZone,
          markers: _markers(zones),
          circles: _circles(zones),
          onMapCreated: (controller) {
            _mapController = controller;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _frameReports());
          },
          status: _status,
          onlyOpen: _onlyOpen,
          manualAddressCount: manualAddressCount,
          onStatusChanged: _setStatus,
          onOnlyOpenChanged: (value) => setState(() => _onlyOpen = value),
          onFrame: _frameReports,
        );
        final zonesPanel = _ZonesPanel(
          zones: zones,
          selectedZone: _selectedZone,
          onFocus: _focusZone,
          onOpen: _showZoneReports,
        );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: map),
                const SizedBox(width: 16),
                SizedBox(width: 330, child: zonesPanel),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(height: 470, child: map),
            const SizedBox(height: 14),
            zonesPanel,
          ],
        );
      },
    );
  }
}

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({
    required this.zones,
    required this.reports,
    required this.selectedZone,
    required this.markers,
    required this.circles,
    required this.onMapCreated,
    required this.status,
    required this.onlyOpen,
    required this.manualAddressCount,
    required this.onStatusChanged,
    required this.onOnlyOpenChanged,
    required this.onFrame,
  });

  final List<_MapZone> zones;
  final List<ReportModel> reports;
  final String? selectedZone;
  final Set<Marker> markers;
  final Set<Circle> circles;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ReportStatus? status;
  final bool onlyOpen;
  final int manualAddressCount;
  final ValueChanged<ReportStatus?> onStatusChanged;
  final ValueChanged<bool> onOnlyOpenChanged;
  final VoidCallback onFrame;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: _fallbackMapPosition,
              markers: markers,
              circles: circles,
              mapToolbarEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: onMapCreated,
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white.withOpacity(.96),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 19),
                          SizedBox(width: 6),
                          Text(
                            'Mapa operativo en vivo',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      Text('${reports.length} visibles',
                          style: const TextStyle(fontSize: 12)),
                      if (manualAddressCount > 0)
                        Text(
                          '$manualAddressCount con dirección escrita',
                          style: const TextStyle(fontSize: 12),
                        ),
                      DropdownButton<ReportStatus?>(
                        value: status,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<ReportStatus?>(
                            value: null,
                            child: Text('Todos los estados'),
                          ),
                          ...ReportStatus.values.map(
                            (item) => DropdownMenuItem<ReportStatus?>(
                              value: item,
                              child: Text(statusLabel(item.value)),
                            ),
                          ),
                        ],
                        onChanged: onStatusChanged,
                      ),
                      FilterChip(
                        selected: onlyOpen,
                        label: const Text('Solo abiertos'),
                        onSelected: onOnlyOpenChanged,
                      ),
                      IconButton(
                        tooltip: 'Ver todos los reportes en el mapa',
                        onPressed: reports.isEmpty ? null : onFrame,
                        icon: const Icon(Icons.center_focus_strong),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Card(
                color: Colors.white.withOpacity(.96),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(
                          color: AppColors.statusPending, label: 'Pendiente'),
                      SizedBox(width: 10),
                      _LegendDot(
                          color: AppColors.statusAssigned, label: 'En gestión'),
                      SizedBox(width: 10),
                      _LegendDot(
                          color: AppColors.statusResolved, label: 'Resuelto'),
                    ],
                  ),
                ),
              ),
            ),
            if (reports.isEmpty)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No hay ubicaciones precisas con este filtro.'),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ZonesPanel extends StatelessWidget {
  const _ZonesPanel({
    required this.zones,
    required this.selectedZone,
    required this.onFocus,
    required this.onOpen,
  });

  final List<_MapZone> zones;
  final String? selectedZone;
  final ValueChanged<_MapZone> onFocus;
  final ValueChanged<_MapZone> onOpen;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Concentración de reportes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Las zonas se actualizan con cada reporte nuevo o cambio de estado.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (zones.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('Sin zonas para mostrar.')),
                )
              else
                for (var index = 0; index < zones.length; index++)
                  _ZoneTile(
                    zone: zones[index],
                    rank: index + 1,
                    selected: zones[index].key == selectedZone,
                    onFocus: () => onFocus(zones[index]),
                    onOpen: () => onOpen(zones[index]),
                  ),
            ],
          ),
        ),
      );
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({
    required this.zone,
    required this.rank,
    required this.selected,
    required this.onFocus,
    required this.onOpen,
  });

  final _MapZone zone;
  final int rank;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor(zone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? color.withOpacity(.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onFocus,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: color.withOpacity(.16),
                  child: Text('$rank',
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${zone.reports.length} reportes · ${zone.active} abiertos',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${categoryLabel(zone.leadingCategory)} · ${zone.highPriority} prioridad alta',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ver reportes de la zona',
                  onPressed: onOpen,
                  icon: const Icon(Icons.list_alt_outlined, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      );
}

class _MapZone {
  _MapZone(this.key);

  final String key;
  final List<ReportModel> reports = [];
  double _latTotal = 0;
  double _lngTotal = 0;

  void add(ReportModel report) {
    reports.add(report);
    _latTotal += report.location.lat;
    _lngTotal += report.location.lng;
  }

  LatLng get center =>
      LatLng(_latTotal / reports.length, _lngTotal / reports.length);

  int get active => reports
      .where((report) => !{
            ReportStatus.resolved,
            ReportStatus.closed,
            ReportStatus.rejected,
          }.contains(report.status))
      .length;

  int get highPriority => reports.where((report) {
        final closed = {
          ReportStatus.resolved,
          ReportStatus.closed,
          ReportStatus.rejected,
        }.contains(report.status);
        return !closed && report.priority >= 4;
      }).length;

  String get leadingCategory {
    final values = <String, int>{};
    for (final report in reports) {
      values.update(report.category.value, (value) => value + 1,
          ifAbsent: () => 1);
    }
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.isEmpty ? 'other' : entries.first.key;
  }
}

List<_MapZone> _groupReports(List<ReportModel> reports) {
  final zones = <String, _MapZone>{};
  for (final report in reports) {
    if (report.location.isManualAddress) continue;
    final latitude = report.location.lat;
    final longitude = report.location.lng;
    if (!latitude.isFinite || !longitude.isFinite) continue;
    final key = '${(latitude / .006).floor()}:${(longitude / .006).floor()}';
    final zone = zones.putIfAbsent(key, () => _MapZone(key));
    zone.add(report);
  }
  final values = zones.values.toList()
    ..sort((a, b) {
      final scoreA = a.active * 5 + a.highPriority * 4 + a.reports.length;
      final scoreB = b.active * 5 + b.highPriority * 4 + b.reports.length;
      return scoreB.compareTo(scoreA);
    });
  return values;
}

Color _statusColor(ReportStatus status) {
  switch (status) {
    case ReportStatus.resolved:
    case ReportStatus.closed:
      return AppColors.statusResolved;
    case ReportStatus.assigned:
      return AppColors.statusAssigned;
    case ReportStatus.inProgress:
      return AppColors.statusInProgress;
    case ReportStatus.rejected:
      return AppColors.textSecondary;
    case ReportStatus.pending:
      return AppColors.statusPending;
  }
}

IconData _statusIcon(ReportStatus status) {
  switch (status) {
    case ReportStatus.resolved:
    case ReportStatus.closed:
      return Icons.check_circle_outline;
    case ReportStatus.assigned:
      return Icons.assignment_outlined;
    case ReportStatus.inProgress:
      return Icons.engineering_outlined;
    case ReportStatus.rejected:
      return Icons.block_outlined;
    case ReportStatus.pending:
      return Icons.priority_high_outlined;
  }
}

Color _zoneColor(_MapZone zone) {
  if (zone.highPriority > 0) return AppColors.statusPending;
  if (zone.active > 0) return AppColors.statusAssigned;
  return AppColors.statusResolved;
}

double _markerHue(_MapZone zone) {
  if (zone.highPriority > 0) return BitmapDescriptor.hueRed;
  if (zone.active > 0) return BitmapDescriptor.hueOrange;
  return BitmapDescriptor.hueGreen;
}
