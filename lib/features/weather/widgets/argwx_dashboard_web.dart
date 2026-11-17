import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../data/services/argwx_service.dart';

/// En web, el tablero se muestra en un marco dentro de la misma ruta.
class ArgwxDashboard extends StatefulWidget {
  const ArgwxDashboard({super.key});

  @override
  State<ArgwxDashboard> createState() => _ArgwxDashboardState();
}

class _ArgwxDashboardState extends State<ArgwxDashboard> {
  static const _viewType = 'condi-argwx-dashboard';

  /// La fábrica se registra una sola vez por proceso: volver a registrar el
  /// mismo tipo falla, y un tipo nuevo por cada montaje acumulaba fábricas.
  static bool _registered = false;

  /// Marcos creados por la fábrica, por id de vista, para que cada instancia
  /// escuche la carga de su propio marco.
  static final Map<int, web.HTMLIFrameElement> _frames = {};

  static void _ensureRegistered() {
    if (_registered) return;
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = ArgwxService.dashboardUrl
        ..title = 'Mapa meteorológico de ConDi';
      iframe.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
      _frames[viewId] = iframe;
      return iframe;
    });
  }

  bool _loading = true;
  int? _viewId;

  @override
  void initState() {
    super.initState();
    _ensureRegistered();
  }

  void _onCreated(int viewId) {
    _viewId = viewId;
    final iframe = _frames[viewId];
    if (iframe == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    iframe.addEventListener(
      'load',
      ((web.Event _) {
        if (mounted) setState(() => _loading = false);
      }).toJS,
    );
  }

  @override
  void dispose() {
    final id = _viewId;
    if (id != null) _frames.remove(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(
            child: HtmlElementView(
              viewType: _viewType,
              onPlatformViewCreated: _onCreated,
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Cargando mapa meteorológico',
              ),
            ),
        ],
      );
}
