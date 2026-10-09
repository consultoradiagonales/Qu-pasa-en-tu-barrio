/// Constantes globales de la app
abstract class AppConstants {
  // Límites de contenido
  static const int maxTitleLength = 80;
  static const int maxDescriptionLength = 500;
  static const int maxCommentLength = 300;
  static const int maxWorkerNotesLength = 200;
  static const int maxPhotosPerReport = 5;

  // Rate limiting: máx. reportes por usuario por día
  static const int maxReportsPerDay = 10;

  // Imágenes
  static const int maxImageSizeMb = 5;
  static const int maxImagePixels = 1200; // redimensionar a este ancho máximo

  // Prioridad
  static const int minPriority = 1;
  static const int maxPriority = 5;

  // Tiempo antes de auto-cerrar reportes resueltos (días)
  static const int autoCloseDays = 30;

  // URLs
  static const String privacyPolicyUrl =
      'https://tudominio.com/privacidad'; // TODO: reemplazar con URL real
  static const String termsUrl =
      'https://tudominio.com/terminos'; // TODO: reemplazar con URL real
  static const String deleteAccountUrl =
      'https://tudominio.com/eliminar-cuenta'; // requerido por Play Store

  // Colecciones Firestore
  static const String usersCollection = 'users';
  static const String reportsCollection = 'reports';
  static const String commentsCollection = 'comments';
  static const String supportVotesCollection = 'supportVotes';
  static const String notificationsCollection = 'notifications';
  static const String contentFlagsCollection = 'contentFlags';
  static const String teamsCollection = 'teams';
  static const String municipalitiesCollection = 'municipalities';

  // Categorías (en el mismo orden que el UI)
  static const List<String> categories = [
    'infrastructure',
    'lighting',
    'garbage',
    'security',
    'health',
    'transport',
    'environment',
    'other',
  ];
}
