import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/report_permissions.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/platform_support.dart';
import '../../../core/widgets/municipality_autocomplete.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
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
  final _address = TextEditingController();
  int _step = 0;
  bool _openingCamera = false,
      _locating = false,
      _sending = false;
  bool _showMap = false;
  String? _error, _sentId;
  bool _sentWithAi = false;
  Future<Uint8List>? _preview;
  GoogleMapController? _map;
  final _geoRef = GeoRefService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _comment.dispose();
    _address.dispose();
    super.dispose();
  }

  ReportDraft get _draft => ref.read(reportDraftProvider);
  bool get _photoConfirmed => _draft.photoConfirmed;
  void _update(ReportDraft draft) =>
      ref.read(reportDraftProvider.notifier).update(draft);
  Future<void> _start() async {
    await ref.read(reportDraftProvider.notifier).ready;
    if (!mounted) return;
    try {
      final recovered = await ref.read(reportCaptureProvider).recoverPhoto();
      if (recovered != null)
        _update(
          _draft.copyWith(photoPath: recovered.path, clearLocation: true),
        );
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
      _address.text = _draft.address;
      if (widget.initialLocation != null && !_draft.locationConfirmed) {
        _update(_draft.copyWith(location: widget.initialLocation));
      }
      if (_draft.hasPhoto) {
        setState(() => _step = _draft.locationConfirmed ? 2 : 1);
      } else if (widget.startWithCamera) {
        await _camera();
      }
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
    final address = _address.text.trim();
    if (address.length < 4) {
      setState(() => _error =
          'Escribí una dirección o referencia de al menos 4 caracteres.');
      return;
    }
    _update(_draft.copyWith(
      address: address,
      clearLocation: true,
      usesManualAddress: true,
    ));
    setState(() => _error = null);
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
    if (point == null) return true;

    UserModel? profile;
    GeoRefPlace? found;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return true;
      profile = await ref.read(userRepositoryProvider).getUser(uid);
      final mine = (profile?.municipalityId ?? '').replaceFirst('georef_', '');
      if (mine.isEmpty) return true;
      found = await _geoRef.municipalityAt(point.latitude, point.longitude);
      if (found == null || found.id == mine) return true;
    } catch (_) {
      // Esta comprobación es una ayuda: si falla por cualquier motivo no
      // puede impedir que se envíe el reporte.
      return true;
    }
    final place = found;
    if (place == null || !mounted) return true;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿El lugar es correcto?'),
        content: Text(
          'El punto que marcaste está en ${place.name}, pero tu municipio es '
          '${profile?.municipalityName ?? 'otro'}. El reporte le llegaría a '
          '${profile?.municipalityName ?? 'ese municipio'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'point'),
            child: const Text('Corregir el punto'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'municipality'),
            child: Text('Mi municipio es ${place.name}'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'send'),
            child: const Text('Enviar igual'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case 'send':
        return true;
      case 'municipality':
        context.go('/auth/municipio?next=report');
        return false;
      case 'point':
        setState(() => _step = 1);
        return false;
      default:
        return false;
    }
  }

  Future<void> _send() async {
    if (_sending || !_draft.canSend || !_photoConfirmed) return;
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
      if (mounted)
        setState(() {
          _sentId = id;
          _sentWithAi = wantsAi;
        });
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
    _comment.clear();
    _address.clear();
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
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                            if (_step == 1) ..._locationStep(context, draft),
                            if (_step == 2) ..._detailsStep(context, draft),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
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
                                  onPressed: (draft.location == null &&
                                              !(draft.usesManualAddress &&
                                                  draft.hasManualAddress)) ||
                                          _locating
                                      ? null
                                      : () {
                                          _update(
                                            draft.copyWith(
                                              locationConfirmed: true,
                                            ),
                                          );
                                          setState(() {
                                            _step = 2;
                                            _error = null;
                                          });
                                        },
                                  child: Text(
                                    draft.usesManualAddress &&
                                            draft.location == null
                                        ? 'Usar dirección escrita'
                                        : 'Usar esta ubicación',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (_step == 2)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _sending || !_photoConfirmed
                                      ? null
                                      : _send,
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
        _photo(height: 130),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _openingCamera ? null : _camera,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Volver a tomar la foto'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('manual-address'),
          controller: _address,
          maxLength: 180,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => _update(_draft.copyWith(address: value)),
          decoration: const InputDecoration(
            labelText: 'Dirección o referencia manual',
            hintText: 'Ej.: calle 133 entre 43 y 44',
            prefixIcon: Icon(Icons.edit_location_alt_outlined),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('use-manual-address'),
            onPressed: _useManualAddress,
            icon: const Icon(Icons.location_searching_outlined),
            label: const Text('Usar dirección escrita'),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'No hace falta activar GPS ni cargar el mapa. La gestión verá la dirección para ubicar el problema.',
          style: TextStyle(fontSize: 12),
        ),
        if (draft.usesManualAddress && draft.location == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Dirección manual seleccionada. Confirmala con el botón inferior para continuar.',
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
        const SizedBox(height: 14),
        const Text(
          'Municipio (opcional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        const Text(
          'Escribí el nombre y elegilo de la lista para describir mejor el lugar.',
        ),
        const SizedBox(height: 8),
        MunicipalityAutocomplete(
          key: const Key('territory-municipality'),
          openUp: true,
          initialText: draft.territory,
          onSelected: (municipality) => _update(
            _draft.copyWith(territory: municipality?.label ?? ''),
          ),
        ),
      ];
  List<Widget> _detailsStep(BuildContext context, ReportDraft draft) => [
        _photo(),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openingCamera ? null : _camera,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Cambiar foto'),
        ),
        const SizedBox(height: 8),
        Card(
          child: CheckboxListTile(
            key: const Key('photo-evidence-confirmed'),
            value: _photoConfirmed,
            onChanged: (value) =>
                _update(_draft.copyWith(photoConfirmed: value ?? false)),
            title: const Text('Confirmo que la foto muestra el problema'),
            subtitle: const Text(
              'No envíes capturas de pantalla ni pantallas de permisos.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                draft.address.isEmpty ? 'Ubicación confirmada' : draft.address,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Cambiar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: reportPresets
              .map(
                (preset) => ChoiceChip(
                  label: Text(preset.label),
                  selected: draft.presetId == preset.id,
                  onSelected: (_) =>
                      _update(draft.copyWith(presetId: preset.id)),
                ),
              )
              .toList(),
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
