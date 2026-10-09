import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notifications_repository.dart';
import '../../../data/services/auth_service.dart';

class NotificationsScreen extends ConsumerWidget {
  final bool forFieldWorker;
  const NotificationsScreen({super.key, this.forFieldWorker = false});

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
            onPressed: () => ref
                .read(notificationsRepositoryProvider)
                .markAllRead(user.uid),
            child: const Text('Marcar todo leído',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('Sin notificaciones por ahora.'),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final n = notifications[i];
              return _NotifTile(
                notification: n,
                userId: user.uid,
                forFieldWorker: forFieldWorker,
              );
            },
          );
        },
      ),
    );
  }
}

class _NotifTile extends ConsumerWidget {
  final NotificationModel notification;
  final String userId;
  final bool forFieldWorker;
  const _NotifTile({
    required this.notification,
    required this.userId,
    required this.forFieldWorker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !notification.read;

    return ListTile(
      tileColor: isUnread ? AppColors.primary.withOpacity(0.05) : null,
      leading: CircleAvatar(
        backgroundColor: _typeColor(notification.type).withOpacity(0.15),
        child: Icon(_typeIcon(notification.type),
            color: _typeColor(notification.type), size: 20),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            timeago.format(notification.createdAt, locale: 'es'),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
      onTap: () async {
        // Marcar como leída
        if (!notification.read) {
          await ref
              .read(notificationsRepositoryProvider)
              .markRead(userId, notification.id);
        }
        // Navegar al reporte
        if (context.mounted) {
          context.go(forFieldWorker
              ? '/field/task/${notification.reportId}'
              : '/report/${notification.reportId}');
        }
      },
    );
  }

  Color _typeColor(NotificationType type) {
    switch (type) {
      case NotificationType.newReport:
        return AppColors.primary;
      case NotificationType.reportResolved:
        return AppColors.statusResolved;
      case NotificationType.workerArrived:
        return AppColors.statusInProgress;
      case NotificationType.reportAssigned:
        return AppColors.primary;
      default:
        return AppColors.accent;
    }
  }

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.newReport:
        return Icons.add_location_alt_outlined;
      case NotificationType.reportResolved:
        return Icons.check_circle_outline;
      case NotificationType.workerArrived:
        return Icons.engineering_outlined;
      case NotificationType.reportAssigned:
        return Icons.assignment_outlined;
      case NotificationType.officialComment:
        return Icons.record_voice_over_outlined;
      case NotificationType.newSupport:
        return Icons.thumb_up_outlined;
    }
  }
}
