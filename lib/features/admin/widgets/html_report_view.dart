import 'package:flutter/material.dart';
import '../../../data/models/report_model.dart';
import '../../../core/widgets/condi_logo.dart';
import '../../../core/utils/web_download.dart';
import '../../../core/theme/app_theme.dart';

class HtmlReportView extends StatefulWidget {
  const HtmlReportView({super.key, required this.reports});
  final List<ReportModel> reports;
  @override
  State<HtmlReportView> createState() => _HtmlReportViewState();
}

class _HtmlReportViewState extends State<HtmlReportView> {
  int _days = 30;
  String _title = 'Informe de gestión ConDi';
  String _html = '';
  void _generate() {
    final since = DateTime.now().subtract(Duration(days: _days));
    final rows =
        widget.reports.where((r) => r.createdAt.isAfter(since)).toList();
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.status.value] = (counts[r.status.value] ?? 0) + 1;
    }
    final chips = counts.entries
        .map((e) =>
            '<div class="kpi"><b>${e.value}</b>${_esc(statusLabel(e.key))}</div>')
        .join();
    final table = rows
        .map((r) =>
            '<tr><td>${_esc(r.title)}</td><td>${_esc(categoryLabel(r.category.value))}</td><td>${_esc(statusLabel(r.status.value))}</td><td>${r.createdAt.toLocal().toString().split(' ').first}</td></tr>')
        .join();
    setState(() => _html =
        '<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${_esc(_title)}</title><style>body{font:16px Arial;color:#17213a;max-width:980px;margin:40px auto;padding:0 20px}header{border-bottom:5px solid #1769c2;padding-bottom:18px}img{width:150px}h1{font-size:30px}.kpis{display:flex;gap:12px;flex-wrap:wrap}.kpi{padding:16px;background:#eef5fd;border-radius:12px;min-width:130px}.kpi b{display:block;font-size:28px;color:#1769c2}table{width:100%;border-collapse:collapse;margin-top:25px}td,th{padding:10px;border-bottom:1px solid #ddd;text-align:left}</style></head><body><header><img src="${Uri.base}assets/assets/images/condi_logo.png"><h1>${_esc(_title)}</h1><p>Período: últimos $_days días · ConDi · Consultora Diagonales</p></header><div class="kpis"><div class="kpi"><b>${rows.length}</b>Reportes</div>$chips</div><h2>Detalle de reportes</h2><table><tr><th>Título</th><th>Categoría</th><th>Estado</th><th>Fecha</th></tr>$table</table></body></html>');
  }

  String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Informes HTML',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                Text(
                    'Generá una versión propia con logo y decisiones de gestión.')
              ])),
          const CondiLogo(fontSize: 30)
        ]),
        const SizedBox(height: 20),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                          width: 360,
                          child: TextFormField(
                              initialValue: _title,
                              onChanged: (v) => _title = v,
                              decoration: const InputDecoration(
                                  labelText: 'Título del informe'))),
                      DropdownButton<int>(
                          value: _days,
                          items: const [
                            DropdownMenuItem(
                                value: 7, child: Text('Últimos 7 días')),
                            DropdownMenuItem(
                                value: 30, child: Text('Últimos 30 días')),
                            DropdownMenuItem(
                                value: 90, child: Text('Últimos 90 días'))
                          ],
                          onChanged: (v) => setState(() => _days = v ?? 30)),
                      FilledButton.icon(
                          onPressed: _generate,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generar HTML')),
                      if (_html.isNotEmpty)
                        OutlinedButton.icon(
                            onPressed: () =>
                                downloadText('informe-condi.html', _html),
                            icon: const Icon(Icons.download),
                            label: const Text('Descargar'))
                    ]))),
        if (_html.isNotEmpty)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText(_html,
                      maxLines: 18,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11))))
      ]);
}
