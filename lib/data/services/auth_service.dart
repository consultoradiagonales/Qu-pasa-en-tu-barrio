import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../repositories/user_repository.dart';

/// Stream del estado de autenticación de Firebase
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Proveedor del rol del usuario actual (leído de Firestore via UserRepository)
/// Se usa en el router para decidir a dónde redirigir
final currentUserRoleProvider = Provider<String?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  return ref.watch(currentUserProfileProvider(uid)).valueOrNull?.role.value;
});

/// Municipio del usuario actual. Devuelve null mientras no se haya leído el
/// perfil y cadena vacía cuando el usuario todavía no eligió municipio.
final currentUserMunicipalityProvider = Provider<String?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  return ref.watch(currentUserProfileProvider(uid)).valueOrNull?.municipalityId;
});

/// Indica si ya terminó el intento de leer el perfil, sin importar el
/// resultado. El router lo necesita para distinguir "todavía cargando" de
/// "no se pudo determinar el rol": en el primer caso no debe redirigir, en el
/// segundo debe tratar al usuario como si no fuera staff.
final userRoleResolvedProvider = Provider<bool>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return true;
  return !ref.watch(currentUserProfileProvider(uid)).isLoading;
});

/// Servicio de autenticación — wrapper sobre FirebaseAuth
class AuthService {
  static const _googleWebClientId =
      '949079641355-u8ktth9l6i9q3rcj6eesgajekuq7vgb1.apps.googleusercontent.com';
  static Future<void>? _googleSignInInitialization;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Registro con correo y contraseña
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Login con correo y contraseña
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await _ensureUserProfile(
        user,
        displayName: user.displayName,
        photoUrl: user.photoURL,
      );
    }
    return credential;
  }

  /// Login con Google (API google_sign_in v7)
  Future<UserCredential> loginWithGoogle() async {
    if (kIsWeb) {
      final credential = await _auth.signInWithPopup(GoogleAuthProvider());
      await _ensureUserProfile(
        credential.user!,
        displayName: credential.user?.displayName,
        photoUrl: credential.user?.photoURL,
      );
      return credential;
    }

    final GoogleSignInAccount googleAccount;
    try {
      // Inicializar justo antes del primer uso y conservar el mismo Future:
      // evita que un error silencioso de arranque deje el botón inutilizable.
      _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: _googleWebClientId,
      );
      await _googleSignInInitialization;
      googleAccount = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw FirebaseAuthException(
          code: 'cancelled-by-user',
          message: 'Inicio de sesión cancelado.',
        );
      }
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: 'No se pudo iniciar sesión con Google.',
      );
    }

    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: 'Google no devolvió un token válido.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await _auth.signInWithCredential(credential);

    await _ensureUserProfile(
      userCredential.user!,
      displayName: googleAccount.displayName,
      photoUrl: googleAccount.photoUrl,
    );
    return userCredential;
  }

  Future<void> _ensureUserProfile(
    User user, {
    String? displayName,
    String? photoUrl,
  }) async {
    // No depender de isNewUser: un intento anterior puede haber creado la
    // cuenta Auth y fallado antes de persistir el perfil Firestore. En ese caso
    // el siguiente inicio de sesión debe reparar el perfil automáticamente.
    final uid = user.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final existing = await transaction.get(userRef);
      if (existing.exists) return;
      transaction.set(userRef, {
        'displayName': 'Usuario #${uid.substring(0, 4).toUpperCase()}',
        'realName': displayName ?? '',
        'email': user.email ?? '',
        'photoURL': photoUrl,
        'role': 'citizen',
        'teamId': null,
        // Vacío: el router lo manda a elegir municipio antes de poder reportar.
        'municipalityId': '',
        'fcmToken': null,
        'createdAt': FieldValue.serverTimestamp(),
        'lastReportAt': null,
        'reportsCount': 0,
        'disabled': false,
      });
    });
  }

  /// Enviar correo de recuperación de contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Cambia la clave de una cuenta de correo después de validar la actual.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> activateOwnerAdmin() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .update({
      'role': 'admin',
      'disabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cerrar sesión
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (_) {}
    }
    await _auth.signOut();
  }

  /// Eliminar cuenta (requiere reautenticación reciente)
  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }

  /// Convertir errores de Firebase a mensajes en español.
  ///
  /// Se compara sobre code + message normalizados porque el mismo fallo llega
  /// con distinto `code` según la plataforma: con Email Enumeration Protection
  /// activada el backend responde INVALID_LOGIN_CREDENTIALS, que el SDK expone
  /// como 'invalid-credential' en Android y a veces sin traducir en web.
  static String errorMessage(FirebaseAuthException e) {
    final hay = '${e.code} ${e.message ?? ''}'.toLowerCase();

    bool has(String needle) => hay.contains(needle);

    if (has('invalid-login-credentials') ||
        has('invalid_login_credentials') ||
        has('invalid-credential') ||
        has('wrong-password') ||
        has('user-not-found')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (has('email-already-in-use') || has('email_exists')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (has('account-exists-with-different-credential')) {
      return 'Ese correo ya tiene una cuenta. Iniciá sesión con tu contraseña.';
    }
    if (has('invalid-email')) return 'El correo electrónico no es válido.';
    if (has('weak-password') || has('weak_password')) {
      return 'La contraseña debe tener al menos 8 caracteres.';
    }
    if (has('user-disabled')) return 'Esta cuenta fue deshabilitada.';
    if (has('operation-not-allowed')) {
      return 'Este método de inicio de sesión no está habilitado.';
    }
    if (has('too-many-requests')) {
      return 'Demasiados intentos. Esperá unos minutos e intentá de nuevo.';
    }
    if (has('requires-recent-login')) {
      return 'Para eliminar tu cuenta, cerrá sesión y volvé a iniciarla primero.';
    }
    if (has('network') || has('unavailable')) {
      return 'Sin conexión a internet. Verificá tu red.';
    }
    if (has('cancelled-by-user')) return 'Inicio de sesión cancelado.';
    if (has('google-sign-in-failed') || has('developer_error')) {
      return 'No se pudo iniciar sesión con Google. Probá con tu correo.';
    }
    return 'No se pudo completar la operación. Intentá de nuevo.';
  }

  /// Mensaje para fallos de inicio de sesión con correo y contraseña.
  ///
  /// Con Email Enumeration Protection activada el backend responde siempre
  /// INVALID_LOGIN_CREDENTIALS, y el `code` que expone el SDK varía según la
  /// plataforma. Descartados los fallos de red y el bloqueo por reintentos,
  /// lo que queda es siempre lo mismo: las credenciales no coinciden.
  static String loginErrorMessage(FirebaseAuthException e) {
    final hay = '${e.code} ${e.message ?? ''}'.toLowerCase();
    if (hay.contains('network') || hay.contains('unavailable')) {
      return 'Sin conexión a internet. Verificá tu red.';
    }
    if (hay.contains('too-many-requests')) {
      return 'Demasiados intentos. Esperá unos minutos e intentá de nuevo.';
    }
    if (hay.contains('user-disabled')) return 'Esta cuenta fue deshabilitada.';
    if (hay.contains('invalid-email')) {
      return 'El correo electrónico no es válido.';
    }
    if (hay.contains('operation-not-allowed')) {
      return 'El inicio de sesión con correo no está habilitado.';
    }
    return 'Correo o contraseña incorrectos. '
        'Si no te acordás, usá "¿Olvidaste tu contraseña?".';
  }
}

/// Proveedor global del AuthService
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
