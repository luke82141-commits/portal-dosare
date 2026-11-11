import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../widgets/comutare_monitorizare.dart';
import '../widgets/elemente.dart';
import 'dosare_filtrate_screen.dart';

/// Toate datele unui dosar (Figma: „03 · Detaliu dosar”): antet albastru cu
/// numărul și comutatorul de monitorizare, informațiile generale, apoi
/// părțile și ședințele în secțiuni care se deschid.
class DosarDetaliuScreen extends StatefulWidget {
  final Dosar dosar;

  const DosarDetaliuScreen({super.key, required this.dosar});

  @override
  State<DosarDetaliuScreen> createState() => _DosarDetaliuScreenState();
}

class _DosarDetaliuScreenState extends State<DosarDetaliuScreen> {
  @override
  void initState() {
    super.initState();
    // Deschiderea detaliului înseamnă că modificările au fost văzute.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BibliotecaService.instance.marcheazaCitit(widget.dosar.cheie);
    });
  }

  DosarSalvat? _salvat() {
    for (final d in BibliotecaService.instance.dosare) {
      if (d.dosar.cheie == widget.dosar.cheie) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: BibliotecaService.instance,
          builder: (context, _) {
            final salvat = _salvat();
            // Datele din bibliotecă sunt actualizate de verificarea periodică.
            final dosar = salvat?.dosar ?? widget.dosar;
            final sedinte = dosar.sedinteSortate;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _Antet(dosar: dosar, monitorizat: salvat != null),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (salvat != null && salvat.modificari.isNotEmpty) ...[
                        _Modificari(salvat: salvat),
                        const SizedBox(height: 16),
                      ],
                      _InformatiiGenerale(dosar: dosar),
                      const SizedBox(height: 16),
                      SectiuneExtensibila(
                        icon: Icons.person,
                        titlu: 'Părți',
                        numar: dosar.parti.length,
                        copii: dosar.parti.isEmpty
                            ? [const _Gol('Portalul nu afișează părți pentru acest dosar.')]
                            : [for (final p in dosar.parti) ParteRand(parte: p)],
                      ),
                      const SizedBox(height: 16),
                      SectiuneExtensibila(
                        icon: Icons.event,
                        titlu: 'Ședințe',
                        numar: sedinte.length,
                        copii: sedinte.isEmpty
                            ? [const _Gol('Nu există încă ședințe publicate.')]
                            : [for (final s in sedinte) SedintaRand(sedinta: s)],
                      ),
                      if (dosar.caiAtac.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SectiuneExtensibila(
                          icon: Icons.call_split,
                          titlu: 'Căi de atac',
                          numar: dosar.caiAtac.length,
                          deschisInitial: false,
                          copii: [for (final c in dosar.caiAtac) _CaleAtacRand(cale: c)],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        salvat?.ultimaVerificare != null
                            ? 'Ultima verificare: ${formateazaDataOra(salvat!.ultimaVerificare)}'
                                ' · sursa: portal.just.ro'
                            : 'Sursa: portal.just.ro',
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Antet extends StatelessWidget {
  final Dosar dosar;
  final bool monitorizat;

  const _Antet({required this.dosar, required this.monitorizat});

  @override
  Widget build(BuildContext context) {
    const alb = AppColors.onPrimary;
    final chips = [
      (dosar.stadiuProcesual, TipFiltru.stadiu),
      (dosar.categorie, TipFiltru.categorie),
      if (dosar.data != null) ('Înregistrat ${formateazaData(dosar.data)}', TipFiltru.an),
    ].where((e) => e.$1.isNotEmpty);

    void filtreaza(TipFiltru tip) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DosareFiltrateScreen(filtre: FiltreDosare.din(tip, dosar))),
        );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.hero)),
      ),
      padding: const EdgeInsets.only(bottom: 20),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  const BackButton(color: alb),
                  const Expanded(
                    child: Text(
                      'Detaliu dosar',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: alb),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: BibliotecaService.instance,
                    builder: (context, _) {
                      final b = BibliotecaService.instance;
                      if (b.dosare.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        tooltip: 'Dosarele mele',
                        color: alb,
                        icon: Badge(
                          isLabelVisible: b.totalNecitite > 0,
                          label: Text('${b.totalNecitite}'),
                          child: const Icon(Icons.collections_bookmark_outlined),
                        ),
                        onPressed: () => _arataDosarele(context, dosar),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Copiază numărul dosarului',
                    color: alb,
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: dosar.numar));
                      messenger.showSnackBar(
                        SnackBar(content: Text('Numărul ${dosar.numar} a fost copiat.')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: monitorizat ? 'Oprește monitorizarea' : 'Monitorizează dosarul',
                    color: monitorizat ? AppColors.accentContainer : alb,
                    icon: Icon(monitorizat ? Icons.bookmark : Icons.bookmark_add_outlined),
                    onPressed: () => comutaMonitorizare(context, dosar),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    dosar.numar,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: alb),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => filtreaza(TipFiltru.instanta),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.account_balance,
                              size: 16,
                              color: alb.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              dosar.instanta,
                              style: TextStyle(fontSize: 14, color: alb.withValues(alpha: 0.85)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 18, color: alb.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (text, tip) in chips)
                        Material(
                          color: alb.withValues(alpha: 0.16),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () => filtreaza(tip),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: Text(
                                text,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: alb,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: alb.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      onTap: () => comutaMonitorizare(context, dosar),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            Icon(
                              monitorizat ? Icons.notifications_active : Icons.notifications_none,
                              size: 22,
                              color: AppColors.accentContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    monitorizat ? 'Monitorizare activă' : 'Monitorizează dosarul',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: alb,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Te anunțăm când apare un termen sau o soluție nouă',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.33,
                                      color: alb.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: monitorizat,
                              onChanged: (_) => comutaMonitorizare(context, dosar),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista dosarelor monitorizate, ca foaie de jos: tap deschide direct
/// detaliul altui dosar, fără întoarcere la ecranul principal.
void _arataDosarele(BuildContext context, Dosar curent) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    builder: (ctx) {
      final dosare = BibliotecaService.instance.dosare;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                dosare.length == 1 ? 'Un dosar monitorizat' : '${dosare.length} dosare monitorizate',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: dosare.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final s = dosare[i];
                  final esteCurent = s.dosar.cheie == curent.cheie;
                  return Material(
                    color: esteCurent ? AppColors.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (esteCurent) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: s.dosar)),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.dosar.numar,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [s.dosar.instanta, s.dosar.obiect]
                                        .where((e) => e.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            s.necitite > 0
                                ? StadiuChip.nou(s.necitite)
                                : StadiuChip.stadiu(s.dosar.stadiuProcesual),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _InformatiiGenerale extends StatelessWidget {
  final Dosar dosar;

  const _InformatiiGenerale({required this.dosar});

  @override
  Widget build(BuildContext context) {
    final randuri = [
      ('Data înregistrării', formateazaData(dosar.data)),
      ('Secție', dosar.sectie),
      ('Obiect', dosar.obiect),
      ('Stadiu procesual', dosar.stadiuProcesual),
      ('Categorie caz', dosar.categorie),
      if (dosar.dataModificare != null)
        ('Modificat pe portal', formateazaData(dosar.dataModificare)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informații generale',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < randuri.length; i++) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        randuri[i].$1,
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        randuri[i].$2.isEmpty ? '—' : randuri[i].$2,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.36,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Schimbările detectate pe portal, pentru dosarele monitorizate.
class _Modificari extends StatefulWidget {
  final DosarSalvat salvat;

  const _Modificari({required this.salvat});

  @override
  State<_Modificari> createState() => _ModificariState();
}

class _ModificariState extends State<_Modificari> {
  bool _toate = false;

  @override
  Widget build(BuildContext context) {
    final modificari = widget.salvat.modificari;
    final afisate = _toate ? modificari : modificari.take(3).toList();
    final ascunse = modificari.length - afisate.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.history, size: 20, color: AppColors.success),
                SizedBox(width: 8),
                Text(
                  'Modificări detectate',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            for (final m in afisate)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.text, style: const TextStyle(fontSize: 14, height: 1.36)),
                    Text(
                      'detectat ${formateazaDataOra(m.detectataLa)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            if (ascunse > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _toate = true),
                  child: Text('Arată încă $ascunse mai vechi'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaleAtacRand extends StatelessWidget {
  final CaleAtac cale;

  const _CaleAtacRand({required this.cale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [cale.tip, formateazaData(cale.dataDeclarare)].where((e) => e.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (cale.parteDeclaratoare.isNotEmpty)
            Text(
              'Declarată de ${cale.parteDeclaratoare}',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _Gol extends StatelessWidget {
  final String text;

  const _Gol(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: const TextStyle(color: AppColors.onSurfaceVariant)),
    );
  }
}
