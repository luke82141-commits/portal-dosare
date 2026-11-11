import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';
import '../utils/termene.dart';

/// Chip-ul colorat pentru stadiul procesual (Figma: „Chip stadiu”).
class StadiuChip extends StatelessWidget {
  final String text;
  final Color fundal;
  final Color culoare;

  const StadiuChip._(this.text, this.fundal, this.culoare);

  /// Fond = albastru, Apel = auriu, Recurs/Contestație = verde.
  factory StadiuChip.stadiu(String stadiu) {
    final s = stadiu.toLowerCase();
    if (s.contains('apel')) {
      return StadiuChip._(stadiu, AppColors.accentContainer, AppColors.accent);
    }
    if (s.contains('recurs') || s.contains('contesta') || s.contains('revizuire')) {
      return StadiuChip._(stadiu, AppColors.successContainer, AppColors.success);
    }
    return StadiuChip._(
      stadiu.isEmpty ? '—' : stadiu,
      AppColors.primaryContainer,
      AppColors.onPrimaryContainer,
    );
  }

  /// Pentru dosarele monitorizate cu modificări necitite.
  factory StadiuChip.nou(int numar) => StadiuChip._(
        numar == 1 ? 'Nou' : '$numar noi',
        AppColors.successContainer,
        AppColors.success,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fundal, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: culoare),
      ),
    );
  }
}

/// Titlu de secțiune cu acțiune opțională în dreapta („Căutări recente · Șterge”).
class AntetSectiune extends StatelessWidget {
  final String titlu;
  final String? actiune;
  final VoidCallback? onActiune;

  const AntetSectiune(this.titlu, {super.key, this.actiune, this.onActiune});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(titlu, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (actiune != null)
          TextButton(
            onPressed: onActiune,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(actiune!),
          ),
      ],
    );
  }
}

/// Card alb cu antet care se deschide și se închide (Figma: „Accordion · Părți”).
class SectiuneExtensibila extends StatefulWidget {
  final IconData icon;
  final String titlu;
  final int numar;
  final List<Widget> copii;
  final bool deschisInitial;

  const SectiuneExtensibila({
    super.key,
    required this.icon,
    required this.titlu,
    required this.numar,
    required this.copii,
    this.deschisInitial = true,
  });

  @override
  State<SectiuneExtensibila> createState() => _SectiuneExtensibilaState();
}

class _SectiuneExtensibilaState extends State<SectiuneExtensibila> {
  late bool _deschis = widget.deschisInitial;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _deschis = !_deschis),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: AppColors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.titlu,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.numar}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _deschis ? 0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_less, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _deschis
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in widget.copii) ...[const Divider(), c],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// O parte din dosar: avatar cu inițiale, nume și calitate (Figma: „Rând parte”).
class ParteRand extends StatelessWidget {
  final Parte parte;

  const ParteRand({super.key, required this.parte});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceVariant,
            child: Text(
              initiale(parte.nume),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  parte.nume.isEmpty ? '—' : parte.nume,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (parte.calitate.isNotEmpty)
                  Text(
                    parte.calitate,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// O ședință: caseta cu data în stânga, completul, soluția și sumarul
/// (Figma: „Rând ședință”). Termenele viitoare sunt evidențiate cu auriu.
class SedintaRand extends StatelessWidget {
  final Sedinta sedinta;

  const SedintaRand({super.key, required this.sedinta});

  @override
  Widget build(BuildContext context) {
    final s = sedinta;
    final viitor = esteTermenViitor(s);

    final (String titlu, Color culoareTitlu) = s.arePronuntare
        ? (s.solutie.isNotEmpty ? s.solutie : 'Pronunțat', AppColors.onSurface)
        : viitor
            ? ('Termen viitor', AppColors.accent)
            : ('Fără soluție publicată', AppColors.onSurfaceVariant);

    final detaliu = s.arePronuntare
        ? (s.solutieSumar != s.solutie ? s.solutieSumar : '')
        : viitor
            ? 'Dosarul se află pe rol. Soluția apare după ședință.'
            : '';

    final document = [
      numeDocument(s.document),
      if (s.numarDocument.isNotEmpty) 'nr. ${s.numarDocument}',
      if (s.dataDocument != null) 'din ${formateazaData(s.dataDocument)}',
    ].where((e) => e.isNotEmpty).join(' ');

    final antet = [
      if (s.complet.isNotEmpty) 'Complet ${s.complet}',
      if (s.ora.isNotEmpty) 'ora ${s.ora}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 56,
            decoration: BoxDecoration(
              color: viitor ? AppColors.accent : AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: s.data == null
                ? const Text('—', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.data!.day.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.bold,
                          color: viitor ? AppColors.onPrimary : AppColors.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        lunaScurta(s.data!),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: viitor ? AppColors.onPrimary : AppColors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (antet.isNotEmpty)
                  Text(
                    antet,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                const SizedBox(height: 3),
                Text(
                  titlu,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: culoareTitlu,
                  ),
                ),
                if (detaliu.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detaliu,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.38,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (document.isNotEmpty || s.dataPronuntare != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (document.isNotEmpty) document,
                      // Data pronunțării apare doar dacă diferă de cea a documentului.
                      if (s.dataPronuntare != null &&
                          formateazaData(s.dataPronuntare) != formateazaData(s.dataDocument))
                        'pronunțat ${formateazaData(s.dataPronuntare)}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stare goală sau de eroare: pictogramă rotundă, titlu, text și un buton.
class StareMesaj extends StatelessWidget {
  final IconData icon;
  final Color fundal;
  final Color culoare;
  final String titlu;
  final String text;
  final String? buton;
  final VoidCallback? onButon;
  final bool butonPrincipal;

  const StareMesaj({
    super.key,
    required this.icon,
    required this.titlu,
    required this.text,
    this.fundal = AppColors.surfaceVariant,
    this.culoare = AppColors.onSurfaceVariant,
    this.buton,
    this.onButon,
    this.butonPrincipal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: fundal,
              child: Icon(icon, size: 30, color: culoare),
            ),
            const SizedBox(height: 12),
            Text(
              titlu,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.43,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (buton != null) ...[
              const SizedBox(height: 16),
              butonPrincipal
                  ? FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: onButon,
                      child: Text(buton!),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: onButon,
                      child: Text(buton!),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bandă de progres afișată cât timp se așteaptă răspunsul portalului.
class IncarcarePortal extends StatelessWidget {
  const IncarcarePortal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, size: 20, color: AppColors.onPrimaryContainer),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Se conectează la portal.just.ro…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(3)),
            child: LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: AppColors.card,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Portalul poate răspunde mai greu. Căutarea durează de obicei câteva secunde.',
            style: TextStyle(fontSize: 12, height: 1.33, color: AppColors.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

/// Card gri cu bare, în locul cardurilor de dosar cât timp se încarcă.
class CardSchelet extends StatelessWidget {
  const CardSchelet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bara(double latime, [double inaltime = 12]) => Container(
          width: latime,
          height: inaltime,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [bara(150, 16), bara(240), bara(290), bara(200)],
        ),
      ),
    );
  }
}

/// Pastilă rotunjită: căutări recente, filtre după stadiu.
class Pastila extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool activ;
  final VoidCallback? onTap;

  const Pastila(this.text, {super.key, this.icon, this.activ = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final culoareText = activ ? AppColors.onPrimary : AppColors.onSurface;
    return Material(
      color: activ ? AppColors.primary : AppColors.card,
      shape: StadiumBorder(
        side: activ ? BorderSide.none : const BorderSide(color: AppColors.outline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: activ ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: culoareText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
