import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';

/// Cardul unui dosar: antet cu numărul, casete cu datele principale, ultima
/// pronunțare evidențiată și, la extindere, părțile și toate ședințele.
///
/// Dacă primește [salvat], afișează și schimbările detectate pe portal.
class DosarCardWidget extends StatefulWidget {
  final Dosar dosar;
  final DosarSalvat? salvat;

  const DosarCardWidget({super.key, required this.dosar, this.salvat});

  @override
  State<DosarCardWidget> createState() => _DosarCardWidgetState();
}

class _DosarCardWidgetState extends State<DosarCardWidget> {
  bool _extins = false;

  Dosar get dosar => widget.dosar;

  Future<void> _comutaSalvare() async {
    final biblioteca = BibliotecaService.instance;
    final messenger = ScaffoldMessenger.of(context);

    if (biblioteca.contine(dosar.cheie)) {
      final confirmat = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scoți dosarul din bibliotecă?'),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scoate'),
            ),
          ],
        ),
      );
      if (confirmat != true) return;
      await biblioteca.sterge(dosar.cheie);
      messenger.showSnackBar(
        SnackBar(content: Text('Dosarul ${dosar.numar} a fost scos din bibliotecă.')),
      );
      return;
    }

    await biblioteca.adauga(dosar);
    final permis = await MonitorizareService.instance.cerePermisiune();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          permis
              ? 'Dosarul ${dosar.numar} a fost salvat. Vei primi notificări la modificări.'
              : 'Dosarul ${dosar.numar} a fost salvat, dar notificările sunt '
                  'dezactivate pentru aplicație. Activează-le din setările telefonului.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sedinte = dosar.sedinteSortate;
    final azi = DateUtils.dateOnly(DateTime.now());

    final viitoare = sedinte
        .where((s) => !s.arePronuntare && s.data != null && !s.data!.isBefore(azi))
        .toList();
    final urmatorulTermen = viitoare.isEmpty ? null : viitoare.last;
    final ultimaPronuntare = sedinte.where((s) => s.arePronuntare).firstOrNull;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _antet(scheme),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.salvat != null) _modificari(widget.salvat!),
                _Caseta(
                  eticheta: 'Instanță',
                  icon: Icons.account_balance,
                  valoare: dosar.instanta,
                  secundar: dosar.sectie,
                  accentuat: true,
                ),
                const SizedBox(height: 8),
                _Caseta(eticheta: 'Obiect', icon: Icons.subject, valoare: dosar.obiect),
                const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Caseta(
                          eticheta: 'Stadiu procesual',
                          valoare: dosar.stadiuProcesual,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Caseta(eticheta: 'Categorie', valoare: dosar.categorie),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Caseta(
                          eticheta: 'Înregistrat',
                          valoare: formateazaData(dosar.data),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Caseta(
                          eticheta: 'Modificat pe portal',
                          valoare: formateazaData(dosar.dataModificare),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_extins) ...[
                  if (urmatorulTermen != null) ...[
                    const SizedBox(height: 8),
                    _TermenViitor(sedinta: urmatorulTermen),
                  ],
                  if (ultimaPronuntare != null) ...[
                    const SizedBox(height: 8),
                    _SedintaCaseta(
                      sedinta: ultimaPronuntare,
                      titlu: 'Ultima pronunțare',
                      compact: true,
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 16),
                  _TitluSectiune('Părți', dosar.parti.length),
                  if (dosar.parti.isEmpty)
                    const _Gol('Portalul nu afișează părți pentru acest dosar.')
                  else
                    _Parti(parti: dosar.parti),
                  const SizedBox(height: 16),
                  _TitluSectiune('Ședințe', sedinte.length),
                  if (sedinte.isEmpty)
                    const _Gol('Nu există încă ședințe publicate.')
                  else
                    for (final s in sedinte)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SedintaCaseta(sedinta: s),
                      ),
                  if (dosar.caiAtac.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _TitluSectiune('Căi de atac', dosar.caiAtac.length),
                    for (final c in dosar.caiAtac)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _Caseta(
                          eticheta: formateazaData(c.dataDeclarare),
                          icon: Icons.call_split,
                          valoare: c.tip,
                          secundar: c.parteDeclaratoare,
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => setState(() => _extins = !_extins),
                  icon: Icon(_extins ? Icons.expand_less : Icons.expand_more),
                  label: Text(
                    _extins
                        ? 'Restrânge'
                        : 'Părți (${dosar.parti.length}) și toate ședințele (${sedinte.length})',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _antet(ColorScheme scheme) {
    return Container(
      color: scheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Icon(Icons.folder_open, color: scheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DOSAR NR.',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
                SelectableText(
                  dosar.numar,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: BibliotecaService.instance,
            builder: (context, _) {
              final salvat = BibliotecaService.instance.contine(dosar.cheie);
              return IconButton(
                tooltip: salvat ? 'Scoate din bibliotecă' : 'Salvează în bibliotecă',
                onPressed: _comutaSalvare,
                color: scheme.onPrimaryContainer,
                icon: Icon(salvat ? Icons.bookmark : Icons.bookmark_add_outlined),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _modificari(DosarSalvat salvat) {
    final scheme = Theme.of(context).colorScheme;
    final verificat = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        salvat.ultimaVerificare == null
            ? 'Încă neverificat pe portal'
            : 'Verificat pe portal: ${formateazaDataOra(salvat.ultimaVerificare)}',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
    if (salvat.modificari.isEmpty) return verificat;

    final areNoi = salvat.necitite > 0;
    final culoare = areNoi ? Colors.orange.shade800 : scheme.outline;
    final afisate = _extins ? salvat.modificari : salvat.modificari.take(3).toList();
    final ascunse = salvat.modificari.length - afisate.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: areNoi ? Colors.orange.shade50 : scheme.surfaceContainerLow,
            border: Border.all(color: culoare.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    areNoi ? Icons.notifications_active : Icons.history,
                    size: 18,
                    color: culoare,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      areNoi
                          ? 'MODIFICĂRI NOI (${salvat.necitite})'
                          : 'ISTORIC MODIFICĂRI',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: culoare,
                      ),
                    ),
                  ),
                  if (areNoi)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: culoare,
                      ),
                      onPressed: () =>
                          BibliotecaService.instance.marcheazaCitit(dosar.cheie),
                      child: const Text('Am văzut'),
                    ),
                ],
              ),
              for (var i = 0; i < afisate.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        afisate[i].text,
                        style: TextStyle(
                          fontWeight:
                              i < salvat.necitite ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      Text(
                        'detectat ${formateazaDataOra(afisate[i].detectataLa)}',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              if (ascunse > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+ încă $ascunse mai vechi',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        verificat,
      ],
    );
  }
}

/// O casetă cu etichetă mică deasupra și valoarea dedesubt.
class _Caseta extends StatelessWidget {
  final String eticheta;
  final String valoare;
  final String secundar;
  final IconData? icon;
  final bool accentuat;

  const _Caseta({
    required this.eticheta,
    required this.valoare,
    this.secundar = '',
    this.icon,
    this.accentuat = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eticheta.isNotEmpty) _Eticheta(eticheta),
                Text(
                  valoare.isEmpty ? '—' : valoare,
                  style: TextStyle(
                    fontSize: accentuat ? 16 : 14,
                    fontWeight: accentuat ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (secundar.isNotEmpty)
                  Text(
                    secundar,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Eticheta extends StatelessWidget {
  final String text;
  final Color? culoare;

  const _Eticheta(this.text, {this.culoare});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
          color: culoare ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TitluSectiune extends StatelessWidget {
  final String titlu;
  final int numar;

  const _TitluSectiune(this.titlu, this.numar);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$titlu ($numar)',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _Gol extends StatelessWidget {
  final String text;

  const _Gol(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// Lista părților, într-o singură casetă cu rânduri despărțite.
class _Parti extends StatelessWidget {
  final List<Parte> parti;

  const _Parti({required this.parti});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < parti.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(parti[i].nume.isEmpty ? '—' : parti[i].nume)),
                  if (parti[i].calitate.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        parti[i].calitate,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bandă scurtă pentru următorul termen, afișată pe cardul restrâns.
class _TermenViitor extends StatelessWidget {
  final Sedinta sedinta;

  const _TermenViitor({required this.sedinta});

  @override
  Widget build(BuildContext context) {
    final culoare = Colors.blue.shade800;
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.event, size: 18, color: culoare),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Următorul termen: '),
                  TextSpan(
                    text: formateazaData(sedinta.data),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (sedinta.ora.isNotEmpty) TextSpan(text: ', ora ${sedinta.ora}'),
                ],
              ),
              style: TextStyle(color: culoare),
            ),
          ),
        ],
      ),
    );
  }
}

/// Caseta unei ședințe. Ce s-a pronunțat apare într-un bloc verde, separat de
/// datele administrative (dată, oră, complet).
class _SedintaCaseta extends StatelessWidget {
  final Sedinta sedinta;
  final String? titlu;

  /// Pe cardul restrâns sumarul soluției e limitat la câteva rânduri.
  final bool compact;

  const _SedintaCaseta({required this.sedinta, this.titlu, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = sedinta;
    final azi = DateUtils.dateOnly(DateTime.now());
    final viitoare = s.data != null && !s.data!.isBefore(azi);

    final (String stare, Color culoareStare) = s.arePronuntare
        ? ('Pronunțat', Colors.green.shade800)
        : viitoare
            ? ('Termen viitor', Colors.blue.shade800)
            : ('Fără soluție publicată', scheme.outline);

    final document = [
      numeDocument(s.document),
      if (s.numarDocument.isNotEmpty) 'nr. ${s.numarDocument}',
      if (s.dataDocument != null) 'din ${formateazaData(s.dataDocument)}',
    ].where((e) => e.isNotEmpty).join(' ');

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titlu != null) _Eticheta(titlu!),
                Row(
                  children: [
                    Icon(Icons.event, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.data == null ? 'Fără dată' : formateazaData(s.data)}'
                        '${s.ora.isEmpty ? '' : '  ·  ora ${s.ora}'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: culoareStare),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        stare,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: culoareStare,
                        ),
                      ),
                    ),
                  ],
                ),
                if (s.complet.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 24),
                    child: Text(
                      'Complet: ${s.complet}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          if (s.arePronuntare)
            Container(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border(
                  left: BorderSide(color: Colors.green.shade700, width: 4),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gavel, size: 15, color: Colors.green.shade800),
                      const SizedBox(width: 6),
                      _Eticheta('Ce s-a pronunțat', culoare: Colors.green.shade800),
                    ],
                  ),
                  if (s.solutie.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        s.solutie,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (s.solutieSumar.isNotEmpty && s.solutieSumar != s.solutie)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        s.solutieSumar,
                        maxLines: compact ? 4 : null,
                        overflow: compact ? TextOverflow.ellipsis : null,
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                  if (!compact && (document.isNotEmpty || s.dataPronuntare != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (document.isNotEmpty) 'Document: $document',
                          if (s.dataPronuntare != null)
                            'Data pronunțării: ${formateazaData(s.dataPronuntare)}',
                        ].join('\n'),
                        style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
