import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/data/models/user_model.dart';
import 'package:que_pasa_en_tu_barrio/data/repositories/user_repository.dart';
import 'package:que_pasa_en_tu_barrio/data/services/auth_service.dart';
import 'package:que_pasa_en_tu_barrio/features/auth/screens/select_municipality_screen.dart';
import 'package:que_pasa_en_tu_barrio/features/profile/screens/profile_screen.dart';

class _FakeUser implements User {
  @override
  String get uid => 'u1';

  @override
  String? get email => 'ana@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _profile(UserRole role) => UserModel(
      uid: 'u1',
      displayName: 'Vecina 1234',
      realName: 'Ana Pérez',
      email: 'ana@example.com',
      role: role,
      municipalityId: 'georef_06441',
      municipalityName: 'La Plata',
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpProfile(WidgetTester tester, UserRole role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
        currentUserProfileProvider('u1')
            .overrideWith((_) => Stream.value(_profile(role))),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('solo acepta destinos internos conocidos al guardar municipio', () {
    expect(municipalityReturnDestination('report'), '/report/new?resume=1');
    expect(municipalityReturnDestination('profile'), '/profile');
    expect(municipalityReturnDestination('home'), '/home');
    expect(municipalityReturnDestination('https://example.com'), '/home');
  });

  testWidgets('el perfil ciudadano permite cambiar el municipio',
      (tester) async {
    await _pumpProfile(tester, UserRole.citizen);

    expect(
      find.byKey(const Key('profile-change-municipality')),
      findsOneWidget,
    );
    expect(find.text('Municipio y alertas climáticas'), findsOneWidget);
  });

  testWidgets('el perfil operativo no permite cambiar el municipio',
      (tester) async {
    await _pumpProfile(tester, UserRole.coordinator);

    expect(
      find.byKey(const Key('profile-change-municipality')),
      findsNothing,
    );
  });
}
