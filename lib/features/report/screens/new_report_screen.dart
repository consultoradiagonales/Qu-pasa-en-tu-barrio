import 'dart:async';
import 'dart:typed_data';
import '../../../core/services/device_profile_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/report_permissions.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/platform_support.dart';
import '../../../core/widgets/locality_autocomplete.dart';
import '../../../core/widgets/municipality_autocomplete.dart';
import '../../../data/models/user_model.dart';
import '../report_flow.dart';
import '../report_insight.dart';
import '../../../data/services/georef_service.dart';

/// Photo -> confirmed location -> optional detail -> server confirmation.
class NewReportScreen extends ConsumerStatefulWidget {
  const NewReportScreen({
    super.key,
    this.startWithCamera = true,
    this.initialAddressMode = false,
    this.initialLocation,
    this.showMap = true,
  });
  final bool startWithCamera;
  final bool initialAddressMode;
  final LatLng? initialLocation;
  final bool showMap;
  @override
  ConsumerState<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends ConsumerState<NewReportScreen> {
  final _comment = TextEditingController();
  final _manualAddress = TextEditingController();
  final _addressFocus = FocusNode();
  final _categoryFocus = FocusNode(debugLabel: 'report-category');
  final _photoReviewFocus = FocusNode();
  final _locationKey = GlobalKey();
  final _addressKey = GlobalKey();
  final _localityKey = GlobalKey();
  final _photoReviewKey = GlobalKey();
  final _categoryKey = GlobalKey();
  final _scroll = ScrollController();
  int _step = 0;
  bool _openingCamera = false, _locating = false, _sending = false;
  bool _showMap = false;
  bool _loadingMunicipalityCenter = false;
  int _municipalityCenterRequest = 0;
  String? _missingField, _defaultProfileKey;
  String? _error, _sentId;
  bool _sentWithAi = false;
  Future<Uint8List>? _preview;
  GoogleMapController? _map;
  GeoRefService get _geoRef => ref.read(reportGeoRefProvider);
  UserModel? get _profile => ref.read(reportProfileProvider).valueOrNull;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _comment.dispose();
    _manualAddress.dispose();
    _addressFocus.dispose();
    _categoryFocus.dispose();
    _photoReviewFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ReportDraft get _draft => ref.read(reportDraftProvider);
  bool get _photoConfirmed => _draft.photoConfirmed;
  void _update(ReportDraft draft) =>
      ref.read(reportDraftProvider.notifier).update(draft);

  String get _municipalityId => _draft.reportsAwayFromHome
      ? _draft.reportMunicipalityId!
      : _profile?.municipalityId ?? '';

  String get _municipalityLabel {
    final name = _draft.reportsAwayFromHome
        ? _draft.reportMunicipalityName
        : _profile?.municipalityName;
    final province =
        _draft.reportsAwayFromHome ? _draft.reportProvince : _profile?.province;
    return [name, province]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
  }

  Future<void> _applyProfileDefault(UserModel? profile) async {
    if (profile == null || profile.municipalityId.trim().isEmpty) return;
    final key = '${profile.uid}:${profile.municipalityId}';
    if (_defaultProfileKey == key) return;
    _defaultProfileKey = key;
    if (_draft.territory.trim().isEmpty) {
      _update(_draft.copyWith(territory: _municipalityLabel));
    }
    if (_draft.location == null) await _loadMunicipalityCenter();
  }

  Future<void> _loadMunicipalityCenter() async {
    final id = _municipalityId;
    if (id.isEmpty || _draft.location != null) return;
    final request = ++_municipalityCenterRequest;
    setState(() => _loadingMunicipalityCenter = true);
    try {
      final center = await _geoRef.municipalityCenter(id);
      if (!mounted ||
          request != _municipalityCenterRequest ||
          id != _municipalityId) {
        return;
      }
      if (center != null && _draft.location == null) {
        _update(_draft.copyWith(
          location: LatLng(center.lat, center.lng),
          usesManualAddress: true,
          locationConfirmed: false,
        ));
      }
    } catch (_) {
      // El municipio sigue elegido; GPS/mapa permiten recuperar la ubicación.
    } finally {
      if (mounted && request == _municipalityCenterRequest) {
        setState(() => _loadingMunicipalityCenter = false);
      }
    }
  }

  void _showMissing(String field, String message, {required int step}) {
    setState(() {
      _step = step;
      _error = message;
      _missingField = field;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final key = switch (field) {
        'address' => _addressKey,
        'locality' => _localityKey,
        'photoReview' => _photoReviewKey,
        'category' => _categoryKey,
        _ => _locationKey,
      };
      final target = key.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(target,
            alignment: .15, duration: const Duration(milliseconds: 250));
      }
      if (!mounted) return;
      switch (field) {
        case 'address':
          _addressFocus.requestFocus();
        case 'category':
          _categoryFocus.requestFocus();
        case 'photoReview':
          _photoReviewFocus.requestFocus();
      }
    });
  }

  String? _fieldError(String field) => _missingField == field ? _error : null;

  void _clearMissing(String field) {
    if (_missingField == field) {
      setState(() {
        _missingField = null;
        _error = null;
      });
    }
  }

  void _confirmLocation() {
    if (_draft.usesManualAddress || _draft.location == null) {
      if (_draft.territory.trim().isEmpty) {
        _showMissing('locality', 'Elegí una ciudad o localidad de la lista.',
            step: 1);
        return;
      }
      if (!_draft.hasManualAddress) {
        _showMissing(
            'address', 'Completá la dirección o una referencia del lugar.',
            step: 1);
        return;
      }
    }
    if (_draft.location == null) {
      _showMissing('location',
          'No pudimos ubicar el lugar. Usá tu ubicación o marcá un punto en el mapa.',
          step: 1);
      return;
    }
    _update(_draft.copyWith(locationConfirmed: true));
    setState(() {
      _step = 2;
      _error = null;
      _missingField = null;
    });
    _scroll.jumpTo(0);
  }

  Future<void> _chooseReportMunicipality() async {
    MunicipalitySuggestion? selected;
    String? validation;
    final choice = await showModalBottomSheet<MunicipalitySuggestion>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 8, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('¿En qué municipio está el problema?',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                    'Este cambio se aplica solo a este reporte. Tu municipio habitual seguirá guardado.'),
                const SizedBox(height: 16),
                MunicipalityAutocomplete(
                  key: const Key('report-other-municipality'),
                  search: _geoRef.searchMunicipalities,
                  onSelected: (value) => updateSheet(() {
                    selected = value;
                    validation = null;
                  }),
                ),
                if (validation != null)
                  Text(validation!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('confirm-report-municipality'),
                  onPressed: () {
                    if (selected == null) {
                      updateSheet(() => validation =
                          'Elegí el municipio de la lista de resultados.');
                    } else {
                      Navigator.pop(sheetContext, selected);
                    }
                  },
                  child: const Text('Usar para este reporte'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final id = 'georef_${choice.id}';
    final home = _profile?.municipalityId ?? '';
    _update(_draft.copyWith(
      reportMunicipalityId: id,
      reportMunicipalityName: choice.name,
      reportProvinceId: choice.provinceId,
      reportProvince: choice.province,
      clearReportMunicipality: id == home,
      territory: choice.label,
      clearLocation: true,
      usesManualAddress: true,
    ));
    setState(() {
      _error = null;
      _missingField = null;
    });
    await _loadMunicipalityCenter();
  }

  Future<void> _useHomeMunicipality() async {
    _update(_draft.copyWith(
        clearReportMunicipality: true,
        clearLocation: true,
        usesManualAddress: true));
    _update(_draft.copyWith(territory: _municipalityLabel));
    await _loadMunicipalityCenter();
  }

  Future<void> _start() async {
    await ref.read(reportDraftProvider.notifier).ready;
    if (!mounted) return;
    _defaultProfileKey = null;
    try {
      final recovered = await ref.read(reportCaptureProvider).recoverPhoto();
      if (recovered != null) {
        _update(
          _draft.copyWith(photoPath: recovered.path, clearLocation: true),
        );
      }
      if (_draft.hasPhoto) {
        try {
          final bytes = await ref
              .read(reportCaptureProvider)
              .readPhoto(_draft.photoPath!);
          _preview = Future.value(bytes);
        } catch (_) {
          await ref.read(reportDraftProvider.notifier).clear();
        }
      }
      if (!mounted) return;
      _comment.text = _draft.comment;
      _manualAddress.text = _draft.address;
      unawaited(_applyProfileDefault(_profile));
      if (widget.initialLocation != null && !_draft.locationConfirmed) {
        _update(_draft.copyWith(location: widget.initialLocation));
      }
      if (_draft.hasPhoto) {
        setState(() => _step = _draft.locationConfirmed ? 2 : 1);
      } else if (widget.startWithCamera) {
        await _camera();
      }
      if (mounted) await DeviceProfileService.askIfNeeded(context);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _camera() async {
    if (_openingCamera || _sending) return;
    setState(() {
      _openingCamera = true;
      _error = null;
    });
    try {
      final photo = await ref.read(reportCaptureProvider).camera();
      if (photo == null || !mounted) return;
      final bytes = await ref.read(reportCaptureProvider).readPhoto(photo.path);
      if (!mounted) return;
      // Foto nueva: hay que volver a confirmarla.
      _update(_draft.copyWith(photoPath: photo.path, photoConfirmed: false));
      _preview = Future.value(bytes);
      setState(() => _step = 1);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<void> _gps() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final location = await ref.read(reportCaptureProvider).gps();
      if (!mounted) return;
      _update(_draft.copyWith(
        location: location,
        locationConfirmed: false,
        usesManualAddress: false,
      ));
      await _map?.animateCamera(CameraUpdate.newLatLng(location));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _markLocation(LatLng point) {
    _update(_draft.copyWith(
      location: point,
      locationConfirmed: false,
      usesManualAddress: false,
    ));
    setState(() => _error = null);
  }

  void _useManualAddress() {
    final address = _manualAddress.text.trim();
    if (_draft.territory.trim().isEmpty) {
      _showMissing('locality', 'Elegí una ciudad o localidad de la lista.',
          step: 1);
      return;
    }
    if (address.length < 2) {
      _showMissing(
          'address', 'Completá la dirección o una referencia del lugar.',
          step: 1);
      return;
    }
    _update(_draft.copyWith(
      address: address,
      usesManualAddress: true,
      locationConfirmed: _draft.location != null,
    ));
    setState(() {
      _error = null;
      _missingField = null;
    });
  }

  void _syncManualAddress(String value) {
    _update(_draft.copyWith(address: value, usesManualAddress: true));
    if (value.trim().length >= 2) _clearMissing('address');
  }

  void _selectLocality(LocalitySuggestion? locality) {
    if (locality == null) {
      _update(_draft.copyWith(territory: ''));
      return;
    }
    _update(_draft.copyWith(
      territory: locality.label,
      usesManualAddress: true,
      location: locality.hasCoordinates
          ? LatLng(locality.latitude!, locality.longitude!)
          : null,
      clearLocation: !locality.hasCoordinates,
      locationConfirmed: false,
    ));
    _clearMissing('locality');
  }

  String _locationDescription(ReportDraft draft) {
    final description = [draft.territory, draft.address]
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');
    return description.isEmpty ? 'Ubicación confirmada' : description;
  }

  Future<bool> _identify() async {
    final service = ref.read(reportSubmitProvider);
    if (service.signedIn) return true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Identificate para enviar',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'La foto y la ubicación quedan guardadas mientras iniciás sesión.',
              ),
              const SizedBox(height: 20),
              if (googleSignInAvailable) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, 'google'),
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continuar con Google'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'email'),
                  child: const Text('Usar correo y contraseña'),
                ),
              ] else
                // Sin Google (iPhone) el correo pasa a ser la acción principal.
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'email'),
                  child: const Text('Continuar con correo y contraseña'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return false;
    if (choice == 'google') {
      await service.loginWithGoogle();
      return service.signedIn;
    }
    if (choice == 'email') context.go('/auth/login?next=report');
    return false;
  }

  /// Evita que un reporte llegue al panel de un municipio con el pin en otro.
  ///
  /// El punto se marca antes de registrarse y el municipio se elige después,
  /// así que pueden no coincidir (en una prueba el punto quedó en La Plata y
  /// el municipio en Azul). Si no coinciden se le pregunta a la persona; se
  /// puede enviar igual porque GeoRef puede errar justo sobre un límite.
  ///
  /// Devuelve true si hay que seguir con el envío. No bloquea nunca cuando no
  /// se puede verificar (sin red, punto fuera de todo municipio) ni cuando se
  /// reportó con dirección escrita y sin punto en el mapa.
  Future<bool> _confirmPointMatchesMunicipality() async {
    final point = _draft.location;
    // En dirección escrita, el centro del municipio sólo es una referencia,
    // no una geocodificación de la calle ni motivo para cambiar el destino.
    if (point == null ||
        (_draft.usesManualAddress && _draft.territory == _municipalityLabel)) {
      return true;
    }

    UserModel? profile;
    GeoRefPlace? found;
    try {
      profile = _profile;
      final mine = _municipalityId.replaceFirst('georef_', '');
      if (mine.isEmpty) return true;
      found = await _geoRef.municipalityAt(point.latitude, point.longitude);
      if (found == null) return true;
      if (found.id == mine) {
        return true;
      }
    } catch (_) {
      // Esta comprobación es una ayuda: si falla por cualquier motivo no
      // puede impedir que se envíe el reporte.
      return true;
    }
    final place = found;
    if (!mounted) return true;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿El lugar es correcto?'),
        content: Text(
          'El punto que marcaste está en ${place.name}, pero el municipio del reporte es '
          '${_municipalityLabel.isEmpty ? 'otro' : _municipalityLabel}. Podés reportar donde estás '
          'sin cambiar el municipio habitual que queda guardado en tu perfil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'point'),
            child: const Text('Corregir el punto'),
          ),
          TextButton(
            key: const Key('report-away-from-home'),
            onPressed: () => Navigator.pop(context, 'away'),
            child: Text('Reportar en ${place.name}'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'home'),
            child: Text(
                'Enviar a ${_municipalityLabel.isEmpty ? 'mi municipio' : _municipalityLabel}'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case 'home':
        return true;
      case 'away':
        final municipality = await _geoRef.municipalityById(place.id);
        _update(_draft.copyWith(
          reportMunicipalityId: 'georef_${place.id}',
          reportMunicipalityName: municipality?.name ?? place.name,
          reportProvinceId: municipality?.provinceId,
          reportProvince: municipality?.province,
          clearReportMunicipality:
              'georef_${place.id}' == profile?.municipalityId,
        ));
        return true;
      case 'point':
        setState(() => _step = 1);
        return false;
      default:
        return false;
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    if (!_draft.hasPhoto) {
      _showMissing('photo', 'Agregá una foto del problema para continuar.',
          step: 0);
      return;
    }
    if (!_draft.locationConfirmed || _draft.location == null) {
      _showMissing('location', 'Completá y confirmá la ubicación del problema.',
          step: 1);
      return;
    }
    if (_draft.usesManualAddress && !_draft.hasManualAddress) {
      _showMissing(
          'address', 'Completá la dirección o una referencia del lugar.',
          step: 1);
      return;
    }
    if (!_photoConfirmed) {
      _showMissing('photoReview', 'Confirmá que la foto muestra el problema.',
          step: 2);
      return;
    }
    if (!_draft.hasCategory) {
      _showMissing(
          'category', 'Elegí el tipo de problema para enviar el reporte.',
          step: 2);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (!await _identify() || !mounted) return;
      if (!await _confirmPointMatchesMunicipality() || !mounted) return;
      final wantsAi = _draft.aiRequested;
      final id = await ref.read(reportSubmitProvider).submit(_draft);
      await ref.read(reportDraftProvider.notifier).clear();
      if (mounted) {
        setState(() {
          _sentId = id;
          _sentWithAi = wantsAi;
        });
      }
    } on MunicipalityRequired {
      if (mounted) context.go('/auth/municipio?next=report');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _newPhoto() async {
    await ref.read(reportDraftProvider.notifier).clear();
    if (!mounted) return;
    _defaultProfileKey = null;
    unawaited(_applyProfileDefault(_profile));
    _comment.clear();
    _manualAddress.clear();
    setState(() {
      _sentId = null;
      _step = 0;
      _preview = null;
      _error = null;
    });
    await _camera();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UserModel?>>(reportProfileProvider, (_, next) {
      final profile = next.valueOrNull;
      if (profile != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_applyProfileDefault(profile));
        });
      }
    });
    ref.watch(reportProfileProvider);
    final draft = ref.watch(reportDraftProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ConDi'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mis reportes y mapa',
            onSelected: (path) => context.go(path),
            itemBuilder: (_) => const [
              PopupMenuItem(value: '/my-reports', child: Text('Mis reportes')),
              PopupMenuItem(value: '/map', child: Text('Mapa del barrio')),
              PopupMenuItem(value: '/profile', child: Text('Mi cuenta')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _sentId != null
                ? _success(context)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Row(
                          children: List.generate(
                            3,
                            (i) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  children: [
                                    LinearProgressIndicator(
                                      value: i <= _step ? 1 : 0,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        '1 · Foto',
                                        '2 · Ubicación',
                                        '3 · Enviar',
                                      ][i],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: i <= _step
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                [
                                  'Mostrá el problema',
                                  '¿Dónde está?',
                                  'Listo para enviar',
                                ][_step],
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  'Sacá una foto para empezar.',
                                  'Escribí la dirección, usá tu ubicación o marcá un punto si preferís.',
                                  'Revisá la foto, elegí una opción y enviá el reporte.',
                                ][_step],
                              ),
                              const SizedBox(height: 18),
                              if (_step == 0) _photoStart(context),
                              if (_step == 0 && _fieldError('photo') != null)
                                _validationNote(_fieldError('photo')!),
                              if (_step == 1) ..._locationStep(context, draft),
                              if (_step == 2) ..._detailsStep(context, draft),
                              if (_error != null && _missingField == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        key: const Key(
                                            'report-validation-message'),
                                        _error!,
                                        style: TextStyle(color: colors.error),
                                      ),
                                      if (_step < 2)
                                        TextButton(
                                          onPressed:
                                              ReportPermissions.openSettings,
                                          child: const Text('Revisar permisos'),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(
                          children: [
                            if (_step > 0)
                              IconButton(
                                tooltip: 'Atrás',
                                icon: const Icon(Icons.arrow_back),
                                onPressed: _sending
                                    ? null
                                    : () => setState(() => _step--),
                              ),
                            if (_step == 1)
                              Expanded(
                                child: FilledButton(
                                  key: const Key('confirm-location'),
                                  onPressed:
                                      _locating || _loadingMunicipalityCenter
                                          ? null
                                          : _confirmLocation,
                                  child: const Text(
                                    'Usar esta ubicación',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (_step == 2)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _sending ? null : _send,
                                  icon: _sending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send_outlined),
                                  label: Text(
                                    _sending ? 'Enviando…' : 'Enviar reporte',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _photoStart(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            const Icon(Icons.add_a_photo_outlined, size: 72),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('take-photo'),
              onPressed: _openingCamera ? null : _camera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_openingCamera ? 'Abriendo cámara…' : 'Sacar foto'),
            ),
          ],
        ),
      );
  Widget _photo({double height = 170}) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: FutureBuilder<Uint8List>(
            future: _preview,
            builder: (context, snapshot) => snapshot.hasData
                ? Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text('Vista previa no disponible')),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
  List<Widget> _locationStep(BuildContext context, ReportDraft draft) => [
        KeyedSubtree(key: _locationKey, child: _photo(height: 130)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _openingCamera ? null : _camera,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Volver a tomar la foto'),
          ),
        ),
        const SizedBox(height: 12),
        if (_fieldError('location') != null)
          _validationNote(_fieldError('location')!),
        if (_municipalityId.isNotEmpty) ...[
          Card(
            key: const Key('report-municipality-summary'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      draft.reportsAwayFromHome
                          ? 'Municipio de este reporte'
                          : 'Tu municipio habitual',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(_municipalityLabel.isEmpty
                      ? _municipalityId
                      : _municipalityLabel),
                  const Text(
                      'Ya está seleccionado. Completá la dirección del problema.'),
                  TextButton.icon(
                    key: const Key('change-report-municipality'),
                    onPressed: _sending ? null : _chooseReportMunicipality,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Reportar en otro municipio'),
                  ),
                  if (draft.reportsAwayFromHome &&
                      (_profile?.municipalityId.isNotEmpty ?? false))
                    TextButton(
                      key: const Key('use-home-municipality'),
                      onPressed: _useHomeMunicipality,
                      child: const Text('Volver a mi municipio habitual'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Dirección manual',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _municipalityId.isEmpty
              ? 'Elegí la ciudad y completá solo los datos de la calle que conozcas.'
              : 'Completá la calle, intersección o referencia. No hace falta volver a elegir el municipio.',
        ),
        const SizedBox(height: 10),
        if (_municipalityId.isEmpty)
          KeyedSubtree(
            key: _localityKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocalityAutocomplete(
                  key: const Key('manual-locality'),
                  initialText: draft.territory,
                  search: _geoRef.searchLocalities,
                  onSelected: _selectLocality,
                ),
                if (_fieldError('locality') != null)
                  _validationNote(_fieldError('locality')!),
              ],
            ),
          ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: _addressKey,
          child: TextField(
            key: const Key('manual-address'),
            controller: _manualAddress,
            focusNode: _addressFocus,
            maxLength: 240,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: true,
            enableSuggestions: true,
            onChanged: _syncManualAddress,
            decoration: InputDecoration(
              labelText: 'Dirección o referencia',
              hintText: 'Ej.: Av. 7 Nº 123, entre 48 y 49, frente a la plaza',
              prefixIcon: const Icon(Icons.signpost_outlined),
              errorText: _fieldError('address'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('use-manual-address'),
            onPressed: _useManualAddress,
            icon: const Icon(Icons.location_searching_outlined),
            label: const Text('Usar dirección manual'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loadingMunicipalityCenter
              ? 'Preparando la referencia de tu municipio…'
              : 'Para la dirección escrita se usa el centro del municipio como referencia aproximada. Podés precisar el punto con GPS o el mapa.',
          style: TextStyle(fontSize: 12),
        ),
        if (draft.usesManualAddress && draft.location == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No pudimos ubicar esa ciudad. Usá tu ubicación o marcá el punto en el mapa.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (widget.showMap) ...[
          const SizedBox(height: 16),
          if (!_showMap)
            OutlinedButton.icon(
              key: const Key('show-map'),
              onPressed: () => setState(() => _showMap = true),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ubicar en el mapa (opcional)'),
            )
          else ...[
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target:
                        draft.location ?? const LatLng(-34.92145, -57.95453),
                    zoom: 16,
                  ),
                  onMapCreated: (controller) => _map = controller,
                  onTap: _markLocation,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  markers: draft.location == null
                      ? {}
                      : {
                          Marker(
                            markerId: const MarkerId('issue'),
                            position: draft.location!,
                            draggable: true,
                            onDragEnd: _markLocation,
                          ),
                        },
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('hide-map'),
                onPressed: () => setState(() => _showMap = false),
                icon: const Icon(Icons.close),
                label: const Text('Cerrar mapa'),
              ),
            ),
          ],
          const Text(
            'El mapa es opcional y puede usar datos móviles.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        if (draft.location != null) ...[
          const SizedBox(height: 8),
          Text(
            '${draft.location!.latitude.toStringAsFixed(5)}, ${draft.location!.longitude.toStringAsFixed(5)}',
          ),
        ],
        TextButton.icon(
          onPressed: _locating ? null : _gps,
          icon: const Icon(Icons.my_location),
          label: Text(_locating ? 'Buscando ubicación…' : 'Usar mi ubicación'),
        ),
      ];

  Widget _validationNote(String text) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
  List<Widget> _detailsStep(BuildContext context, ReportDraft draft) => [
        _photo(),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openingCamera ? null : _camera,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Cambiar foto'),
        ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _photoReviewFocus,
          child: Card(
            key: _photoReviewKey,
            child: CheckboxListTile(
              key: const Key('photo-evidence-confirmed'),
              value: _photoConfirmed,
              onChanged: (value) {
                _update(_draft.copyWith(photoConfirmed: value ?? false));
                if (value == true) _clearMissing('photoReview');
              },
              title: const Text('Confirmo que la foto muestra el problema'),
              subtitle: const Text(
                'No envíes capturas de pantalla ni pantallas de permisos.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        ),
        if (_fieldError('photoReview') != null)
          _validationNote(_fieldError('photoReview')!),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _locationDescription(draft),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Cambiar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: _categoryKey,
          child: DropdownButtonFormField<String>(
            key: const Key('report-category'),
            focusNode: _categoryFocus,
            initialValue: draft.hasCategory ? draft.presetId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Tipo de problema',
              prefixIcon: const Icon(Icons.report_problem_outlined),
              errorText: _fieldError('category'),
            ),
            hint: const Text('Elegí una categoría'),
            items: reportPresets
                .map(
                  (preset) => DropdownMenuItem<String>(
                    value: preset.id,
                    child: Text(
                      preset.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (presetId) {
              if (presetId != null) {
                _update(draft.copyWith(presetId: presetId));
                _clearMissing('category');
              }
            },
          ),
        ),
        if (!draft.hasCategory)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Elegí una categoría para poder enviar el reporte.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('optional-comment'),
          controller: _comment,
          maxLength: AppConstants.maxDescriptionLength,
          minLines: 2,
          maxLines: 4,
          onChanged: (value) => _update(_draft.copyWith(comment: value)),
          decoration: const InputDecoration(
            labelText: 'Comentario (opcional)',
            hintText: 'Agregá un detalle si querés',
          ),
        ),
        SwitchListTile.adaptive(
          key: const Key('ai-consent'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Ayuda de IA de ConDi'),
          subtitle: const Text(
            'Google Gemini interpreta la foto y el comentario para resumir el problema y responderte. Es opcional y puede equivocarse. Tu reporte se envía igual si lo desactivás.',
          ),
          value: draft.aiRequested,
          onChanged: (value) => _update(draft.copyWith(aiRequested: value)),
        ),
      ];
  Widget _success(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          Icon(
            Icons.check_circle,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'Reporte recibido',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          const Text(
            'La foto y la ubicación ya están registradas. Podés seguir el estado en Mis reportes.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_sentWithAi)
            ReportInsightCard(reportId: _sentId!, expected: true),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _newPhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Reportar otro problema'),
          ),
          TextButton(
            onPressed: () => context.go('/my-reports'),
            child: const Text('Ver mis reportes'),
          ),
        ],
      );
}
