import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/main.dart';

void main() {
  testWidgets(
      'Un fallo de inicio conserva un estado de error y ofrece reintentar sin simular casos',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(StartupUnavailableApp(onRetry: () => retries++));
    expect(find.text('No pudimos iniciar ConDi'), findsOneWidget);
    expect(find.textContaining('Demo nativa'), findsNothing);
    expect(find.text('Asignar Cuadrilla Norte'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    expect(retries, 1);
  });
}
