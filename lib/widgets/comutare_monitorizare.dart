import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';

/// Pornește sau oprește monitorizarea unui dosar. La oprire cere confirmare,
/// pentru că istoricul modificărilor se șterge.
Future<void> comutaMonitorizare(BuildContext context, Dosar dosar) async {
  final biblioteca = BibliotecaService.instance;
  final messenger = ScaffoldMessenger.of(context);

  if (biblioteca.contine(dosar.cheie)) {
    final confirmat = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oprești monitorizarea?'),
        content: Text(
          'Dosarul ${dosar.numar} (${dosar.instanta}) nu va mai fi urmărit '
          'și istoricul modificărilor lui se șterge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oprește'),
          ),
        ],
      ),
    );
    if (confirmat != true) return;
    await biblioteca.sterge(dosar.cheie);
    messenger.showSnackBar(
      SnackBar(content: Text('Dosarul ${dosar.numar} nu mai este monitorizat.')),
    );
    return;
  }

  await biblioteca.adauga(dosar);
  final permis = await MonitorizareService.instance.cerePermisiune();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        permis
            ? 'Dosarul ${dosar.numar} este monitorizat. Vei primi notificări la modificări.'
            : 'Dosarul ${dosar.numar} este monitorizat, dar notificările sunt '
                'dezactivate pentru aplicație. Activează-le din setările telefonului.',
      ),
    ),
  );
}
