import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../screens/dosar_detaliu_screen.dart';
import '../services/soap_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';
import 'elemente.dart';
import 'partajare_solutie.dart';

/// Același număr de dosar la toate instanțele prin care a trecut (fond,
/// apel, recurs), căutat pe portal după număr.
class ParcursDosar {
  ParcursDosar._();

  /// Se poate înlocui în teste.
  static SoapService Function() soap = SoapService.new;

  static final Map<String, Future<List<Dosar>>> _cache = {};

  static Future<List<Dosar>> cauta(String numar, {bool reincarca = false}) {
    if (reincarca) _cache.remove(numar);
    return _cache[numar] ??= soap()
        .cautaDosare(numarDosar: numar)
        .then((r) => ordoneaza(r.dosare))
        .catchError((Object e) {
      _cache.remove(numar);
      throw e;
    });
  }

  static void golesteCache() => _cache.clear();

  /// Rezultatele unei căutări pe portal conțin deja toate instanțele cu
  /// același număr, deci detaliul le arată fără o nouă interogare.
  static void memoreaza(List<Dosar> dosare) {
    final peNumere = <String, List<Dosar>>{};
    for (final d in dosare) {
      (peNumere[d.numar] ??= []).add(d);
    }
    for (final e in peNumere.entries) {
      _cache[e.key] = Future.value(ordoneaza(e.value));
    }
  }

  /// Judecătorie → tribunal → curte de apel → ÎCCJ, apoi după data înregistrării.
  static List<Dosar> ordoneaza(List<Dosar> dosare) {
    int nivel(Dosar d) {
      final i = d.institutie.toLowerCase();
      if (i.startsWith('judecatoria')) return 0;
      if (i.startsWith('tribunal')) return 1;
      if (i.contains('curte')) return 2;
      return 3;
    }

    return [...dosare]..sort((a, b) {
        final n = nivel(a).compareTo(nivel(b));
        if (n != 0) return n;
        return (a.data ?? DateTime(0)).compareTo(b.data ?? DateTime(0));
      });
  }
}

/// Cardul „Parcursul dosarului” din detaliu, ordonat ca ierarhia instanțelor
/// (judecătoria jos, instanța cea mai înaltă sus): soluția de la fond când dosarul
/// e în cale de atac, și calea de atac (instanța, soluția, ședințele) când e
/// deschis de la fond.
class ParcursDosarCard extends StatefulWidget {
  final Dosar dosar;

  const ParcursDosarCard({super.key, required this.dosar});

  @override
  State<ParcursDosarCard> createState() => _ParcursDosarCardState();
}

class _ParcursDosarCardState extends State<ParcursDosarCard> {
  late Future<List<Dosar>> _viitor = ParcursDosar.cauta(widget.dosar.numar);

  void _reincearca() =>
      setState(() => _viitor = ParcursDosar.cauta(widget.dosar.numar, reincarca: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Dosar>>(
      future: _viitor,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _CardMic(
            icon: Icons.manage_search,
            text: 'Caut dosarul și la celelalte instanțe…',
          );
        }
        if (snap.hasError) {
          return _CardMic(
            icon: Icons.cloud_off,
            text: 'Nu am putut verifica dacă dosarul e și la alte instanțe.',
            actiune: 'Reîncearcă',
            onActiune: _reincearca,
          );
        }
        final toate = snap.data!;
        // Fără alte instanțe, cardul nu apare.
        if (!toate.any((d) => d.cheie != widget.dosar.cheie)) return const SizedBox.shrink();
        final etape = toate.any((d) => d.cheie == widget.dosar.cheie) ? toate : [...toate, widget.dosar];
        return _Parcurs(etape: ParcursDosar.ordoneaza(etape), curent: widget.dosar);
      },
    );
  }
}

class _CardMic extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actiune;
  final VoidCallback? onActiune;

  const _CardMic({required this.icon, required this.text, this.actiune, this.onActiune});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
            ),
            if (actiune != null) TextButton(onPressed: onActiune, child: Text(actiune!)),
          ],
        ),
      ),
    );
  }
}

class _Parcurs extends StatelessWidget {
  final List<Dosar> etape;
  final Dosar curent;

  const _Parcurs({required this.etape, required this.curent});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accentContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.route, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parcursul dosarului',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'La ${etape.length} instanțe · de jos în sus, de la fond la căile de atac',
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Ca în ierarhia instanțelor: cea mai înaltă sus, judecătoria jos.
            for (final (i, d) in etape.reversed.indexed)
              _Etapa(
                dosar: d,
                curent: d.cheie == curent.cheie,
                ultima: i == etape.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _Etapa extends StatefulWidget {
  final Dosar dosar;
  final bool curent;
  final bool ultima;

  const _Etapa({required this.dosar, required this.curent, required this.ultima});

  @override
  State<_Etapa> createState() => _EtapaState();
}

class _EtapaState extends State<_Etapa> {
  bool _sedinte = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.dosar;
    final solutie = ultimaPronuntare(d);
    final termen = urmatorulTermen(d);
    final sedinte = d.sedinteSortate;
    final culoare = widget.curent ? AppColors.primary : AppColors.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Linia de timp.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.curent ? AppColors.primary : AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: culoare, width: 3),
                  ),
                ),
                if (!widget.ultima)
                  Expanded(child: Container(width: 2, color: AppColors.outline)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.ultima ? 8 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (d.stadiuProcesual.isNotEmpty) StadiuChip.stadiu(d.stadiuProcesual),
                      if (widget.curent)
                        const Text(
                          'dosarul deschis',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(d.instanta, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (d.data != null)
                    Text(
                      'Înregistrat ${formateazaData(d.data)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                    ),
                  const SizedBox(height: 8),
                  _Solutie(solutie: solutie, termen: termen, dosar: d),
                  if (!widget.curent) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (sedinte.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => setState(() => _sedinte = !_sedinte),
                            icon: Icon(_sedinte ? Icons.expand_less : Icons.expand_more, size: 18),
                            label: Text('Ședințe (${sedinte.length})'),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: d)),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Deschide'),
                        ),
                      ],
                    ),
                    if (_sedinte)
                      for (final s in sedinte) SedintaRand(sedinta: s, dosar: d),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Solutie extends StatelessWidget {
  final Sedinta? solutie;
  final Sedinta? termen;
  final Dosar dosar;

  const _Solutie({required this.solutie, required this.termen, required this.dosar});

  @override
  Widget build(BuildContext context) {
    final s = solutie;
    if (s == null) {
      final t = termen;
      return Text(
        t == null
            ? 'Fără soluție publicată'
            : 'Următorul termen: ${formateazaData(t.data)}${t.ora.isEmpty ? '' : ', ora ${t.ora}'}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: t == null ? AppColors.onSurfaceVariant : AppColors.accent,
        ),
      );
    }
    final titlu = s.solutie.isNotEmpty ? s.solutie : 'Pronunțat';
    final detalii = [
      if (s.data != null) formateazaData(s.dataPronuntare ?? s.data),
      if (s.ora.isNotEmpty) 'ora ${s.ora}',
      if (s.complet.isNotEmpty) 'Complet ${s.complet}',
    ].join(' · ');
    return InkWell(
      onLongPress: () => optiuniSolutie(context, s, dosar: dosar),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Soluție: $titlu', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (s.solutieSumar.isNotEmpty && s.solutieSumar != s.solutie) ...[
              const SizedBox(height: 4),
              Text(scurteaza(s.solutieSumar, 220), style: const TextStyle(fontSize: 13, height: 1.35)),
            ],
            if (detalii.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(detalii, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
