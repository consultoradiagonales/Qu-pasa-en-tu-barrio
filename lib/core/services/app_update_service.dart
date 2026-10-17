import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class RequiredAppUpdate {
  const RequiredAppUpdate({
    required this.currentBuild,
    required this.minimumBuild,
    required this.storeUrl,
    required this.message,
  });

  final int currentBuild;
  final int minimumBuild;
  final String storeUrl;
  final String message;
}

/// Consulta una configuración pública y bloquea solo cuando existe una versión
/// de tienda más nueva que la instalada. Ante falta de red o configuración no
/// válida, deja iniciar la app para no impedir un reporte urgente.
class AppUpdateService {
  AppUpdateService._();

  static final _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static Future<RequiredAppUpdate?> requiredUpdate() async {
    if (kIsWeb) return null;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final result = await _functions
          .httpsCallable('getAppRelease')
          .call({'platform': platform}).timeout(const Duration(seconds: 5));
      final payload = Map<String, dynamic>.from(result.data as Map);
      final release =
          Map<String, dynamic>.from(payload[platform] as Map? ?? {});
      final minimumBuild = _asInt(release['minBuild']);
      final storeUrl = _storeUrl(release['storeUrl'], platform);
      final message = _text(release['message']);
      if (minimumBuild <= currentBuild || storeUrl == null) return null;
      return RequiredAppUpdate(
        currentBuild: currentBuild,
        minimumBuild: minimumBuild,
        storeUrl: storeUrl,
        message: message.isEmpty
            ? 'Hay una nueva versión de ConDi disponible. Actualizá la app para continuar.'
            : message,
      );
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static String? _storeUrl(Object? value, String platform) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (platform == 'android' && host != 'play.google.com') return null;
    if (platform == 'ios' && host != 'apps.apple.com') return null;
    return uri.toString();
  }
}

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({super.key, required this.update});

  final RequiredAppUpdate update;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.system_update_alt_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Actualizá ConDi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      update.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Esta versión ya no puede usarse. Instalá la actualización para continuar.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () async {
                        final opened = await launchUrl(
                          Uri.parse(update.storeUrl),
                          mode: LaunchMode.externalApplication,
                        );
                        if (!opened && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'No se pudo abrir la tienda. Intentá nuevamente.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Actualizar ahora'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
