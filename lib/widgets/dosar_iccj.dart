import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/iccj_service.dart';

/// Cere numărul unui dosar de la Înalta Curte și îl pune în bibliotecă. În
/// fereastra de noapte îl aduce imediat; altfel îl ține „în așteptare” până la
/// verificarea de noapte. Întoarce mesajul de arătat utilizatorului.
Future<String?> adaugaDosarIccj(BuildContext context, {IccjService? iccj, DateTime? acum}) async {
  final numar = await showDialog<String>(context: context, builder: (_) => const _DialogNumar());
  if (numar == null || numar.trim().isEmpty || !context.mounted) return null;
  return urmaresteDosarIccj(numar.trim(), iccj: iccj, acum: acum);
}

/// Logica din spatele dialogului, separată ca să poată fi testată.
Future<String> urmaresteDosarIccj(String numar, {IccjService? iccj, DateTime? acum}) async {
  final biblioteca = BibliotecaService.instance;
  if (IccjService.inFereastra(acum ?? DateTime.now())) {
    try {
      final gasite = (await (iccj ?? IccjService()).cautaDosar(numar))
          .where((d) => d.numar == numar)
          .toList();
      if (gasite.isEmpty) return 'ÎCCJ nu are un dosar cu numărul $numar.';
      for (final d in gasite) {
        await biblioteca.adauga(d);
      }
      return 'Dosarul $numar de la ÎCCJ a fost adăugat.';
    } on IccjException {
      // Cade pe varianta de zi, mai jos.
    }
  }
  final d = dosarIccjInAsteptare(numar);
  if (biblioteca.contine(d.cheie)) return 'Dosarul $numar e deja urmărit.';
  await biblioteca.adauga(d);
  return 'Dosarul $numar a fost adăugat. ÎCCJ răspunde doar între 03:30 și 06:30, '
      'așa că termenele apar după verificarea de la noapte.';
}

class _DialogNumar extends StatefulWidget {
  const _DialogNumar();

  @override
  State<_DialogNumar> createState() => _DialogNumarState();
}

class _DialogNumarState extends State<_DialogNumar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dosar la Înalta Curte'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dosarele ÎCCJ nu sunt pe portal.just.ro. Le urmărim prin serviciul '
            'Înaltei Curți, care răspunde doar noaptea (03:30–06:30).',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Număr dosar',
              hintText: 'ex. 1234/1/2026',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Renunță')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Urmărește'),
        ),
      ],
    );
  }
}
