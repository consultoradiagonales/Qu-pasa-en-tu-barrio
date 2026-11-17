import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:que_pasa_en_tu_barrio/core/router/navigation_policy.dart';
import 'package:que_pasa_en_tu_barrio/data/models/user_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/user_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/home/screens/citizen_home_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'u1';

  @override
  String? get displayName => 'Ana';

  @override
  String? get email => 'ana@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _profile() => UserModel(
      uid: 'u1',
      displayName: 'Vecina 1234',
      realName: 'Ana Pérez',
      email: 'ana@example.com',
      role: UserRole.citizen,
      municipalityId: 'georef_06441',
      municipalityName: 'La Plata',
      createdAt: DateTime(2026, 1, 1),
      reportsCount: 7,
    );

void main() {
  test('la navegación ciudadana comienza en la nueva pantalla de inicio', () {
    expect(citizenStartLocation, '/home');
    expect(signedInDestination(null), '/home');
    expect(signedInDestination('/home'), '/home');
    expect(signedInDestination('report'), '/report/new?resume=1');
  });

  test('el regreso del login conserva la vista del motor ARGWX', () {
    expect(signedInDestination('/clima'), '/clima');
    expect(signedInDestination('/clima?view=map'), '/clima?view=map');
    expect(signedInDestination('/clima?view=https://x.example'), '/home');
  });

  testWidgets('Clima y predicciones abre el motor ARGWX', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const CitizenHomeScreen(
              weatherMapPreview: ColoredBox(color: Colors.blue)),
        ),
        GoRoute(
          path: '/clima',
          builder: (_, state) =>
              Text('clima:${state.uri.queryParameters['view']}'),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('u1')
            .overrideWith((_) => Stream.value(_profile())),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Clima y predicciones'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('home-weather')));
    await tester.tap(find.byKey(const Key('home-weather')));
    await tester.pumpAndSettle();
    expect(find.text('clima:map'), findsOneWidget);
  });

  test('la operación de campo admite operario y responsable global', () {
    expect(canOpenOperations('/field', 'field_worker', enabled: true), isTrue);
    expect(canOpenOperations('/field', 'field_manager', enabled: true), isTrue);
    expect(canOpenOperations('/field', 'citizen', enabled: true), isFalse);
    expect(
        canOpenOperations('/field', 'field_manager', enabled: false), isFalse);
  });

  testWidgets('el inicio muestra mapa meteorológico, cámara y cuenta',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(null)),
      ],
      child: const MaterialApp(
        home: CitizenHomeScreen(
            weatherMapPreview: ColoredBox(color: Colors.blue)),
      ),
    ));
    await tester.pumpAndSettle();

    final camera = find.byKey(const Key('home-camera-quick'));
    final profile = find.byKey(const Key('home-profile-panel'));
    final weatherMap = find.byKey(const Key('home-weather-map'));
    expect(weatherMap, findsOneWidget);
    expect(find.byKey(const Key('home-weather-full')), findsOneWidget);
    expect(camera, findsOneWidget);
    expect(profile, findsOneWidget);
    expect(find.text('Reportar con la cámara'), findsOneWidget);
    expect(find.byKey(const Key('home-login')), findsOneWidget);
    expect(find.byKey(const Key('home-register')), findsOneWidget);

    expect(tester.getRect(weatherMap).center.dy,
        lessThan(tester.getRect(camera).center.dy));
    expect(tester.getRect(camera).center.dy,
        lessThan(tester.getRect(profile).center.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la mitad inferior evita duplicar accesos de la barra inferior',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('u1')
            .overrideWith((_) => Stream.value(_profile())),
      ],
      child: const MaterialApp(
        home: CitizenHomeScreen(
            weatherMapPreview: ColoredBox(color: Colors.blue)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Municipalidad de La Plata'), findsOneWidget);
    expect(
        find.byKey(const Key('municipality-crest-la_plata')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.byKey(const Key('home-alerts')), findsOneWidget);
    expect(find.byKey(const Key('home-map')), findsOneWidget);
    expect(find.byKey(const Key('home-weather')), findsOneWidget);
    expect(find.byKey(const Key('home-my-reports')), findsNothing);
    expect(find.byKey(const Key('home-full-profile')), findsNothing);
    expect(find.byKey(const Key('home-change-municipality')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
