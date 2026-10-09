import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/auth_service.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/report/screens/new_report_screen.dart';
import '../../features/report_detail/screens/report_detail_screen.dart';
import '../../features/my_reports/screens/my_reports_screen.dart';
import '../../features/field/screens/field_home_screen.dart';
import '../../features/field/screens/task_detail_screen.dart';
import '../../features/field/screens/work_in_progress_screen.dart';
import '../../features/coordinator/screens/coordinator_home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';

/// Proveedor del router — se reconstruye cuando cambia el estado de auth
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isOnAuth = state.matchedLocation.startsWith('/auth');
      final isOnSplash = state.matchedLocation == '/splash';

      // Si está en splash, no redirigir (el splash decide)
      if (isOnSplash) return null;

      // Si no está logueado y no está en pantalla de auth, mandar al login
      if (!isLoggedIn && !isOnAuth) return '/auth/welcome';

      // Si está logueado y está en pantalla de auth, mandar al home según rol
      if (isLoggedIn && isOnAuth) {
        final currentRole = ref.read(currentUserRoleProvider);
        if (currentRole == null) return null;
        return _homeByRole(currentRole);
      }

      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth
      GoRoute(
        path: '/auth/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Ciudadano — mapa principal con shell de navegación
      ShellRoute(
        builder: (context, state, child) => _CitizenShell(child: child),
        routes: [
          GoRoute(
            path: '/map',
            builder: (context, state) => const MapScreen(),
          ),
          GoRoute(
            path: '/my-reports',
            builder: (context, state) => const MyReportsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Crear reporte (modal, sin shell)
      GoRoute(
        path: '/report/new',
        builder: (context, state) => const NewReportScreen(),
      ),

      // Detalle de reporte (ciudadano y todos los roles)
      GoRoute(
        path: '/report/:id',
        builder: (context, state) => ReportDetailScreen(
          reportId: state.pathParameters['id']!,
        ),
      ),

      // Equipo de campo
      ShellRoute(
        builder: (context, state, child) => _FieldShell(child: child),
        routes: [
          GoRoute(
            path: '/field',
            builder: (context, state) => const FieldHomeScreen(),
          ),
          GoRoute(
            path: '/field/notifications',
            builder: (context, state) =>
                const NotificationsScreen(forFieldWorker: true),
          ),
          GoRoute(
            path: '/field/task/:id',
            builder: (context, state) => TaskDetailScreen(
              reportId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/field/task/:id/work',
            builder: (context, state) => WorkInProgressScreen(
              reportId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      // Coordinador
      ShellRoute(
        builder: (context, state, child) => _CoordinatorShell(child: child),
        routes: [
          GoRoute(
            path: '/coordinator',
            builder: (context, state) => const CoordinatorHomeScreen(),
          ),
          GoRoute(
            path: '/coordinator/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Página no encontrada: ${state.error}'),
      ),
    ),
  );
});

/// Retorna la ruta home según el rol del usuario
String _homeByRole(String? role) {
  switch (role) {
    case 'field_worker':
      return '/field';
    case 'coordinator':
    case 'admin':
    case 'moderator':
      return '/coordinator';
    default:
      return '/map';
  }
}

// ─── Shells de navegación ────────────────────────────────────────────────────

/// Barra de navegación inferior para ciudadanos
class _CitizenShell extends StatelessWidget {
  final Widget child;
  const _CitizenShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFromLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => _navigate(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Mis reportes',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alertas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith('/my-reports')) return 1;
    if (location.startsWith('/notifications')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _navigate(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/map');
        break;
      case 1:
        context.go('/my-reports');
        break;
      case 2:
        context.go('/notifications');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }
}

/// Shell para equipo de campo (simplificado, sin NavigationBar compleja)
class _FieldShell extends StatelessWidget {
  final Widget child;
  const _FieldShell({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Shell para coordinador
class _CoordinatorShell extends StatelessWidget {
  final Widget child;
  const _CoordinatorShell({required this.child});

  @override
  Widget build(BuildContext context) => child;
}
