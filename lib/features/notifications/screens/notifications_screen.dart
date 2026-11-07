import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../core/services/notification_action_service.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notifications_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/utils/error_text.dart';
import '../notification_visuals.dart';
import 'notification_message_detail_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  final bool forFieldWorker;
  final NotificationActionLauncher actionLauncher;
  const NotificationsScreen({
    super.key,
    this.forFieldWorker = false,
    this.actionLauncher = launchTrustedNotificationAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final notifAsync = ref.watch(notificationsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationsRepositoryProvider).markAllRead(user.uid),
            child: const Text('Marcar todo leído',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(mensajeDeError(e))),
        data: (notifications) {
          return Column(
            children: [
              _PushActivationCard(userId: user.uid),
              Expanded(
                child: notifications.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none_outlined,
                                size: 64, color: AppColors.textSecondary),
                            SizedBox(height: 16),
                            Text('Sin notificaciones por ahora.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = notifications[i];
                          return _NotifTile(
                            notification: n,
                            userId: user.uid,
                            forFieldWorker: forFieldWorker,
                            actionLauncher: actionLauncher,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Permite recuperar la entrega push cuando se instaló una versión anterior o
/// cuando el sistema negó el permiso la primera vez. El token nunca se muestra
/// ni se guarda fuera del perfil de la persona autenticada.
class _PushActivationCard extends StatefulWidget {
  const _PushActivationCard({required this.userId});

  final String userId;

  @override
  State<_PushActivationCard> createState() => _PushActivationCardState();
}

class _PushActivationCardState extends State<_PushActivationCard> {
  AuthorizationStatus? _status;
  bool _loading = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (kIsWeb) return;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (mounted) setState(() => _status = settings.authorizationStatus);
    } catch (_) {
      // El botón vuelve a intentar y muestra el error si el servicio no está listo.
    }
  }

  Future<void> _activate() async {
    if (kIsWeb) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      var settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await Geolocator.openAppSettings();
        if (mounted) {
          setState(() {
            _status = settings.authorizationStatus;
            _result =
                'Habilitá las notificaciones de ConDi en Ajustes y luego volvé a verificar este celular.';
          });
        }
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        throw StateError('No se pudo registrar este celular todavía.');
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
        'fcmToken': token,
      });
      if (mounted) {
        setState(() {
          _status = settings.authorizationStatus;
          _result =
              'Este celular quedó habilitado para recibir actualizaciones y alertas.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _result =
            'No se pudo activar ahora. Revisá la conexión e intentá nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final authorized = _status == AuthorizationStatus.authorized ||
        _status == AuthorizationStatus.provisional;
    final denied = _status == AuthorizationStatus.denied;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: authorized
            ? AppColors.primary.withOpacity(0.07)
            : Colors.amber.withOpacity(0.11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: authorized
              ? AppColors.primary.withOpacity(0.24)
              : Colors.amber.shade700.withOpacity(0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            authorized
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: authorized ? AppColors.primary : Colors.amber.shade900,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorized
                      ? 'Notificaciones activas'
                      : 'Activá las notificaciones',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  _result ??
                      (authorized
                          ? 'Verificá este celular si no recibís actualizaciones o alertas.'
                          : 'Recibí avisos sobre tus reportes y alertas de tu zona aun con la app cerrada.'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loading ? null : _activate,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(denied
                          ? Icons.settings_outlined
                          : Icons.notifications_active_outlined),
                  label: Text(denied
                      ? 'Abrir ajustes'
                      : authorized
                          ? 'Verificar este celular'
                          : 'Activar ahora'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifTile extends ConsumerWidget {
  final NotificationModel notification;
  final String userId;
  final bool forFieldWorker;
  final NotificationActionLauncher actionLauncher;
  const _NotifTile({
    required this.notification,
    required this.userId,
    required this.forFieldWorker,
    required this.actionLauncher,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !notification.read;

    return Dismissible(
      key: ValueKey('notification-${notification.id}'),
      direction: DismissDirection.horizontal,
      background: const _DismissBackground(alignment: Alignment.centerLeft),
      secondaryBackground:
          const _DismissBackground(alignment: Alignment.centerRight),
      confirmDismiss: (_) async {
        try {
          await ref
              .read(notificationsRepositoryProvider)
              .deleteNotification(userId, notification.id);
          return true;
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No se pudo eliminar la notificación.')),
            );
          }
          return false;
        }
      },
      onDismissed: (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alerta eliminada.')),
          );
        }
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        tileColor: isUnread ? AppColors.primary.withOpacity(0.05) : null,
        leading: CircleAvatar(
          backgroundColor:
              notificationTypeColor(notification.type).withOpacity(0.15),
          child: Icon(
            notificationTypeIcon(notification.type),
            color: notificationTypeColor(notification.type),
            size: 20,
          ),
        ),
        title: Text(
          notification.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (notification.imageUrl?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  notification.imageUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              timeago.format(notification.createdAt, locale: 'es'),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        trailing: Icon(
          notification.actionUrl == null
              ? Icons.chevron_right
              : Icons.open_in_new_rounded,
          semanticLabel: notification.actionUrl == null
              ? 'Abrir alerta completa'
              : 'Abrir enlace de actualización',
        ),
        onTap: () async {
          if (!notification.read) {
            try {
              await ref
                  .read(notificationsRepositoryProvider)
                  .markRead(userId, notification.id);
            } catch (_) {
              // Opening a message must not depend on a transient network error.
            }
          }
          final actionUrl = notification.actionUrl;
          if (actionUrl != null) {
            final opened = await openNotificationAction(
              {'actionUrl': actionUrl},
              launcher: actionLauncher,
            );
            if (opened || !context.mounted) return;
          }
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationMessageDetailScreen(
                notification: notification,
                forFieldWorker: forFieldWorker,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      const Icon(Icons.delete_outline, color: Colors.white),
      const SizedBox(width: 8),
      const Text(
        'Eliminar',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ];
    return Container(
      color: Colors.red.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerRight
            ? content.reversed.toList(growable: false)
            : content,
      ),
    );
  }
}
