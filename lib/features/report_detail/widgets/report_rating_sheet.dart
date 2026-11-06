import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Valoración que deja la persona que creó un reporte una vez resuelto.
///
/// Es deliberadamente distinta de la valoración de la aplicación en Google
/// Play: esta se guarda en el propio reporte y la ve el municipio.
class ReportRatingSheet extends StatefulWidget {
  const ReportRatingSheet({
    super.key,
    required this.onSubmit,
  });

  final void Function(int rating, String? comment) onSubmit;

  @override
  State<ReportRatingSheet> createState() => _ReportRatingSheetState();
}

class _ReportRatingSheetState extends State<ReportRatingSheet> {
  final _commentController = TextEditingController();
  int _stars = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_stars == 0) return;
    final comment = _commentController.text.trim();
    widget.onSubmit(_stars, comment.isEmpty ? null : comment);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '¿Qué tan bien se resolvió el problema?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) {
                  final value = index + 1;
                  return IconButton(
                    key: Key('report-rating-star-$value'),
                    tooltip: '$value de 5',
                    onPressed: () => setState(() => _stars = value),
                    icon: Icon(
                      index < _stars ? Icons.star : Icons.star_border,
                      color: AppColors.accent,
                      size: 36,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('report-rating-comment'),
              controller: _commentController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comentario opcional',
                hintText: 'Contanos cómo fue la solución',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('report-rating-submit'),
              onPressed: _stars > 0 ? _submit : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Enviar calificación'),
            ),
          ],
        ),
      ),
    );
  }
}
