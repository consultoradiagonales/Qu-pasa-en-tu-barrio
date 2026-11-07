import 'package:flutter/material.dart';

import '../../data/models/notification_model.dart';
import '../../core/theme/app_theme.dart';

Color notificationTypeColor(NotificationType type) {
  switch (type) {
    case NotificationType.newReport:
    case NotificationType.reportAssigned:
      return AppColors.primary;
    case NotificationType.reportResolved:
      return AppColors.statusResolved;
    case NotificationType.reportProgress:
    case NotificationType.workerArrived:
      return AppColors.statusInProgress;
    case NotificationType.reportRejected:
    case NotificationType.weatherAlert:
      return AppColors.statusPending;
    case NotificationType.officialComment:
    case NotificationType.newSupport:
    case NotificationType.municipalityMessage:
      return AppColors.accent;
  }
}

IconData notificationTypeIcon(NotificationType type) {
  switch (type) {
    case NotificationType.newReport:
      return Icons.add_location_alt_outlined;
    case NotificationType.reportResolved:
      return Icons.check_circle_outline;
    case NotificationType.reportProgress:
      return Icons.photo_camera_back_outlined;
    case NotificationType.reportRejected:
      return Icons.info_outline;
    case NotificationType.workerArrived:
      return Icons.engineering_outlined;
    case NotificationType.reportAssigned:
      return Icons.assignment_outlined;
    case NotificationType.officialComment:
      return Icons.record_voice_over_outlined;
    case NotificationType.newSupport:
      return Icons.thumb_up_outlined;
    case NotificationType.weatherAlert:
      return Icons.cloud_outlined;
    case NotificationType.municipalityMessage:
      return Icons.campaign_outlined;
  }
}

String notificationTypeLabel(NotificationType type) {
  switch (type) {
    case NotificationType.newReport:
      return 'Nuevo reporte';
    case NotificationType.reportAssigned:
      return 'Reporte asignado';
    case NotificationType.workerArrived:
      return 'Cuadrilla en camino';
    case NotificationType.reportResolved:
      return 'Reporte resuelto';
    case NotificationType.reportProgress:
      return 'Actualizacion del reporte';
    case NotificationType.reportRejected:
      return 'Actualizacion del reporte';
    case NotificationType.officialComment:
      return 'Mensaje oficial';
    case NotificationType.newSupport:
      return 'Apoyo recibido';
    case NotificationType.weatherAlert:
      return 'Alerta meteorologica';
    case NotificationType.municipalityMessage:
      return 'Mensaje municipal';
  }
}
