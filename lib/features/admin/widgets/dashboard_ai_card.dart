import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/services/dashboard_ai_service.dart';

class DashboardAiCard extends ConsumerStatefulWidget {
  const DashboardAiCard({super.key, required this.municipalityId});
  final String municipalityId;

  @override
  ConsumerState<DashboardAiCard> createState() => _DashboardAiCardState();
}

class _DashboardAiCardState extends ConsumerState<DashboardAiCard> {
  DashboardAiReport? _report;
  bool _loading = false;
  String? _error;
  int _periodDays = 30;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref.read(dashboardAiServiceProvider).generate(
            municipalityId: widget.municipalityId,
            periodDays: _periodDays,
          );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = mensajeDeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome_outlined),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Análisis estratégico con IA',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Analiza carga operativa, demoras, prioridad, apoyo vecinal y zonas anonimizadas. Solo propone decisiones: el municipio las valida.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  value: _periodDays,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('Últimos 7 días')),
                    DropdownMenuItem(value: 30, child: Text('Últimos 30 días')),
                    DropdownMenuItem(value: 90, child: Text('Últimos 90 días')),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _periodDays = value ?? 30),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_loading ? 'Analizando…' : 'Generar análisis'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (report != null && report.status == 'ready') ...[
              const SizedBox(height: 18),
              Text(report.summary),
              if (report.priorities.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Prioridades sugeridas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final priority in report.priorities)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined, size: 20),
                    title: Text(priority['title'] ?? ''),
                    subtitle: Text(
                      '${priority["evidence"] ?? ""}\n${priority["action"] ?? ""}',
                    ),
                  ),
              ],
              if (report.strategies.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Decisiones estratégicas a validar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final strategy in report.strategies)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_tree_outlined, size: 20),
                    title: Text(strategy['title'] ?? ''),
                    subtitle: Text(
                      '${strategy["objective"] ?? ""}\n${strategy["action"] ?? ""}\nImpacto de recursos: ${strategy["resourceImpact"] ?? ""}',
                    ),
                  ),
              ],
              if (report.risks.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Riesgos operativos',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final risk in report.risks)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('• $risk'),
                  ),
              ],
              if (report.questions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Validaciones antes de decidir',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final question in report.questions)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('• $question'),
                  ),
              ],
              const SizedBox(height: 10),
              Text(
                'Base: ${report.totalReports} reportes · ${report.periodDays} días',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
