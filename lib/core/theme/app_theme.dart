import 'package:flutter/material.dart';

/// Paleta de colores oficial de la app
abstract class AppColors {
  // Primario: azul municipal
  static const primary = Color(0xFF1565C0);
  static const primaryLight = Color(0xFF1E88E5);
  static const primaryDark = Color(0xFF0D47A1);

  // Acento: naranja urgencia
  static const accent = Color(0xFFFF6F00);
  static const accentLight = Color(0xFFFFB300);

  // Estados de los reportes
  static const statusPending = Color(0xFFE53935);    // rojo
  static const statusAssigned = Color(0xFFFB8C00);   // naranja
  static const statusInProgress = Color(0xFFFFB300); // amarillo
  static const statusResolved = Color(0xFF43A047);   // verde
  static const statusRejected = Color(0xFF757575);   // gris

  // Categorías
  static const catInfrastructure = Color(0xFF5C6BC0);
  static const catLighting = Color(0xFFFFCA28);
  static const catGarbage = Color(0xFF66BB6A);
  static const catSecurity = Color(0xFFEF5350);
  static const catHealth = Color(0xFF26C6DA);
  static const catTransport = Color(0xFF42A5F5);
  static const catEnvironment = Color(0xFF9CCC65);
  static const catOther = Color(0xFFBDBDBD);

  // Neutros
  static const background = Color(0xFFF5F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider = Color(0xFFE0E0E0);

  // Dark mode
  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        background: AppColors.background,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: AppColors.surface,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        secondary: AppColors.accentLight,
        background: AppColors.backgroundDark,
        surface: AppColors.surfaceDark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
    );
  }
}

/// Helper para obtener el color según el estado del reporte
Color statusColor(String status) {
  switch (status) {
    case 'pending':
      return AppColors.statusPending;
    case 'assigned':
      return AppColors.statusAssigned;
    case 'in_progress':
      return AppColors.statusInProgress;
    case 'resolved':
      return AppColors.statusResolved;
    case 'rejected':
    case 'closed':
      return AppColors.statusRejected;
    default:
      return AppColors.statusPending;
  }
}

/// Helper para obtener la etiqueta en español del estado
String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pendiente';
    case 'assigned':
      return 'Asignado';
    case 'in_progress':
      return 'En curso';
    case 'resolved':
      return 'Resuelto';
    case 'rejected':
      return 'Rechazado';
    case 'closed':
      return 'Cerrado';
    default:
      return 'Pendiente';
  }
}

/// Helper para obtener la etiqueta en español de la categoría
String categoryLabel(String category) {
  switch (category) {
    case 'infrastructure':
      return 'Infraestructura';
    case 'lighting':
      return 'Alumbrado';
    case 'garbage':
      return 'Basura';
    case 'security':
      return 'Seguridad';
    case 'health':
      return 'Salud';
    case 'transport':
      return 'Transporte';
    case 'environment':
      return 'Medio Ambiente';
    case 'other':
      return 'Otro';
    default:
      return 'Otro';
  }
}

/// Helper para obtener el color de la categoría
Color categoryColor(String category) {
  switch (category) {
    case 'infrastructure':
      return AppColors.catInfrastructure;
    case 'lighting':
      return AppColors.catLighting;
    case 'garbage':
      return AppColors.catGarbage;
    case 'security':
      return AppColors.catSecurity;
    case 'health':
      return AppColors.catHealth;
    case 'transport':
      return AppColors.catTransport;
    case 'environment':
      return AppColors.catEnvironment;
    default:
      return AppColors.catOther;
  }
}
