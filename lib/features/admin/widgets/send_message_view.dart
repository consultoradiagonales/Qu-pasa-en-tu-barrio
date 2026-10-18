import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/repositories/push_reach_repository.dart';

/// Redacta un mensaje y lo envía como notificación a la app de los vecinos.
/// El permiso real lo valida la Cloud Function `sendCustomMessage`; el rol que
/// recibe esta vista solo decide qué opciones se ofrecen.
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
  late final _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');
  _Audience _audience = _Audience.municipality;
  bool _sending = false;
  String? _result;
  bool _failed = false;

  // Un id por mensaje: si se reintenta el mismo envío, el servidor no lo
  // duplica. Se renueva solo cuando el envío salió bien.
  String _requestId = _newId();

  static String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
  }

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
      final response =
          await _functions.httpsCallable('sendCustomMessage').call({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'requestId': _requestId,
        'audience': {'type': everyone ? 'all' : 'municipality'},
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      final total = data['total'] ?? 0;
      final pushed = data['pushed'] ?? 0;
      if (!mounted) return;
      setState(() {
        _failed = false;
        _result = total == 0
            ? 'No hay vecinos para recibir este mensaje todavía.'
            : 'Enviado a $total personas ($pushed con notificación en el '
                'celular; el resto lo ve dentro de la app).';
        _title.clear();
        _body.clear();
        _requestId = _newId();
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
        const Text('Aparece como notificación en el celular y queda en la '
            'bandeja de la app.'),
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
                    : (value) =>
                        setState(() => _audience = value ?? _audience),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('message-title'),
                controller: _title,
                maxLength: 80,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Título'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('message-body'),
                controller: _body,
                maxLength: 280,
                maxLines: 4,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Mensaje'),
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
