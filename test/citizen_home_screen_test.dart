import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('divide el inicio entre cámara rápida y cuenta', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(null)),
      ],
      child: const MaterialApp(home: CitizenHomeScreen()),
    ));
    await tester.pumpAndSettle();

    final camera = find.byKey(const Key('home-camera-quick'));
    final profile = find.byKey(const Key('home-profile-panel'));
    expect(camera, findsOneWidget);
    expect(profile, findsOneWidget);
    expect(find.text('Reportar con la cámara'), findsOneWidget);
    expect(find.byKey(const Key('home-login')), findsOneWidget);
    expect(find.byKey(const Key('home-register')), findsOneWidget);

    final cameraRect = tester.getRect(camera);
    final profileRect = tester.getRect(profile);
    expect(cameraRect.center.dy, lessThan(profileRect.center.dy));
    expect((cameraRect.height - profileRect.height).abs(), lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la mitad inferior ofrece alertas, reportes, mapa y perfil',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('u1')
            .overrideWith((_) => Stream.value(_profile())),
      ],
      child: const MaterialApp(home: CitizenHomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Municipalidad de La Plata'), findsOneWidget);
    expect(
        find.byKey(const Key('municipality-crest-la_plata')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.byKey(const Key('home-alerts')), findsOneWidget);
    expect(find.byKey(const Key('home-my-reports')), findsOneWidget);
    expect(find.byKey(const Key('home-map')), findsOneWidget);
    expect(find.byKey(const Key('home-full-profile')), findsOneWidget);
    expect(find.byKey(const Key('home-change-municipality')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
