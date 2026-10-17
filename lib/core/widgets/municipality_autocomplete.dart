import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/georef_service.dart';

typedef MunicipalitySearch = Future<List<MunicipalitySuggestion>> Function(
  String query,
);

/// Un único campo para elegir municipio.
///
/// Se escribe parte del nombre y la app sugiere, con la provincia, todos los
/// municipios del país que coinciden: "Saladillo, Buenos Aires", "Saladillo,
/// Córdoba", etc. Reemplaza a los cinco desplegables encadenados (provincia,
/// municipio, departamento, localidad y paraje).
class MunicipalityAutocomplete extends StatefulWidget {
  const MunicipalityAutocomplete({
    super.key,
    required this.onSelected,
    this.label = 'Municipio',
    this.initialText = '',
    this.openUp = false,
    this.search,
  });

  /// Recibe el municipio elegido, o null cuando la persona vuelve a editar el
  /// texto y la elección anterior deja de valer.
  final ValueChanged<MunicipalitySuggestion?> onSelected;
  final String label;
  final String initialText;

  /// Abre la lista de sugerencias hacia arriba. Hace falta cuando el campo
  /// está al pie de la pantalla: hacia abajo la lista queda cortada y no se
  /// ven las opciones.
  final bool openUp;

  /// Solo para pruebas; por defecto consulta GeoRef.
  final MunicipalitySearch? search;

  @override
  State<MunicipalityAutocomplete> createState() =>
      _MunicipalityAutocompleteState();
}

class _MunicipalityAutocompleteState extends State<MunicipalityAutocomplete> {
  late final MunicipalitySearch _search =
      widget.search ?? GeoRefService().searchMunicipalities;

  int _sequence = 0;
  MunicipalitySuggestion? _selected;
  bool _searching = false, _empty = false, _failed = false;

  /// setState seguro: las opciones se piden desde un listener del campo, y a
  /// veces eso ocurre en medio de un build.
  void _status(void Function() change) {
    scheduleMicrotask(() {
      if (mounted) setState(change);
    });
  }

  Future<Iterable<MunicipalitySuggestion>> _options(
    TextEditingValue value,
  ) async {
    final query = value.text.trim();
    if (_selected != null && query == _selected!.label) return const [];
    if (query.length < 2) {
      _status(() => _searching = _empty = _failed = false);
      return const [];
    }

    // Espera a que la persona deje de escribir; si llega otra letra, esta
    // búsqueda queda vieja y se descarta.
    final mine = ++_sequence;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mine != _sequence || !mounted) return const [];

    _status(() {
      _searching = true;
      _empty = _failed = false;
    });
    try {
      final results = await _search(query);
      if (mine != _sequence || !mounted) return const [];
      _status(() {
        _searching = false;
        _empty = results.isEmpty;
      });
      return results;
    } catch (_) {
      if (mine == _sequence && mounted) {
        _status(() {
          _searching = false;
          _failed = true;
        });
      }
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<MunicipalitySuggestion>(
          initialValue: TextEditingValue(text: widget.initialText),
          displayStringForOption: (option) => option.label,
          optionsViewOpenDirection: widget.openUp
              ? OptionsViewOpenDirection.up
              : OptionsViewOpenDirection.down,
          optionsBuilder: _options,
          onSelected: (option) {
            setState(() => _selected = option);
            widget.onSelected(option);
            FocusScope.of(context).unfocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
              ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TextField(
              key: const Key('municipality-input'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: 'Escribí tu municipio, por ejemplo Saladillo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          if (_selected != null) {
                            setState(() => _selected = null);
                            widget.onSelected(null);
                          }
                        },
                      ),
              ),
              onChanged: (text) {
                if (_selected != null && text.trim() != _selected!.label) {
                  setState(() => _selected = null);
                  widget.onSelected(null);
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: _searching
              ? Row(children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Buscando…', style: hint),
                ])
              : _failed
                  ? Text(
                      'No pudimos buscar ahora. Revisá tu conexión e '
                      'intentá de nuevo.',
                      style: hint,
                    )
                  : _empty
                      ? Text(
                          'No encontramos ese municipio. Probá con otra '
                          'parte del nombre.',
                          style: hint,
                        )
                      : Text(
                          _selected != null
                              ? 'Elegiste ${_selected!.label}'
                              : 'Si hay varios con el mismo nombre, fijate '
                                  'en la provincia.',
                          style: hint,
                        ),
        ),
      ],
    );
  }
}
