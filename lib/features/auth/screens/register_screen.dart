import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/models/user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.registerWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      // Guardar datos del usuario en Firestore
      final uid = credential.user!.uid;
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.createUser(UserModel(
        uid: uid,
        displayName: 'Usuario #${uid.substring(0, 4).toUpperCase()}',
        realName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        role: UserRole.citizen,
        municipalityId: 'default', // TODO: selección de municipio
        createdAt: DateTime.now(),
      ));

      await userRepo.refreshFcmToken(uid);

      if (mounted) context.go('/map');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nombre completo
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá tu nombre';
                  if (v.trim().length < 2) return 'Nombre demasiado corto';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Correo
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresá tu correo';
                  if (!v.contains('@')) return 'Correo no válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Contraseña
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresá una contraseña';
                  if (v.length < 8) return 'Mínimo 8 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Confirmar contraseña
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _passCtrl.text) return 'Las contraseñas no coinciden';
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Botón crear cuenta
              ElevatedButton(
                onPressed: _loading ? null : _register,
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
                    : const Text('Crear cuenta'),
              ),
              const SizedBox(height: 16),

              // Link a login
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿Ya tenés cuenta?'),
                  TextButton(
                    onPressed: () => context.go('/auth/login'),
                    child: const Text('Iniciá sesión'),
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
