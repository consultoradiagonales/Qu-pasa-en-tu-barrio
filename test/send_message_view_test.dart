import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/features/admin/widgets/send_message_view.dart';

Widget _host(bool isAdmin) => MaterialApp(
      home: Scaffold(body: SendMessageView(isAdmin: isAdmin)),
    );

void main() {
  testWidgets('el botón se habilita solo con título y mensaje', (tester) async {
    await tester.pumpWidget(_host(false));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byKey(const Key('message-send')));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('message-title')), 'Corte');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('message-body')), 'Sin agua en el centro');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('un coordinador no ve "Todos los usuarios"', (tester) async {
    await tester.pumpWidget(_host(false));
    await tester.tap(find.byKey(const Key('message-audience')));
    await tester.pumpAndSettle();
    expect(find.text('Todos los usuarios de la app'), findsNothing);
    expect(find.text('Vecinos de mi municipio'), findsWidgets);
  });

  testWidgets('el administrador sí ve "Todos los usuarios"', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.tap(find.byKey(const Key('message-audience')));
    await tester.pumpAndSettle();
    expect(find.text('Todos los usuarios de la app'), findsWidgets);
  });
}
