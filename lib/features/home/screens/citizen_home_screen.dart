import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/municipality_identity.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';

class CitizenHomeScreen extends ConsumerWidget {
  const CitizenHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _CameraQuickAccess(
                onTap: () => context.go('/report/new?mode=camera'),
              ),
            ),
            Expanded(
              child: Container(
                key: const Key('home-profile-panel'),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.09),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: user == null
                    ? const _SignedOutProfilePanel()
                    : ref.watch(currentUserProfileProvider(user.uid)).when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          error: (_, __) => _ProfileShortcuts(
                            name: user.displayName ?? 'Mi perfil',
                            email: user.email ?? '',
                          ),
                          data: (profile) => _ProfileShortcuts(
                            name: _profileName(profile, user.displayName),
                            email: profile?.email ?? user.email ?? '',
                            reportsCount: profile?.reportsCount,
                            municipalityId: profile?.municipalityId,
                            municipalityName: profile?.municipalityName,
                            canChangeMunicipality:
                                profile?.role == UserRole.citizen,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _profileName(UserModel? profile, String? authName) {
    final realName = profile?.realName.trim() ?? '';
    if (realName.isNotEmpty) return realName;
    final displayName = profile?.displayName.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final fallback = authName?.trim() ?? '';
    return fallback.isEmpty ? 'Mi perfil' : fallback;
  }
}

class _CameraQuickAccess extends StatelessWidget {
  const _CameraQuickAccess({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Material(
        key: const Key('home-camera-quick'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEDF4FF), AppColors.surface],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCEAFB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: AppColors.primary,
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Reportar con la cámara',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sacá una foto y cargá el reporte en pocos pasos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignedOutProfilePanel extends StatelessWidget {
  const _SignedOutProfilePanel();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 30,
            child: Icon(Icons.person_outline, size: 34),
          ),
          const SizedBox(height: 10),
          Text('Tu cuenta', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Iniciá sesión para ver alertas, reportes y todas las opciones de tu perfil.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('home-login'),
              onPressed: () => context.go(
                '/auth/login?next=${Uri.encodeComponent('/home')}',
              ),
              icon: const Icon(Icons.login),
              label: const Text('Iniciar sesión'),
            ),
          ),
          TextButton(
            key: const Key('home-register'),
            onPressed: () => context.go('/auth/register'),
            child: const Text('Crear cuenta'),
          ),
        ],
      ),
    );
  }
}

class _ProfileShortcuts extends StatelessWidget {
  const _ProfileShortcuts({
    required this.name,
    required this.email,
    this.reportsCount,
    this.municipalityId,
    this.municipalityName,
    this.canChangeMunicipality = false,
  });

  final String name;
  final String email;
  final int? reportsCount;
  final String? municipalityId;
  final String? municipalityName;
  final bool canChangeMunicipality;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    if (municipalityId?.trim().isNotEmpty == true ||
                        municipalityName?.trim().isNotEmpty == true)
                      MunicipalityIdentity(
                        municipalityId: municipalityId,
                        municipalityName: municipalityName,
                        crestSize: 22,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (reportsCount != null)
                Column(
                  children: [
                    Text(
                      '$reportsCount',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const Text('Reportes', style: TextStyle(fontSize: 11)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.55,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _HomeShortcut(
                key: const Key('home-alerts'),
                icon: Icons.notifications_outlined,
                label: 'Alertas',
                onTap: () => context.go('/notifications'),
              ),
              _HomeShortcut(
                key: const Key('home-my-reports'),
                icon: Icons.list_alt_outlined,
                label: 'Mis reportes',
                onTap: () => context.go('/my-reports'),
              ),
              _HomeShortcut(
                key: const Key('home-map'),
                icon: Icons.map_outlined,
                label: 'Mapa',
                onTap: () => context.go('/map'),
              ),
              _HomeShortcut(
                key: const Key('home-full-profile'),
                icon: Icons.manage_accounts_outlined,
                label: 'Mi perfil',
                onTap: () => context.go('/profile'),
              ),
            ],
          ),
          if (canChangeMunicipality) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                key: const Key('home-change-municipality'),
                onPressed: () => context.go('/auth/municipio?next=home'),
                icon: const Icon(Icons.location_city_outlined),
                label: const Text('Cambiar municipio de alertas'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeShortcut extends StatelessWidget {
  const _HomeShortcut({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
