import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'navigation_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/services/auth_service.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/select_municipality_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/report/screens/new_report_screen.dart';
import '../../features/report_detail/screens/report_detail_screen.dart';
import '../../features/my_reports/screens/my_reports_screen.dart';
import '../../features/field/screens/field_home_screen.dart';
import '../../features/field/screens/task_detail_screen.dart';
import '../../features/field/screens/work_in_progress_screen.dart';
import '../../features/coordinator/screens/coordinator_home_screen.dart';
import '../../features/admin/screens/admin_console_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/advertising/local_ads_banner.dart';
import '../services/device_profile_service.dart';

class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
  late final dynamic _sub;

  /// Expuesto para que el router pueda reevaluar el redirect cuando cambia
  /// algo que no es el estado de sesión, como el rol leído de Firestore.
  @override
  void notifyListeners() => super.notifyListeners();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Proveedor del router — se crea UNA vez; el redirect se reejercuta via refreshListenable
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier();
  ref.onDispose(notifier.dispose);

  // El guard por rol depende de la lectura del perfil, que llega después del
  // cambio de sesión. Sin esto el redirect se evalúa una sola vez, cuando el
  // rol todavía es desconocido, y nunca se vuelve a aplicar.
  ref.listen(userRoleResolvedProvider, (_, __) => notifier.notifyListeners());
  ref.listen(currentUserRoleProvider, (_, __) => notifier.notifyListeners());
  ref.listen(
      currentUserMunicipalityProvider, (_, __) => notifier.notifyListeners());

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final isOnSplash = state.matchedLocation == '/splash';
      // La elección de municipio cuelga de /auth pero es para alguien que ya
      // inició sesión, así que no entra en el rebote de las pantallas de auth:
      // si entrara, el guard de más abajo la devolvería acá sin fin.
      final isOnMunicipio = state.matchedLocation.startsWith('/auth/municipio');
      final isOnAuth =
          state.matchedLocation.startsWith('/auth') && !isOnMunicipio;

      // Si está en splash, no redirigir (el splash decide)
      if (isOnSplash) return null;

      final target = state.matchedLocation;
      final isReport = target == '/report/new';
      // Photo capture is public. Authentication is requested only on send.
      if (!isLoggedIn && !isOnAuth && !isReport) {
        final next = isOnMunicipio ? 'report' : target;
        return '/auth/login?next=${Uri.encodeComponent(next)}';
      }
      if (isLoggedIn && isOnAuth) {
        if (ref.read(currentUserRoleProvider) == null) return null;
        return signedInDestination(state.uri.queryParameters['next']);
      }
      if (isOperationsPath(target)) {
        if (!(kIsWeb || operationsBuild)) return citizenStartLocation;
        if (ref.read(userRoleResolvedProvider) &&
            !canOpenOperations(target, ref.read(currentUserRoleProvider),
                enabled: true)) {
          return citizenStartLocation;
        }
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
        path: '/auth/municipio',
        builder: (context, state) => const SelectMunicipalityScreen(),
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

      // Consola web de gestión y analítica. Comparte las mismas reglas y
      // streams que la app, por lo que nunca expone datos fuera del backend.
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminConsoleScreen(),
      ),

      // Crear reporte (modal, sin shell)
      GoRoute(
        path: '/report/new',
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return NewReportScreen(
            startWithCamera: query['resume'] != '1',
            initialAddressMode: query['mode'] == 'manual',
            initialLocation: _queryLocation(query['lat'], query['lng']),
          );
        },
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
    errorBuilder: (context, state) => const Scaffold(
      body: Center(
        child: Text('No encontramos esa página.'),
      ),
    ),
  );
});

LatLng? _queryLocation(String? lat, String? lng) {
  final latitude = double.tryParse(lat ?? '');
  final longitude = double.tryParse(lng ?? '');
  if (latitude == null || longitude == null) return null;
  return LatLng(latitude, longitude);
}

// ─── Shells de navegación ────────────────────────────────────────────────────

/// Barra de navegación inferior para ciudadanos
class _CitizenShell extends ConsumerStatefulWidget {
  final Widget child;
  const _CitizenShell({required this.child});

  @override
  ConsumerState<_CitizenShell> createState() => _CitizenShellState();
}

class _CitizenShellState extends ConsumerState<_CitizenShell> {
  bool _consentChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _consentChecked) return;
      _consentChecked = true;
      await DeviceProfileService.askIfNeeded(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFromLocation(location);
    final municipalityId = ref.watch(currentUserMunicipalityProvider) ?? '';

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalAdsBanner(municipalityId: municipalityId),
          NavigationBar(
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
