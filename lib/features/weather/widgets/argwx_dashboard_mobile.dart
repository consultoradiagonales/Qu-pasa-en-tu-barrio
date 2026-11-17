import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/argwx_service.dart';

/// El tablero completo de ARGWX permanece dentro de la pantalla de ConDi.
class ArgwxDashboard extends StatefulWidget {
  const ArgwxDashboard({super.key});

  @override
  State<ArgwxDashboard> createState() => _ArgwxDashboardState();
}

class _ArgwxDashboardState extends State<ArgwxDashboard> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _loading = true;
              _failed = false;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) {
            setState(() => _loading = false);
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() {
              _loading = false;
              _failed = true;
            });
          }
        },
        onNavigationRequest: (request) {
          final url = Uri.tryParse(request.url);
          final root = Uri.parse(ArgwxService.dashboardUrl);
          return url != null &&
                  url.scheme == 'https' &&
                  url.host == root.host &&
                  url.path.startsWith(root.path)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(ArgwxService.dashboardUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
        if (_failed)
          Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo cargar el mapa meteorológico.'),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _controller.loadRequest(
                        Uri.parse(ArgwxService.dashboardUrl),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
