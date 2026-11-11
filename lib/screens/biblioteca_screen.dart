import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import '../widgets/dosar_card.dart';

/// Dosarele salvate, cu schimbările detectate pe portal.
class BibliotecaScreen extends StatefulWidget {
  const BibliotecaScreen({super.key});

  @override
  State<BibliotecaScreen> createState() => _BibliotecaScreenState();
}

class _BibliotecaScreenState extends State<BibliotecaScreen> {
  bool _verifica = false;

  Future<void> _verificaAcum() async {
    if (_verifica) return;
    setState(() => _verifica = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rezultate = await MonitorizareService.instance.verificaToate();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            rezultate.isEmpty
                ? 'Nicio modificare pe portal.'
                : rezultate.length == 1
                    ? 'Un dosar are modificări.'
                    : '${rezultate.length} dosare au modificări.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Verificarea a eșuat: $e')));
    } finally {
      if (mounted) setState(() => _verifica = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biblioteca = BibliotecaService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca mea'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_verifica)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              tooltip: 'Verifică acum pe portal',
              onPressed: _verificaAcum,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: biblioteca,
        builder: (context, _) {
          final dosare = biblioteca.dosare;
          if (dosare.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmarks_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Niciun dosar salvat',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Caută un dosar și apasă semnul de carte din colțul cardului. '
                      'Vei primi o notificare la fiecare schimbare apărută pe portal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _verificaAcum,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: dosare.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${dosare.length == 1 ? 'Un dosar urmărit' : '${dosare.length} dosare urmărite'}'
                      ' · verificare automată o dată pe oră',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  );
                }
                final salvat = dosare[index - 1];
                return DosarCardWidget(
                  key: ValueKey(salvat.dosar.cheie),
                  dosar: salvat.dosar,
                  salvat: salvat,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
