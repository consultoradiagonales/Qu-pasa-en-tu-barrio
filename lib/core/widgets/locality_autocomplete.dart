import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/georef_service.dart';

typedef LocalitySearch = Future<List<LocalitySuggestion>> Function(String query);

/// Campo de ciudad/localidad para el formulario de dirección manual.
///
/// No obliga a recorrer divisiones administrativas. Al escribir, muestra las
/// coincidencias junto a su provincia para que un homónimo pueda elegirse sin
/// ambigüedad.
class LocalityAutocomplete extends StatefulWidget {
  const LocalityAutocomplete({
    super.key,
    required this.onSelected,
    this.initialText = '',
    this.search,
  });

  final ValueChanged<LocalitySuggestion?> onSelected;
  final String initialText;
  final LocalitySearch? search;

  @override
  State<LocalityAutocomplete> createState() => _LocalityAutocompleteState();
}

class _LocalityAutocompleteState extends State<LocalityAutocomplete> {
  late final LocalitySearch _search =
      widget.search ?? GeoRefService().searchLocalities;

  int _sequence = 0;
  LocalitySuggestion? _selected;
  bool _searching = false, _empty = false, _failed = false;

  void _status(void Function() change) {
    scheduleMicrotask(() {
      if (mounted) setState(change);
    });
  }

  Future<Iterable<LocalitySuggestion>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    if (_selected != null && query == _selected!.label) return const [];
    if (query.length < 2) {
      _status(() => _searching = _empty = _failed = false);
      return const [];
    }

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
        Autocomplete<LocalitySuggestion>(
          initialValue: TextEditingValue(text: widget.initialText),
          displayStringForOption: (option) => option.label,
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
              key: const Key('locality-input'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Ciudad o localidad',
                hintText: 'Escribí, por ejemplo, Saladillo',
                prefixIcon: const Icon(Icons.location_city_outlined),
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
                      'No pudimos buscar ahora. Revisá tu conexión e intentá de nuevo.',
                      style: hint,
                    )
                  : _empty
                      ? Text(
                          'No encontramos esa ciudad. Probá con otra parte del nombre.',
                          style: hint,
                        )
                      : Text(
                          _selected != null
                              ? 'Elegiste ${_selected!.label}'
                              : 'Si hay homónimos, elegí la provincia correcta.',
                          style: hint,
                        ),
        ),
      ],
    );
  }
}
