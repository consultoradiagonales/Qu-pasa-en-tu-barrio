import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'assets/images/condi_logo.png',
                  width: 190,
                  height: 190,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Reportá lo que pasa en tu barrio',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Reportá problemas urbanos, seguí su estado y ayudá a mejorar tu ciudad.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // Características rápidas
              _FeatureRow(
                icon: Icons.camera_alt_outlined,
                text: 'Sacá una foto y geolocaliza el problema',
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.people_outline,
                text: 'Otros vecinos pueden apoyar tu reporte',
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: Icons.check_circle_outline,
                text: 'Ves el antes y después cuando se resuelve',
              ),
              const Spacer(),
              // Botones
              ElevatedButton(
                onPressed: () => context.go('/auth/register'),
                child: const Text('Crear cuenta'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/auth/login'),
                child: const Text('Iniciar sesión'),
              ),
              const SizedBox(height: 24),
              // Política de privacidad
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.privacyPolicyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Al continuar aceptás nuestra Política de privacidad',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
