import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/termene.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

/// Ce arată ecranul deschis din căsuțele de sus de pe „Monitorizate”.
enum SelectieDosare { actualizari, termene }

/// Dosarele cu actualizări necitite, cele mai recente întâi.
List<DosarSalvat> dosareCuActualizari(List<DosarSalvat> dosare) {
  DateTime ultima(DosarSalvat s) => s.modificari.isEmpty
      ? DateTime(0)
      : s.modificari.map((m) => m.detectataLa).reduce((a, b) => a.isAfter(b) ? a : b);
  return [
    for (final s in dosare)
      if (s.necitite > 0) s,
  ]..sort((a, b) => ultima(b).compareTo(ultima(a)));
}

/// Dosarele cu termen în următoarele 7 zile (azi inclus), cel mai apropiat întâi.
List<DosarSalvat> dosareCuTermenInSaptamana(List<DosarSalvat> dosare, {DateTime? acum}) {
  final azi = DateUtils.dateOnly(acum ?? DateTime.now());
  final l = [
    for (final s in dosare)
      if (urmatorulTermen(s.dosar, acum: acum) case final t?)
        if (t.data!.difference(azi).inDays < 7) (s, t),
  ]..sort((a, b) => _momentTermen(a.$2).compareTo(_momentTermen(b.$2)));
  return [for (final (s, _) in l) s];
}

/// Data termenului plus ora, ca termenele din aceeași zi să iasă în ordine.
DateTime _momentTermen(Sedinta t) {
  final p = t.ora.split(':');
  final ore = int.tryParse(p.first) ?? 0;
  final minute = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return t.data!.add(Duration(hours: ore, minutes: minute));
}

class DosareSelectieScreen extends StatelessWidget {
  final SelectieDosare selectie;
  const DosareSelectieScreen({super.key, required this.selectie});

  @override
  Widget build(BuildContext context) {
    final actualizari = selectie == SelectieDosare.actualizari;
    return Scaffold(
      appBar: AppBar(title: Text(actualizari ? 'Actualizări noi' : 'Termene în 7 zile')),
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final toate = BibliotecaService.instance.dosare;
          final dosare = actualizari
              ? dosareCuActualizari(toate)
              : dosareCuTermenInSaptamana(toate);
          if (dosare.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: StareMesaj(
                icon: actualizari ? Icons.done_all : Icons.event_available,
                titlu: actualizari ? 'Nicio actualizare nouă' : 'Niciun termen în 7 zile',
                text: actualizari
                    ? 'Le-ai văzut pe toate. Aici apar dosarele în care portalul a adus ceva nou.'
                    : 'Niciun dosar urmărit nu are termen în următoarea săptămână.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: dosare.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  actualizari
                      ? 'Cele mai recente actualizări primele'
                      : 'În ordinea termenelor, de la cel mai apropiat',
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
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
