import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Link que cualquiera puede abrir para empezar a usar ConDi, desde un
/// teléfono o una computadora y sin invitación previa.
const conDiInviteUrl = 'https://project-5fc9024a-e961-42b7-9ee.web.app/';

const conDiInviteText =
    'Sumate a ConDi y reportá los problemas de tu barrio con una foto: '
    '$conDiInviteUrl';

/// Abre las opciones para invitar a otras personas a usar la app.
Future<void> showInviteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invitar a usar ConDi',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
                'Compartí este link para que otros vecinos se sumen.'),
            const SizedBox(height: 12),
            SelectableText(
              conDiInviteUrl,
              key: const Key('invite-link'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('invite-whatsapp'),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Compartir por WhatsApp'),
              onPressed: () async {
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(conDiInviteText)}',
                );
                final opened =
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!opened && sheetContext.mounted) {
                  await _copy(sheetContext);
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('invite-copy'),
              icon: const Icon(Icons.link),
              label: const Text('Copiar link'),
              onPressed: () => _copy(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _copy(BuildContext context) async {
  await Clipboard.setData(const ClipboardData(text: conDiInviteText));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copiado. Pegalo donde quieras compartirlo.')),
  );
}
