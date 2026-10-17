import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/report_permissions.dart';
import '../../data/models/report_model.dart';
import '../../data/repositories/reports_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/auth_service.dart';

class ReportPreset {
  const ReportPreset(this.id, this.label, this.category);
  final String id;
  final String label;
  final ReportCategory category;
}

const reportPresets = [
  ReportPreset('pothole', 'Bache', ReportCategory.infrastructure),
  ReportPreset('light', 'Luminaria apagada', ReportCategory.lighting),
  ReportPreset('trash', 'Basura acumulada', ReportCategory.garbage),
  ReportPreset('sidewalk', 'Vereda rota', ReportCategory.infrastructure),
  ReportPreset('tree', 'Árbol o espacio verde', ReportCategory.environment),
  ReportPreset('traffic', 'Semáforo o señal', ReportCategory.transport),
  ReportPreset('other', 'Otro problema', ReportCategory.other),
];

class ReportDraft {
  ReportDraft(
      {String? id,
      this.photoPath,
      this.location,
      this.locationConfirmed = false,
      this.usesManualAddress = false,
      this.photoConfirmed = false,
      this.presetId = 'other',
      this.aiRequested = true,
      this.comment = '',
      this.address = '',
      this.territory = ''})
      : id = id ?? const Uuid().v4();
  final String id;
  final String? photoPath;
  final LatLng? location;
  final bool locationConfirmed;
  final bool usesManualAddress;

  /// La persona confirmó que la foto muestra el problema. Vive en el borrador
  /// y no en la pantalla porque iniciar sesión o elegir municipio destruye la
  /// pantalla, y la confirmación se perdía dejando Enviar bloqueado sin motivo.
  final bool photoConfirmed;
  final String presetId;
  final bool aiRequested;
  final String comment;
  final String address;
  final String territory;
  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;
  bool get hasManualAddress => address.trim().length >= 4;
  bool get canSend =>
      hasPhoto &&
      locationConfirmed &&
      (location != null || (usesManualAddress && hasManualAddress));
  ReportPreset get preset => reportPresets.firstWhere((p) => p.id == presetId,
      orElse: () => reportPresets.last);

  ReportDraft copyWith(
          {String? photoPath,
          LatLng? location,
          bool? locationConfirmed,
          bool? usesManualAddress,
          bool? photoConfirmed,
          String? presetId,
          bool? aiRequested,
          String? comment,
          String? address,
          String? territory,
          bool clearLocation = false}) =>
      ReportDraft(
          id: id,
          photoPath: photoPath ?? this.photoPath,
          location: clearLocation ? null : location ?? this.location,
          locationConfirmed: clearLocation
              ? false
              : locationConfirmed ?? this.locationConfirmed,
          usesManualAddress: usesManualAddress ??
              (clearLocation ? false : this.usesManualAddress),
          photoConfirmed: photoConfirmed ?? this.photoConfirmed,
          presetId: presetId ?? this.presetId,
          aiRequested: aiRequested ?? this.aiRequested,
          comment: comment ?? this.comment,
          address: address ?? this.address,
          territory: territory ?? this.territory);

  Map<String, dynamic> toJson() => {
        'id': id,
        'photoPath': photoPath,
        'lat': location?.latitude,
        'lng': location?.longitude,
        'locationConfirmed': locationConfirmed,
        'usesManualAddress': usesManualAddress,
        'photoConfirmed': photoConfirmed,
        'presetId': presetId,
        'aiRequested': aiRequested,
        'comment': comment,
        'address': address,
        'territory': territory,
      };
  factory ReportDraft.fromJson(Map<String, dynamic> j) {
    final lat = j['lat'] as num?;
    final lng = j['lng'] as num?;
    return ReportDraft(
        id: j['id'] as String?,
        photoPath: j['photoPath'] as String?,
        location: lat != null && lng != null
            ? LatLng(lat.toDouble(), lng.toDouble())
            : null,
        locationConfirmed: j['locationConfirmed'] == true,
        usesManualAddress: j['usesManualAddress'] == true,
        photoConfirmed: j['photoConfirmed'] == true,
        presetId: j['presetId'] as String? ?? 'other',
        aiRequested: j['aiRequested'] != false,
        comment: j['comment'] as String? ?? '',
        address: j['address'] as String? ?? '',
        territory: j['territory'] as String? ?? '');
  }
}

class ReportDraftStorage {
  static const key = 'condi_report_draft_v2';
  Future<ReportDraft?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null
        ? null
        : ReportDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> write(ReportDraft? draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(draft.toJson()));
    }
  }
}

final reportDraftStorageProvider = Provider((ref) => ReportDraftStorage());

class ReportDraftController extends StateNotifier<ReportDraft> {
  ReportDraftController(this.storage) : super(ReportDraft()) {
    ready = _restore();
  }
  final ReportDraftStorage storage;
  late final Future<void> ready;
  Future<void> _writes = Future.value();
  Future<void> _restore() async {
    try {
      final saved = await storage.read();
      if (saved != null && mounted) state = saved;
    } catch (_) {/* A corrupt draft must not prevent opening the camera. */}
  }

  void update(ReportDraft draft) {
    state = draft;
    _writes =
        _writes.then((_) => storage.write(draft)).catchError((Object _) {});
  }

  Future<void> clear() async {
    state = ReportDraft();
    _writes =
        _writes.then((_) => storage.write(null)).catchError((Object _) {});
    await _writes;
  }
}

final reportDraftProvider =
    StateNotifierProvider<ReportDraftController, ReportDraft>(
        (ref) => ReportDraftController(ref.read(reportDraftStorageProvider)));

class ReportCaptureService {
  final ImagePicker _picker = ImagePicker();
  Future<Uint8List> readPhoto(String path) => XFile(path).readAsBytes();
  Future<XFile?> camera() async {
    if (!kIsWeb && !await ReportPermissions.requestCamera()) {
      throw StateError('Permití la cámara para fotografiar el problema.');
    }
    return _picker.pickImage(
        source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
  }

  Future<XFile?> recoverPhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final lost = await _picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    return lost.files?.isNotEmpty == true ? lost.files!.first : null;
  }

  Future<LatLng> gps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Activá la ubicación o marcá el punto en el mapa.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Podés ubicar el problema tocando el mapa.');
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    return LatLng(pos.latitude, pos.longitude);
  }
}

final reportCaptureProvider = Provider((ref) => ReportCaptureService());

/// Coordenada técnica de respaldo para no impedir un reporte cuando la persona
/// decide describir la dirección sin activar GPS. Nunca se presenta como un
/// punto exacto: el flag `isManualAddress` la excluye de mapas y concentraciones.
LatLng _manualAddressPoint(String municipalityId, String municipalityName) {
  final key = '$municipalityId $municipalityName'.toLowerCase();
  if (key.contains('la-plata') || key.contains('06441')) {
    return const LatLng(-34.9205, -57.9536);
  }
  if (key.contains('saladillo') || key.contains('060707')) {
    return const LatLng(-35.6384, -59.7779);
  }
  return const LatLng(-34.6037, -58.3816);
}

class MunicipalityRequired implements Exception {}

class ReportSubmitService {
  ReportSubmitService(this.ref);
  final Ref ref;
  bool get signedIn => FirebaseAuth.instance.currentUser != null;
  Future<void> loginWithGoogle() async {
    await ref.read(authServiceProvider).loginWithGoogle();
  }

  Future<String> submit(ReportDraft draft) async {
    if (!draft.canSend)
      throw StateError(
          'Agregá una foto y confirmá la ubicación o la dirección escrita.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Iniciá sesión para enviar tu reporte.');
    final profile = await ref.read(userRepositoryProvider).getUser(user.uid);
    final municipality = profile?.municipalityId ?? '';
    if (municipality.isEmpty) throw MunicipalityRequired();
    final repo = ref.read(reportsRepositoryProvider);
    if (await repo.countUserReportsToday(user.uid) >=
        AppConstants.maxReportsPerDay) {
      throw StateError('Alcanzaste el límite de 10 reportes por día.');
    }
    Uint8List bytes = await XFile(draft.photoPath!).readAsBytes();
    if (bytes.isEmpty)
      throw StateError('La foto no está disponible. Volvé a tomarla.');
    try {
      bytes = await FlutterImageCompress.compressWithList(bytes,
          quality: 80,
          minWidth: AppConstants.maxImagePixels,
          minHeight: AppConstants.maxImagePixels);
    } catch (_) {/* Upload the original if this platform cannot compress. */}
    final isPng = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80;
    final photo = FirebaseStorage.instance
        .ref('reports/${draft.id}/citizen/photo.${isPng ? 'png' : 'jpg'}');
    await photo.putData(bytes,
        SettableMetadata(contentType: isPng ? 'image/png' : 'image/jpeg'));
    final url = await photo.getDownloadURL();
    final isManualAddress = draft.location == null && draft.usesManualAddress;
    final location = draft.location ??
        _manualAddressPoint(
          profile?.municipalityId ?? '',
          profile?.municipalityName ?? '',
        );
    final locationLabel = [draft.territory.trim(), draft.address.trim()]
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final now = DateTime.now();
    await repo.createReport(ReportModel(
        id: draft.id,
        userId: user.uid,
        municipalityId: municipality,
        municipalityName: profile?.municipalityName,
        provinceId: profile?.provinceId,
        province: profile?.province,
        departmentId: profile?.departmentId,
        department: profile?.department,
        localityId: profile?.localityId,
        locality: profile?.locality,
        settlementId: profile?.settlementId,
        settlement: profile?.settlement,
        title: draft.preset.label,
        description: draft.comment.trim(),
        category: draft.preset.category,
        aiRequested: draft.aiRequested,
        photosReport: [url],
        location: ReportLocation(
            lat: location.latitude,
            lng: location.longitude,
            geohash: isManualAddress
                ? ''
                : GeoFirePoint(GeoPoint(location.latitude, location.longitude))
                    .geohash,
            address: locationLabel.isEmpty ? null : locationLabel,
            isManualAddress: isManualAddress),
        createdAt: now,
        updatedAt: now));
    return draft.id;
  }
}

final reportSubmitProvider = Provider((ref) => ReportSubmitService(ref));
