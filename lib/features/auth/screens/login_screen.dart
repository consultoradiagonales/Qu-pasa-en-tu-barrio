import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.loginWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      // Actualizar FCM token en Firestore
      await ref
          .read(userRepositoryProvider)
          .refreshFcmToken(credential.user!.uid);

      if (mounted) _redirectByRole(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthService.errorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.loginWithGoogle();
      await ref
          .read(userRepositoryProvider)
          .refreshFcmToken(credential.user!.uid);
      if (mounted) _redirectByRole(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthService.errorMessage(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar sesión con Google.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _redirectByRole(String uid) async {
    final user = await ref.read(userRepositoryProvider).getUser(uid);
    if (!mounted) return;
    switch (user?.role.value) {
      case 'field_worker':
        context.go('/field');
        break;
      case 'coordinator':
      case 'admin':
      case 'moderator':
        context.go('/coordinator');
        break;
      default:
        context.go('/map');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Correo
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresá tu correo';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Contraseña
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresá tu contraseña';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Olvidé mi contraseña
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/auth/forgot-password'),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 16),

              // Botón iniciar sesión
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 16),

              // Separador
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'o',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              // Google Sign-In
              OutlinedButton.icon(
                onPressed: _loading ? null : _loginWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continuar con Google'),
              ),
              const SizedBox(height: 24),

              // Link a registro
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿No tenés cuenta?'),
                  TextButton(
                    onPressed: () => context.go('/auth/register'),
                    child: const Text('Registrate'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
