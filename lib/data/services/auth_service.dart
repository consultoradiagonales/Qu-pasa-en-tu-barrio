import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Servicio de autenticación — wrapper sobre FirebaseAuth
class AuthService {
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
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Login con Google
  Future<UserCredential> loginWithGoogle() async {
    // TODO: inicializar GoogleSignIn
    // Requiere SHA-1 en Firebase Console para Android:
    // cd android && ./gradlew signingReport
    // Copiar el SHA-1 en Firebase Console > Configuración del proyecto > Tu app Android
    throw UnimplementedError('Google Sign-In pendiente de configuración');
  }

  /// Enviar correo de recuperación de contraseña
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
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

  /// Convertir errores de Firebase a mensajes en español
  static String errorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
        return 'La contraseña es incorrecta.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo.';
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'too-many-requests':
        return 'Demasiados intentos. Esperá unos minutos e intentá de nuevo.';
      case 'requires-recent-login':
        return 'Para eliminar tu cuenta, cerrá sesión y volvé a iniciarla primero.';
      case 'network-request-failed':
        return 'Sin conexión a internet. Verificá tu red.';
      default:
        return 'Ocurrió un error. Intentá de nuevo.';
    }
  }
}

/// Proveedor global del AuthService
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
