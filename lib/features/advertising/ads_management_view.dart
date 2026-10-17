import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/services/auth_service.dart';
import 'local_ad.dart';
import 'local_ads_repository.dart';

class AdsManagementView extends ConsumerWidget {
  const AdsManagementView({super.key, required this.municipalityId});

  final String municipalityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserRoleProvider) != 'admin') {
      return const Center(
        child: Text('La publicidad la gestiona el administrador.'),
      );
    }
    final ads = ref.watch(managedAdsProvider(municipalityId));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Publicidad de comercios',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        const Text(
          'El banner se muestra en el zócalo ciudadano. Elegí cierre '
          'inmediato o siete segundos según el abono contratado.',
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Crear anuncio'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _AdEditor(municipalityId: municipalityId),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...ads.when(
          data: (items) => [
            for (final ad in items)
              Card(
                child: ListTile(
                  title: Text(ad.business),
                  subtitle: Text(
                    '${ad.message}\n'
                    '${ad.startsAt.toLocal().toString().substring(0, 10)} — '
                    '${ad.endsAt.toLocal().toString().substring(0, 10)} · '
                    '${ad.dismissMode.label} · '
                    '${ad.visibleAt(DateTime.now()) ? "En circulación" : "Fuera de circulación"}',
                  ),
                  isThreeLine: true,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _AdEditor(
                      municipalityId: municipalityId,
                      ad: ad,
                    ),
                  ),
                  trailing: Switch(
                    value: ad.active,
                    onChanged: (value) => _setActive(context, ref, ad, value),
                  ),
                ),
              ),
          ],
          loading: () => [const LinearProgressIndicator()],
          error: (_, __) => [
            const Text('No pudimos cargar los anuncios. Intentá nuevamente.'),
          ],
        ),
      ],
    );
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    LocalAd ad,
    bool active,
  ) async {
    try {
      await ref.read(localAdsRepositoryProvider).save(
            adId: ad.id,
            municipalityId: ad.municipalityId,
            business: ad.business,
            message: ad.message,
            imageUrl: ad.imageUrl,
            link: ad.link,
            startsAt: ad.startsAt,
            endsAt: ad.endsAt,
            active: active,
            dismissMode: ad.dismissMode,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo cambiar el anuncio.'),
        ));
      }
    }
  }
}

class _AdEditor extends ConsumerStatefulWidget {
  const _AdEditor({required this.municipalityId, this.ad});

  final String municipalityId;
  final LocalAd? ad;

  @override
  ConsumerState<_AdEditor> createState() => _AdEditorState();
}

class _AdEditorState extends ConsumerState<_AdEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _business;
  late final TextEditingController _message;
  late final TextEditingController _image;
  late final TextEditingController _link;
  late DateTime _start;
  late DateTime _end;
  late LocalAdDismissMode _dismissMode;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ad = widget.ad;
    _business = TextEditingController(text: ad?.business);
    _message = TextEditingController(text: ad?.message);
    _image = TextEditingController(text: ad?.imageUrl);
    _link = TextEditingController(text: ad?.link);
    _start = ad?.startsAt.toLocal() ?? DateUtils.dateOnly(DateTime.now());
    _end = ad?.endsAt.toLocal() ??
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 30));
    _dismissMode = ad?.dismissMode ?? LocalAdDismissMode.closeNow;
  }

  @override
  void dispose() {
    for (final controller in [_business, _message, _image, _link]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _date(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() {
        if (start) {
          _start = date;
        } else {
          _end = date;
        }
      });
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw Exception('La imagen supera 5 MB.');
      }
      final mime = file.mimeType ??
          (file.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      if (!['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
        throw Exception('Usá JPG, PNG o WebP.');
      }
      final imageRef = FirebaseStorage.instance.ref(
        'advertising/${widget.municipalityId}/'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await imageRef
          .putData(bytes, SettableMetadata(contentType: mime))
          .timeout(const Duration(seconds: 45));
      final url = await imageRef.getDownloadURL();
      if (mounted) _image.text = url;
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo subir la imagen. Usá JPG, PNG o WebP de hasta 5 MB.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'La fecha de fin debe ser posterior al inicio.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(localAdsRepositoryProvider).save(
            adId: widget.ad?.id,
            municipalityId: widget.municipalityId,
            business: _business.text.trim(),
            message: _message.text.trim(),
            imageUrl: _image.text.trim(),
            link: _link.text.trim(),
            startsAt: _start,
            endsAt: _end,
            active: widget.ad?.active ?? true,
            dismissMode: _dismissMode,
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo guardar. Revisá la conexión y tus permisos.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ad == null ? 'Nuevo anuncio local' : 'Editar anuncio'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _business,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Comercio'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Ingresá el comercio'
                      : null,
                ),
                TextFormField(
                  controller: _message,
                  maxLength: 180,
                  decoration:
                      const InputDecoration(labelText: 'Mensaje del anuncio'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Ingresá un mensaje'
                      : null,
                ),
                TextFormField(
                  controller: _link,
                  decoration: const InputDecoration(
                    labelText: 'Enlace HTTPS (web o WhatsApp)',
                  ),
                  validator: (value) => LocalAd.validLink((value ?? '').trim())
                      ? null
                      : 'Ingresá un enlace HTTPS válido',
                ),
                TextFormField(
                  controller: _image,
                  decoration:
                      const InputDecoration(labelText: 'URL de imagen (opcional)'),
                  validator: (value) => (value ?? '').trim().isEmpty ||
                          LocalAd.validLink(value!.trim())
                      ? null
                      : 'Ingresá una URL HTTPS',
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Subir imagen del comercio'),
                ),
                DropdownButtonFormField<LocalAdDismissMode>(
                  value: _dismissMode,
                  decoration: const InputDecoration(
                    labelText: 'Cierre del banner',
                    helperText: 'Definilo según el abono contratado.',
                  ),
                  items: LocalAdDismissMode.values
                      .map((mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (mode) {
                          if (mode != null) {
                            setState(() => _dismissMode = mode);
                          }
                        },
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _date(true),
                      child: Text('Inicio: ${_start.toString().substring(0, 10)}'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _date(false),
                      child: Text('Fin: ${_end.toString().substring(0, 10)}'),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
