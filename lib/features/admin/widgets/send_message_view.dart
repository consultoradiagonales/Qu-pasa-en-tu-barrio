import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/repositories/admin_messages_repository.dart';
import '../../../data/repositories/push_reach_repository.dart';

/// Redacta un mensaje para los vecinos. El servidor lo deja en la bandeja de
/// cada destinatario y envía push cuando el celular tiene un token válido.
class SendMessageView extends ConsumerStatefulWidget {
  const SendMessageView({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  ConsumerState<SendMessageView> createState() => _SendMessageViewState();
}

enum _Audience { municipality, everyone }

class _SendMessageViewState extends ConsumerState<SendMessageView> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  _Audience _audience = _Audience.municipality;
  bool _sending = false;
  String? _result;
  bool _failed = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().length >= 3 && _body.text.trim().length >= 3;

  Future<void> _send() async {
    final everyone = _audience == _Audience.everyone;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Enviar mensaje?'),
        content: Text(everyone
            ? 'Lo recibirán todos los usuarios de la app.'
            : 'Lo recibirán los vecinos de tu municipio.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _result = null;
    });
    try {
      final municipalityId = ref.read(reachMunicipalityIdProvider);
      final response = await ref.read(adminMessagesRepositoryProvider).send(
            title: _title.text.trim(),
            body: _body.text.trim(),
            senderMunicipalityId: municipalityId,
            audience: everyone
                ? MessageAudience.everyone
                : MessageAudience.municipality,
          );
      if (!mounted) return;
      setState(() {
        _failed = false;
        _result = _deliveryMessage(response);
        _title.clear();
        _body.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _result = mensajeDeError(error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _deliveryMessage(MessageDispatchResult response) {
    if (response.total == 0) {
      return 'No hay vecinos para recibir este mensaje todavía.';
    }
    if (response.pushed == 0) {
      return 'Mensaje disponible para ${response.total} personas en la '
          'bandeja de ConDi. Ningún celular tiene notificaciones activas.';
    }
    if (response.inApp == 0) {
      return 'Notificación enviada a ${response.pushed} persona${response.pushed == 1 ? '' : 's'}.';
    }
    return 'Notificación enviada a ${response.pushed} persona${response.pushed == 1 ? '' : 's'}; '
        '${response.inApp} la verá${response.inApp == 1 ? '' : 'n'} al abrir ConDi.';
  }

  // Clave null = todos los usuarios. Si el municipio aún no se conoce no se
  // consulta nada y el aviso no se muestra.
  AsyncValue<PushReach>? _watchReach() {
    if (_audience == _Audience.everyone) {
      return ref.watch(pushReachProvider(null));
    }
    final municipalityId = ref.watch(reachMunicipalityIdProvider);
    if (municipalityId.isEmpty) return null;
    return ref.watch(pushReachProvider(municipalityId));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Enviar mensaje a los vecinos',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
            'El mensaje queda en la bandeja y, si el celular está habilitado, llega como notificación.'),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<_Audience>(
                key: const Key('message-audience'),
                initialValue: _audience,
                decoration: const InputDecoration(labelText: 'Destinatarios'),
                items: [
                  const DropdownMenuItem(
                      value: _Audience.municipality,
                      child: Text('Vecinos de mi municipio')),
                  if (widget.isAdmin)
                    const DropdownMenuItem(
                        value: _Audience.everyone,
                        child: Text('Todos los usuarios de la app')),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _audience = value ?? _audience),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('message-title'),
                controller: _title,
                maxLength: 120,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  helperText: 'Hasta 120 caracteres.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('message-body'),
                controller: _body,
                maxLength: 4000,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Mensaje',
                  alignLabelWithHint: true,
                  helperText:
                      'Hasta 4.000 caracteres. El mensaje completo queda en la bandeja.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _ReachNotice(reach: _watchReach()),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('message-send'),
                onPressed: _valid && !_sending ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Enviando…' : 'Enviar mensaje'),
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                Text(_result!,
                    style: TextStyle(
                        color: _failed
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Alcance real del envío, antes de enviar. Si el conteo falla no bloquea nada.
class _ReachNotice extends StatelessWidget {
  const _ReachNotice({required this.reach});

  final AsyncValue<PushReach>? reach;

  @override
  Widget build(BuildContext context) {
    final value = reach;
    if (value == null) return const SizedBox.shrink();
    return value.when(
      loading: () => const Row(children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('Calculando a cuántas personas llega…'),
      ]),
      error: (_, __) => const Text(
          'No pudimos calcular el alcance del envío. Podés enviar igual.',
          key: Key('message-reach-error')),
      data: (r) => Column(
        key: const Key('message-reach'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.total} usuarios en total, ${r.withPush} con '
              'notificaciones activas en el celular, ${r.inAppOnly} solo '
              'recibirán el aviso dentro de la app.'),
          if (r.withPush == 0) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('message-reach-warning'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                  'Por ahora nadie puede recibir la notificación en el '
                  'celular. Para recibirla, cada persona debe instalar la '
                  'última versión de la app, iniciar sesión y aceptar el '
                  'permiso de notificaciones. Mientras tanto, el mensaje se '
                  'verá dentro de la app.'),
            ),
          ],
        ],
      ),
    );
  }
}
