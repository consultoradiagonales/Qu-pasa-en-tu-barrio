import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/features/profile/invite_sheet.dart';

void main() {
  test('la invitación comparte un link público de ConDi', () {
    expect(conDiInviteUrl, startsWith('https://'));
    expect(conDiInviteText, contains(conDiInviteUrl));
  });

  testWidgets('la hoja de invitación muestra el link, WhatsApp y copiar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInviteSheet(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Invitar a usar ConDi'), findsOneWidget);
    expect(find.byKey(const Key('invite-link')), findsOneWidget);
    expect(find.byKey(const Key('invite-whatsapp')), findsOneWidget);
    expect(find.byKey(const Key('invite-copy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
