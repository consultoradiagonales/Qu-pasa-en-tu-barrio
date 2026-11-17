import 'dart:convert';
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
import '../../data/services/immutable_report_photo.dart';
import '../../data/models/user_model.dart';
import '../../data/services/georef_service.dart';
import 'camera/web_camera_capture.dart';

/// El municipio habitual se obtiene de la cuenta, nunca del último reporte.
final reportProfileProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  return user == null
      ? const AsyncData(null)
      : ref.watch(currentUserProfileProvider(user.uid));
});

final reportGeoRefProvider = Provider((ref) => GeoRefService());

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
  ReportPreset('standing_water', 'Agua estancada', ReportCategory.environment),
  ReportPreset('pests', 'Plagas', ReportCategory.health),
  ReportPreset('noise', 'Ruidos molestos', ReportCategory.other),
  ReportPreset('drug_dealing', 'Venta de droga', ReportCategory.security),
  ReportPreset(
      'street_racing', 'Picada motos o autos', ReportCategory.transport),
  ReportPreset('repeated_theft', 'Robos reiterados', ReportCategory.security),
  ReportPreset(
      'flooded_street', 'Calle anegada', ReportCategory.infrastructure),
  ReportPreset('disturbances', 'Disturbios', ReportCategory.security),
  ReportPreset('other', 'Otro', ReportCategory.other),
];

class ReportDraft {
  ReportDraft(
      {String? id,
      this.photoPath,
      this.location,
      this.locationConfirmed = false,
      this.usesManualAddress = false,
      this.photoConfirmed = false,
      this.presetId,
      this.aiRequested = true,
      this.comment = '',
      this.address = '',
      this.territory = '',
      this.reportMunicipalityId,
      this.reportMunicipalityName,
      this.reportProvinceId,
      this.reportProvince,
      this.photoPending = false})
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

  /// Null until the person explicitly chooses a category.
  final String? presetId;
  final bool aiRequested;
  final String comment;
  final String address;
  final String territory;

  /// Municipio excepcional al que se dirige este reporte. No modifica el
  /// municipio habitual del perfil y se descarta al terminar el envío.
  final String? reportMunicipalityId;
  final String? reportMunicipalityName;
  final String? reportProvinceId;
  final String? reportProvince;

  /// El reporte remoto (con id == [id]) ya fue creado pero la foto no se
  /// subió. Se persiste para que, tras reabrir la app, la pantalla siga
  /// ofreciendo "Reintentar foto" y el descarte oculte el reporte remoto.
  final bool photoPending;
  bool get reportsAwayFromHome =>
      reportMunicipalityId != null && reportMunicipalityId!.trim().isNotEmpty;
  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;
  bool get hasManualAddress => address.trim().length >= 2;
  bool get hasCategory =>
      presetId != null && reportPresets.any((preset) => preset.id == presetId);
  bool get canSend =>
      hasPhoto && locationConfirmed && location != null && hasCategory;
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
          String? reportMunicipalityId,
          String? reportMunicipalityName,
          String? reportProvinceId,
          String? reportProvince,
          bool? photoPending,
          bool clearReportMunicipality = false,
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
          territory: territory ?? this.territory,
          reportMunicipalityId: clearReportMunicipality
              ? null
              : reportMunicipalityId ?? this.reportMunicipalityId,
          reportMunicipalityName: clearReportMunicipality
              ? null
              : reportMunicipalityName ?? this.reportMunicipalityName,
          reportProvinceId: clearReportMunicipality
              ? null
              : reportProvinceId ?? this.reportProvinceId,
          reportProvince: clearReportMunicipality
              ? null
              : reportProvince ?? this.reportProvince,
          photoPending: photoPending ?? this.photoPending);

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
        'reportMunicipalityId': reportMunicipalityId,
        'reportMunicipalityName': reportMunicipalityName,
        'reportProvinceId': reportProvinceId,
        'reportProvince': reportProvince,
        'photoPending': photoPending,
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
        presetId: j['presetId'] as String?,
        aiRequested: j['aiRequested'] != false,
        comment: j['comment'] as String? ?? '',
        address: j['address'] as String? ?? '',
        territory: j['territory'] as String? ?? '',
        reportMunicipalityId: j['reportMunicipalityId'] as String?,
        reportMunicipalityName: j['reportMunicipalityName'] as String?,
        reportProvinceId: j['reportProvinceId'] as String?,
        reportProvince: j['reportProvince'] as String?,
        // Borradores anteriores no tienen la clave: se leen como false.
        photoPending: j['photoPending'] == true);
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
    if (kIsWeb) return captureWebCameraPhoto();
    if (!await ReportPermissions.requestCamera()) {
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
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
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

class MunicipalityRequired implements Exception {}

class ReportSubmissionException extends StateError {
  ReportSubmissionException(super.message, {this.photoPending = false});

  final bool photoPending;
}

class ReportSubmitService {
  ReportSubmitService(this.ref);
  final Ref ref;
  bool get signedIn => FirebaseAuth.instance.currentUser != null;
  Future<void> loginWithGoogle() async {
    await ref.read(authServiceProvider).loginWithGoogle();
  }

  Future<String> submit(ReportDraft draft) async {
    if (!draft.canSend) {
      throw StateError(
        'Agregá una foto, confirmá un punto en el mapa y elegí una categoría.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Iniciá sesión para enviar tu reporte.');
    UserModel? profile;
    try {
      profile = await ref.read(userRepositoryProvider).getUser(user.uid);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        throw ReportSubmissionException(
          'No pudimos validar tu cuenta para enviar el reporte. Cerrá sesión, volvé a ingresar e intentá de nuevo.',
        );
      }
      rethrow;
    }
    final homeMunicipality = profile?.municipalityId ?? '';
    if (homeMunicipality.isEmpty) throw MunicipalityRequired();
    final municipality = draft.reportsAwayFromHome
        ? draft.reportMunicipalityId!.trim()
        : homeMunicipality;
    final repo = ref.read(reportsRepositoryProvider);
    Uint8List bytes = await XFile(draft.photoPath!).readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('La foto no está disponible. Volvé a tomarla.');
    }
    try {
      bytes = await FlutterImageCompress.compressWithList(bytes,
          quality: 80,
          minWidth: AppConstants.maxImagePixels,
          minHeight: AppConstants.maxImagePixels);
    } catch (_) {/* Upload the original if this platform cannot compress. */}
    final isPng = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80;
    final photoPath =
        'reports/${draft.id}/citizen/photo.${isPng ? 'png' : 'jpg'}';
    final photo = FirebaseStorage.instance.ref(photoPath);
    // Primero se confirma el alta liviana. El ADMIN la recibe por Firestore
    // mientras la evidencia continúa subiendo en segundo plano de red.
    final location = draft.location!;
    final locationLabel = [draft.territory.trim(), draft.address.trim()]
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final now = DateTime.now();
    final report = ReportModel(
        id: draft.id,
        userId: user.uid,
        municipalityId: municipality,
        municipalityName: draft.reportsAwayFromHome
            ? draft.reportMunicipalityName
            : profile?.municipalityName,
        provinceId: draft.reportsAwayFromHome
            ? draft.reportProvinceId
            : profile?.provinceId,
        province: draft.reportsAwayFromHome
            ? draft.reportProvince
            : profile?.province,
        departmentId: draft.reportsAwayFromHome ? null : profile?.departmentId,
        department: draft.reportsAwayFromHome ? null : profile?.department,
        localityId: draft.reportsAwayFromHome ? null : profile?.localityId,
        locality: draft.reportsAwayFromHome ? null : profile?.locality,
        settlementId: draft.reportsAwayFromHome ? null : profile?.settlementId,
        settlement: draft.reportsAwayFromHome ? null : profile?.settlement,
        homeMunicipalityId: homeMunicipality,
        reportedAwayFromHome: municipality != homeMunicipality,
        title: draft.preset.label,
        description: draft.comment.trim(),
        category: draft.preset.category,
        aiRequested: draft.aiRequested,
        location: ReportLocation(
            lat: location.latitude,
            lng: location.longitude,
            geohash:
                GeoFirePoint(GeoPoint(location.latitude, location.longitude))
                    .geohash,
            address: locationLabel.isEmpty ? null : locationLabel,
            isManualAddress: draft.usesManualAddress),
        createdAt: now,
        updatedAt: now);
    try {
      await repo.createReport(report, pendingPhotoPath: photoPath);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        throw ReportSubmissionException(
          'No se pudo registrar el reporte. Revisá que tu cuenta tenga un municipio asignado y volvé a intentar.',
        );
      }
      rethrow;
    }
    String url;
    try {
      url = await uploadImmutableReportPhoto(
        bytes: bytes,
        read: () => photo.getData(8 * 1024 * 1024),
        upload: () async {
          await photo.putData(
              bytes,
              SettableMetadata(
                  contentType: isPng ? 'image/png' : 'image/jpeg'));
        },
        downloadUrl: photo.getDownloadURL,
      );
    } on FirebaseException catch (error) {
      final accessDenied = error.code == 'unauthorized' ||
          error.code == 'permission-denied' ||
          error.code == 'unauthenticated';
      throw ReportSubmissionException(
        accessDenied
            ? 'El reporte ya fue recibido, pero el servicio de fotos rechazó la carga. Conservamos el borrador para reintentar cuando se restablezca el acceso.'
            : 'El reporte ya fue recibido, pero la foto quedó pendiente. Revisá tu conexión y tocá “Reintentar foto”. No crees otro reporte.',
        photoPending: true,
      );
    } on StateError catch (error) {
      throw ReportSubmissionException(
        'El reporte ya fue recibido, pero la foto quedó pendiente: ${error.message}',
        photoPending: true,
      );
    } catch (_) {
      throw ReportSubmissionException(
        'El reporte ya fue recibido, pero la foto quedó pendiente. Tocá “Reintentar foto”. No crees otro reporte.',
        photoPending: true,
      );
    }
    try {
      await repo.completeReportPhoto(
        reportId: draft.id,
        storagePath: photoPath,
        downloadUrl: url,
      );
    } catch (_) {
      throw ReportSubmissionException(
        'El reporte ya fue recibido, pero falta confirmar la foto. Tocá “Reintentar foto” para completar el envío.',
        photoPending: true,
      );
    }
    return draft.id;
  }
}

final reportSubmitProvider = Provider((ref) => ReportSubmitService(ref));
