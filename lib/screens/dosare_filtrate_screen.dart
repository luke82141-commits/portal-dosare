import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

/// După ce se pot filtra dosarele salvate.
enum TipFiltru { instanta, stadiu, categorie, an }

/// Un criteriu de filtrare, cu valoarea luată din dosarul de pornire.
class Filtru {
  final TipFiltru tip;
  final Dosar sursa;

  const Filtru(this.tip, this.sursa);

  bool potriveste(Dosar d) => switch (tip) {
        TipFiltru.instanta => d.institutie == sursa.institutie,
        TipFiltru.stadiu => d.stadiuProcesual == sursa.stadiuProcesual,
        TipFiltru.categorie => d.categorie == sursa.categorie,
        TipFiltru.an => d.data?.year == sursa.data?.year,
      };

  /// False când dosarul de pornire nu are valoare pentru acest criteriu.
  bool get disponibil => switch (tip) {
        TipFiltru.instanta => sursa.institutie.isNotEmpty,
        TipFiltru.stadiu => sursa.stadiuProcesual.isNotEmpty,
        TipFiltru.categorie => sursa.categorie.isNotEmpty,
        TipFiltru.an => sursa.data != null,
      };

  String get eticheta => switch (tip) {
        TipFiltru.instanta => sursa.instanta,
        TipFiltru.stadiu => sursa.stadiuProcesual,
        TipFiltru.categorie => sursa.categorie,
        TipFiltru.an => 'Înregistrate în ${sursa.data?.year}',
      };

  IconData get icon => switch (tip) {
        TipFiltru.instanta => Icons.account_balance,
        TipFiltru.stadiu => Icons.call_split,
        TipFiltru.categorie => Icons.category_outlined,
        TipFiltru.an => Icons.event,
      };
}

/// Dosarele salvate care au aceeași instanță, cale de atac, materie sau an
/// de înregistrare ca dosarul din care s-a pornit. Criteriile se pot
/// combina sau scoate din rândul de sus.
class DosareFiltrateScreen extends StatefulWidget {
  final Dosar sursa;
  final TipFiltru initial;

  const DosareFiltrateScreen({super.key, required this.sursa, required this.initial});

  @override
  State<DosareFiltrateScreen> createState() => _DosareFiltrateScreenState();
}

class _DosareFiltrateScreenState extends State<DosareFiltrateScreen> {
  late final Set<TipFiltru> _active = {widget.initial};

  @override
  Widget build(BuildContext context) {
    final filtre = [
      for (final t in TipFiltru.values)
        if (Filtru(t, widget.sursa).disponibil) Filtru(t, widget.sursa),
    ];
    final active = filtre.where((f) => _active.contains(f.tip)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dosarele mele'),
        shape: const Border(bottom: BorderSide(color: AppColors.outline)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: filtre.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = filtre[i];
                final activ = _active.contains(f.tip);
                return Pastila(
                  f.eticheta,
                  icon: activ ? Icons.check : f.icon,
                  activ: activ,
                  onTap: () => setState(() {
                    if (activ) {
                      _active.remove(f.tip);
                    } else {
                      _active.add(f.tip);
                    }
                  }),
                );
              },
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final dosare = BibliotecaService.instance.dosare
              .where((s) => active.every((f) => f.potriveste(s.dosar)))
              .toList();

          if (dosare.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                StareMesaj(
                  icon: Icons.filter_alt_off_outlined,
                  titlu: 'Niciun dosar salvat aici',
                  text: 'Niciun dosar din biblioteca ta nu se potrivește cu filtrele '
                      'alese. Scoate unul dintre ele din rândul de sus.',
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: dosare.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Text(
                  dosare.length == 1 ? 'Un dosar' : '${dosare.length} dosare',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                );
              }
              final s = dosare[i - 1];
              return DosarCardWidget(key: ValueKey(s.dosar.cheie), dosar: s.dosar, salvat: s);
            },
          );
        },
      ),
    );
  }
}
