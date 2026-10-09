import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final userAsync = ref.watch(
      StreamProvider((ref) => ref.read(userRepositoryProvider).watchUser(user.uid)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (userModel) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.primary.withOpacity(0.15),
                child: Text(
                  userModel?.realName.isNotEmpty == true
                      ? userModel!.realName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontSize: 36, color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                userModel?.realName ?? '',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                userModel?.email ?? '',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Chip(
                label: Text(
                  _rolLabel(userModel?.role.value ?? 'citizen'),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: AppColors.primary.withOpacity(0.1),
              ),
            ),
            const SizedBox(height: 32),

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatTile(
                    label: 'Reportes',
                    value: '${userModel?.reportsCount ?? 0}'),
              ],
            ),
            const Divider(height: 40),

            // Opciones
            _MenuItem(
              icon: Icons.privacy_tip_outlined,
              label: 'Política de privacidad',
              onTap: () {/* TODO: abrir URL */},
            ),
            _MenuItem(
              icon: Icons.info_outline,
              label: 'Acerca de la app',
              onTap: () {/* TODO: pantalla about */},
            ),
            const Divider(height: 32),

            // Cerrar sesión
            _MenuItem(
              icon: Icons.logout,
              label: 'Cerrar sesión',
              color: Colors.orange,
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) context.go('/auth/welcome');
              },
            ),

            // Eliminar cuenta (Play Store obligatorio)
            _MenuItem(
              icon: Icons.delete_forever_outlined,
              label: 'Eliminar mi cuenta',
              color: Colors.red,
              onTap: () => _confirmDeleteAccount(context, ref, user.uid),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta acción es irreversible. Se eliminarán tu cuenta y todos tus datos. '
          'Tus reportes quedarán anónimos en el mapa.\n\n'
          '¿Estás seguro/a?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(userRepositoryProvider).deleteUserData(uid);
      await ref.read(authServiceProvider).deleteAccount();
      if (context.mounted) context.go('/auth/welcome');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Para eliminar tu cuenta, cerrá sesión y volvé a iniciarla primero.',
            ),
          ),
        );
      }
    }
  }

  String _rolLabel(String role) {
    switch (role) {
      case 'field_worker':
        return 'Equipo de campo';
      case 'coordinator':
        return 'Coordinador';
      case 'admin':
        return 'Administrador';
      case 'moderator':
        return 'Moderador';
      default:
        return 'Ciudadano';
    }
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuItem(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.onSurface;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}
