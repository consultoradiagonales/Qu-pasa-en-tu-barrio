import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/argwx_service.dart';
import '../../../data/services/auth_service.dart';

String _when(DateTime? date) {
  if (date == null) return 'sin fecha';
  final d = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)} h';
}

Color _onLevel(ArgwxLevel level) =>
    level == ArgwxLevel.yellow ? const Color(0xFF14283F) : Colors.white;

/// Perfil → Clima y prevención. Consulta voluntaria del motor ARGWX para el
/// municipio de la cuenta. No activa notificaciones ni pide ubicación.
class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = user == null
        ? null
        : ref.watch(currentUserProfileProvider(user.uid)).valueOrNull;
    final argwxId = ArgwxService.argwxIdFor(profile?.municipalityId);

    return Scaffold(
      appBar: AppBar(title: const Text('Clima y prevención')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : argwxId == null
              ? const _NotCovered()
              : WeatherBody(
                  argwxId: argwxId,
                  municipalityName: profile.municipalityName ?? 'Tu municipio',
                ),
    );
  }
}

class _NotCovered extends StatelessWidget {
  const _NotCovered();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 48, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'Por ahora el pronóstico municipal cubre los 135 partidos de la '
            'provincia de Buenos Aires. Las alertas oficiales del SMN siguen '
            'llegando como hasta ahora.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class WeatherBody extends ConsumerStatefulWidget {
  const WeatherBody({
    super.key,
    required this.argwxId,
    required this.municipalityName,
  });

  final String argwxId;
  final String municipalityName;

  @override
  ConsumerState<WeatherBody> createState() => _WeatherBodyState();
}

class _WeatherBodyState extends ConsumerState<WeatherBody> {
  int _hours = 24;
  Future<ArgwxFloods>? _floods;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(argwxForecastProvider(widget.argwxId));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(argwxForecastProvider(widget.argwxId).future),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.municipalityName,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 24, label: Text('24 h')),
              ButtonSegment(value: 48, label: Text('48 h')),
              ButtonSegment(value: 72, label: Text('72 h')),
            ],
            selected: {_hours},
            onSelectionChanged: (s) => setState(() => _hours = s.first),
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => _Unavailable(
              onRetry: () => ref.invalidate(argwxForecastProvider(widget.argwxId)),
            ),
            data: (forecast) => _ForecastView(forecast: forecast, hours: _hours),
          ),
          const Divider(height: 40),
          _FloodsSection(
            future: _floods,
            onLoad: () => setState(() {
              _floods = ref.read(argwxServiceProvider).floods(widget.argwxId);
            }),
          ),
          const Divider(height: 40),
          const _Disclaimer(),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Datos meteorológicos no disponibles por el momento. '
              'Esto no significa que no haya riesgo: consultá las alertas '
              'oficiales del SMN.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _ForecastView extends StatelessWidget {
  const _ForecastView({required this.forecast, required this.hours});
  final ArgwxForecast forecast;
  final int hours;

  @override
  Widget build(BuildContext context) {
    final window = forecast.windows
        .where((w) => w.hours == hours)
        .cast<ArgwxWindow?>()
        .firstWhere((_) => true, orElse: () => null);
    final m = window?.municipality;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!forecast.isLive)
          const _Notice(
            icon: Icons.science_outlined,
            text: 'Datos de demostración: no usar para decisiones.',
          ),
        if (forecast.isStale)
          _Notice(
            icon: Icons.history,
            text: 'Último dato del ${_when(forecast.generatedAt)}. '
                'Puede no reflejar la situación actual.',
          ),
        if (window == null || m == null)
          const _Notice(
            icon: Icons.help_outline,
            text: 'Sin dato para este período. No significa ausencia de riesgo.',
          )
        else ...[
          Text(
            '${window.label} · hasta ${_when(window.validTo)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('argwx-level'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(m.level.color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.level == ArgwxLevel.green
                      ? 'Nivel verde'
                      : 'Alerta ${m.level.label.toLowerCase()}'
                          '${m.hazard == null ? '' : ' por ${m.hazard}'}',
                  style: TextStyle(
                    color: _onLevel(m.level),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(m.level.meaning,
                    style: TextStyle(color: _onLevel(m.level))),
                const SizedBox(height: 8),
                Text(
                  m.isOfficialSmn
                      ? 'Fuente: alerta oficial del SMN'
                      : 'Fuente: análisis ConDi · coinciden '
                          '${m.consensus ?? '-'} modelos',
                  style: TextStyle(
                    color: _onLevel(m.level),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (m.rainMm != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.water_drop_outlined),
              title: Text('Lluvia estimada: ${m.rainMm!.toStringAsFixed(1)} mm'),
              subtitle: m.rainOver10mmPercent == null
                  ? null
                  : Text('Probabilidad de superar 10 mm: '
                      '${m.rainOver10mmPercent!.round()} %'),
            ),
          if (m.drivers.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Ver detalle'),
              children: [
                for (final d in m.drivers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(d),
                  ),
              ],
            ),
          Text(
            'Actualizado: ${_when(forecast.generatedAt)} · '
            '${forecast.modelCount} modelos',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _FloodsSection extends StatelessWidget {
  const _FloodsSection({required this.future, required this.onLoad});
  final Future<ArgwxFloods>? future;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    const title = Text('Ríos, arroyos y canales',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
    if (future == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 8),
          const Text(
              'Consultá si hay cursos de agua con aviso en tu partido. '
              'La consulta descarga unos 4 MB.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('argwx-load-floods'),
            onPressed: onLoad,
            icon: const Icon(Icons.waves_outlined),
            label: const Text('Consultar cursos de agua'),
          ),
        ],
      );
    }
    return FutureBuilder<ArgwxFloods>(
      future: future,
      builder: (context, snap) {
        final children = <Widget>[title, const SizedBox(height: 8)];
        if (snap.connectionState != ConnectionState.done) {
          children.add(const Center(child: CircularProgressIndicator()));
        } else if (snap.hasError || !snap.hasData) {
          children.add(const Text(
              'No se pudo consultar ahora. Esto no significa que no haya '
              'riesgo hídrico.'));
          children.add(TextButton(onPressed: onLoad, child: const Text('Reintentar')));
        } else {
          final floods = snap.data!;
          if (floods.isStale) {
            children.add(_Notice(
              icon: Icons.history,
              text: 'Último dato del ${_when(floods.generatedAt)}.',
            ));
          }
          if (floods.courses.isEmpty) {
            children.add(const Text(
                'Sin cursos de agua con aviso para tu partido en este momento.'));
          }
          for (final c in floods.courses) {
            children.add(Card(
              child: ExpansionTile(
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: Color(c.level.color),
                ),
                title: Text(c.name),
                subtitle: Text(
                  'Aviso ${c.level.label.toLowerCase()}'
                  '${c.type.isEmpty ? '' : ' · ${c.type}'}'
                  '${c.flowConfirmed ? ' · caudal medido' : ' · estimado por modelos'}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [for (final r in c.reasons) Text('• $r')],
              ),
            ));
          }
          children.add(Text('Actualizado: ${_when(floods.generatedAt)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF7E6),
      child: ListTile(
        leading: Icon(icon, color: AppColors.accent),
        title: Text(text, style: const TextStyle(color: AppColors.onSurface)),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'El análisis ConDi combina varios modelos meteorológicos. El '
          'porcentaje de modelos que coinciden no es una probabilidad de '
          'ocurrencia. Ante una emergencia, seguí las indicaciones del SMN y '
          'de Defensa Civil.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://www.smn.gob.ar/'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Alertas oficiales del SMN'),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(ArgwxService.dashboardUrl),
                  mode: LaunchMode.externalApplication),
              child: const Text('Tablero completo'),
            ),
          ],
        ),
        const Text(
          'Datos: modelos meteorológicos vía Open-Meteo (CC BY 4.0); alertas '
          'y estaciones del SMN; caudales GloFAS (Copernicus); alturas de '
          'Prefectura Naval e INA; red hídrica de la DPH Buenos Aires.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
