import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:que_pasa_en_tu_barrio/features/report_detail/widgets/report_rating_sheet.dart';

void main() {
  Widget host(void Function(int, String?) onSubmit) => MaterialApp(
        home: Scaffold(body: ReportRatingSheet(onSubmit: onSubmit)),
      );

  testWidgets('requiere una estrella antes de enviar', (tester) async {
    await tester.pumpWidget(host((_, __) {}));
    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('report-rating-submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('envía escala de 1 a 5 y comentario opcional', (tester) async {
    int? rating;
    String? comment;
    await tester.pumpWidget(host((value, text) {
      rating = value;
      comment = text;
    }));

    await tester.tap(find.byKey(const Key('report-rating-star-4')));
    await tester.enterText(
      find.byKey(const Key('report-rating-comment')),
      'La reparación quedó muy bien.',
    );
    await tester.tap(find.byKey(const Key('report-rating-submit')));

    expect(rating, 4);
    expect(comment, 'La reparación quedó muy bien.');
  });
}
