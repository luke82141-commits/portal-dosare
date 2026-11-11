import 'package:flutter/material.dart';
import '../models/dosar_model.dart';

class DosarCardWidget extends StatelessWidget {
  final Dosar dosar;

  const DosarCardWidget({super.key, required this.dosar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          'Dosar nr. ${dosar.numar}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            'Obiect: ${dosar.obiect}\nInstanță: ${dosar.institutie}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildDetailRow('Data:', dosar.data),
          _buildDetailRow('Categorie:', dosar.categorie),
          _buildDetailRow('Stadiu procesual:', dosar.stadiuProcesual),
          _buildDetailRow('Secție:', dosar.sectie),
          const SizedBox(height: 10),
          const Text('Părți în dosar:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (dosar.parti.isEmpty) const Text('—'),
          ...dosar.parti.map((p) => Text('• ${p.nume} — ${p.calitate}')),
          const SizedBox(height: 10),
          const Text('Ședințe / Termene:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (dosar.sedinte.isEmpty) const Text('—'),
          ...dosar.sedinte.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${s.data}${s.ora.isNotEmpty ? ' ora ${s.ora}' : ''} | Complet: ${s.complet}'
                '${s.solutie.isNotEmpty ? '\n  Soluție: ${s.solutie}' : ''}'
                '${s.solutieSumar.isNotEmpty ? '\n  ${s.solutieSumar}' : ''}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
