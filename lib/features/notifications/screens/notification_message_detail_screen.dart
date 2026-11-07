import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/notification_model.dart';
import '../notification_visuals.dart';

const _trustedLinkDomains = <String>{
  'consultoradiagonales.com.ar',
  'play.google.com',
  'wa.me',
};

/// Extracts only HTTPS links to destinations controlled by ConDi or the
/// official distribution channels. This keeps server-sent notification text
/// from opening unknown destinations on a user's device.
List<Uri> safeNotificationLinks(String text) {
  final seen = <String>{};
  final links = <Uri>[];
  final matches =
      RegExp(r'https://[^\s<>()]+', caseSensitive: false).allMatches(text);

  for (final match in matches) {
    final raw = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?\)]$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;

    final host = uri.host.toLowerCase();
    final trusted = _trustedLinkDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
    if (trusted && seen.add(uri.toString())) links.add(uri);
  }
  return links;
}

Future<void> openSafeNotificationLink(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class NotificationMessageDetailScreen extends StatelessWidget {
  const NotificationMessageDetailScreen({
    super.key,
    required this.notification,
    required this.forFieldWorker,
  });

  final NotificationModel notification;
  final bool forFieldWorker;

  @override
  Widget build(BuildContext context) {
    final color = notificationTypeColor(notification.type);
    final links = safeNotificationLinks(
      '${notification.actionUrl ?? ''} ${notification.body}',
    );
    final theme = Theme.of(context);
    final timestamp =
        DateFormat('dd/MM/yyyy HH:mm').format(notification.createdAt);
    final city = notification.municipalityName?.trim() ?? '';
    final province = notification.province?.trim() ?? '';
    final affectedArea = notification.affectedArea?.trim().isNotEmpty == true
        ? notification.affectedArea!.trim()
        : notification.affectedZones.join(', ');
    final hasLocation = city.isNotEmpty || affectedArea.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(notification.type == NotificationType.weatherAlert
            ? 'Alerta meteorológica'
            : 'Mensaje'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withOpacity(0.15),
                        child: Icon(notificationTypeIcon(notification.type),
                            color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ConDi',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              notificationTypeLabel(notification.type),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('notification-affected-area'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withOpacity(0.28)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (city.isNotEmpty)
                            _LocationLine(
                              icon: Icons.location_city_outlined,
                              label: 'Tu ciudad',
                              value:
                                  province.isEmpty ? city : '$city, $province',
                            ),
                          if (city.isNotEmpty && affectedArea.isNotEmpty)
                            const SizedBox(height: 10),
                          if (affectedArea.isNotEmpty)
                            _LocationLine(
                              icon: Icons.map_outlined,
                              label: 'Zonas afectadas',
                              value: affectedArea,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: const Key('notification-message-full'),
                      constraints: const BoxConstraints(maxWidth: 560),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            notification.body.isEmpty
                                ? 'Sin contenido adicional.'
                                : notification.body,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(height: 1.42),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              timestamp,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (notification.imageUrl?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      label: 'Imagen adjunta al mensaje',
                      image: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: notification.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 150,
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined),
                                SizedBox(height: 6),
                                Text('No se pudo cargar la imagen.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (links.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Enlaces del mensaje',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final link in links)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          key: Key('notification-link-${link.host}'),
                          onPressed: () => openSafeNotificationLink(link),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(
                            link.host == 'play.google.com' ||
                                    link.host == 'apps.apple.com'
                                ? 'Actualizar ConDi'
                                : link.host,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (notification.hasReport)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.icon(
                  key: const Key('notification-open-report'),
                  onPressed: () => context.go(
                    forFieldWorker
                        ? '/field/task/${notification.reportId}'
                        : '/report/${notification.reportId}',
                  ),
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Ver reporte'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      );
}
