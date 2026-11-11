import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../screens/dosar_detaliu_screen.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';
import 'comutare_monitorizare.dart';
import 'elemente.dart';

/// Cardul compact al unui dosar în liste (Figma: „Card dosar”): număr,
/// stadiu, instanță, obiect și următorul termen. Tap deschide detaliul.
///
/// Dacă primește [salvat] cu modificări necitite, arată chip-ul „Nou” și
/// ultima modificare.
///
/// Cu [cuBiblioteca] (în rezultatele căutării) arată dacă dosarul e deja în
/// bibliotecă, cu un buton care îl adaugă sau îl scoate direct din listă.
class DosarCardWidget extends StatelessWidget {
  final Dosar dosar;
  final DosarSalvat? salvat;
  final bool cuBiblioteca;

  const DosarCardWidget({
    super.key,
    required this.dosar,
    this.salvat,
    this.cuBiblioteca = false,
  });

  @override
  Widget build(BuildContext context) {
    final necitite = salvat?.necitite ?? 0;
    final ultimaModificare =
        necitite > 0 && salvat!.modificari.isNotEmpty ? salvat!.modificari.first : null;
    final instanta = [dosar.instanta, dosar.sectie].where((e) => e.isNotEmpty).join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: dosar)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dosar.numar,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  necitite > 0
                      ? StadiuChip.nou(necitite)
                      : StadiuChip.stadiu(dosar.stadiuProcesual),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.account_balance, size: 16, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      instanta,
                      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                dosar.obiect.isEmpty ? '—' : dosar.obiect,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.33, fontWeight: FontWeight.w500),
              ),
              if (ultimaModificare != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notifications_active, size: 16, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scurteaza(ultimaModificare.text, 140),
                          style: const TextStyle(fontSize: 13, color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.event, size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      rezumatTermen(dosar),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (cuBiblioteca)
                    _ButonBiblioteca(dosar)
                  else
                    const Icon(Icons.chevron_right, size: 20, color: AppColors.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „+ Bibliotecă” / „În bibliotecă”, comutat direct din card.
class _ButonBiblioteca extends StatelessWidget {
  final Dosar dosar;

  const _ButonBiblioteca(this.dosar);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BibliotecaService.instance,
      builder: (context, _) {
        final salvat = BibliotecaService.instance.contine(dosar.cheie);
        final culoare = salvat ? AppColors.success : AppColors.primary;
        return Tooltip(
          message: salvat ? 'Scoate din bibliotecă' : 'Adaugă în bibliotecă',
          child: Material(
            color: salvat ? AppColors.successContainer : AppColors.card,
            shape: StadiumBorder(
              side: salvat ? BorderSide.none : const BorderSide(color: AppColors.outline),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => comutaMonitorizare(context, dosar),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(salvat ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                        size: 16, color: culoare),
                    const SizedBox(width: 6),
                    Text(
                      salvat ? 'În bibliotecă' : 'Adaugă',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: culoare),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
