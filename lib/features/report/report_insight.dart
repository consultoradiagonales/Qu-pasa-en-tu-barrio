import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReportInsight {
  const ReportInsight(
      {required this.status,
      this.summary = '',
      this.empathy = '',
      this.question = '',
      this.emergency = false});
  final String status, summary, empathy, question;
  final bool emergency;
  factory ReportInsight.fromMap(Map<String, dynamic> map) => ReportInsight(
        status: map['status'] is String ? map['status'] : 'unavailable',
        summary: map['summary'] is String ? map['summary'] : '',
        empathy: map['empathy'] is String ? map['empathy'] : '',
        question: map['question'] is String ? map['question'] : '',
        emergency: map['emergency'] == true,
      );
}

final reportInsightProvider = StreamProvider.autoDispose
    .family<ReportInsight?, String>((ref, id) => FirebaseFirestore.instance
        .collection('reportInsights')
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? ReportInsight.fromMap(doc.data()!) : null));

class ReportInsightCard extends ConsumerWidget {
  const ReportInsightCard(
      {super.key, required this.reportId, this.expected = false});
  final String reportId;
  final bool expected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(reportInsightProvider(reportId));
    final insight = value.valueOrNull;
    if (!expected && (insight == null || insight.status != 'ready'))
      return const SizedBox.shrink();
    final ready = insight?.status == 'ready';
    final unavailable = value.hasError || insight?.status == 'unavailable';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome_outlined, size: 20),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Asistente ConDi · IA',
                        style: TextStyle(fontWeight: FontWeight.bold)))
              ]),
              const SizedBox(height: 10),
              if (ready) ...[
                Text(insight!.empathy),
                const SizedBox(height: 12),
                const Text('Esto entendimos',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(insight.summary),
                if (insight.question.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child:
                          Text('Para un próximo reporte: ${insight.question}')),
                if (insight.emergency)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Si hay peligro inmediato, contactá al servicio de emergencias local. ConDi no atiende emergencias.')),
                const SizedBox(height: 10),
                const Text(
                    'Interpretación automática: puede equivocarse. No es una respuesta oficial del municipio ni cambia el estado de tu reporte.',
                    style: TextStyle(fontSize: 12)),
              ] else
                Text(unavailable
                    ? 'La interpretación no está disponible. Tu reporte está registrado y conserva la foto y tu comentario.'
                    : 'Estamos interpretando tu reporte. Podés continuar y verlo después en Mis reportes.'),
            ])));
  }
}
