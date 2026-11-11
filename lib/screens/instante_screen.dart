import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/instante_portal.dart';
import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/ruta.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

String _faraDiacritice(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ăâ]'), 'a')
    .replaceAll('î', 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't');

/// Dosarele din bibliotecă aflate la instanța [i].
List<DosarSalvat> _dosareLa(InstantaPortal i) => [
      for (final s in BibliotecaService.instance.dosare)
        if (s.dosar.institutie.toLowerCase() == i.cod.toLowerCase()) s,
    ];

/// Toate instanțele din țară, grupate pe județe, cu căutare.
class InstanteScreen extends StatefulWidget {
  const InstanteScreen({super.key});

  @override
  State<InstanteScreen> createState() => _InstanteScreenState();
}

class _InstanteScreenState extends State<InstanteScreen> {
  final _cautare = TextEditingController();
  TipInstanta? _tip;

  @override
  void dispose() {
    _cautare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _faraDiacritice(_cautare.text.trim());
    final gasite = toateInstantele.where((i) {
      if (_tip != null && i.tip != _tip) return false;
      if (text.isEmpty) return true;
      return _faraDiacritice('${i.nume} ${i.judet} ${i.curte}').contains(text);
    }).toList();

    // Pe județe, alfabetic; în fiecare județ: curte, tribunale, judecătorii.
    final peJudete = <String, List<InstantaPortal>>{};
    for (final i in gasite) {
      (peJudete[i.judet] ??= []).add(i);
    }
    final judete = peJudete.keys.toList()
      ..sort((a, b) => _faraDiacritice(a).compareTo(_faraDiacritice(b)));
    for (final l in peJudete.values) {
      l.sort((a, b) {
        final t = a.tip.index.compareTo(b.tip.index);
        return t != 0 ? t : _faraDiacritice(a.nume).compareTo(_faraDiacritice(b.nume));
      });
    }

    return Scaffold(
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Instanțe',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${toateInstantele.length} instanțe · contact și programul serviciilor',
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _cautare,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Caută instanță, oraș sau județ',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _cautare.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Șterge',
                                  onPressed: () => setState(_cautare.clear),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (tip, eticheta) in [
                              (null, 'Toate'),
                              (TipInstanta.curteDeApel, 'Curți de apel'),
                              (TipInstanta.tribunal, 'Tribunale'),
                              (TipInstanta.judecatorie, 'Judecătorii'),
                            ]) ...[
                              Pastila(eticheta, activ: _tip == tip, onTap: () => setState(() => _tip = tip)),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (gasite.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: StareMesaj(
                    icon: Icons.search_off,
                    titlu: 'Nicio instanță găsită',
                    text: 'Încearcă după numele orașului, de exemplu „Ploiești”.',
                  ),
                ),
              ),
            for (final j in judete) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(
                    j.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (k, i) in peJudete[j]!.indexed) ...[
                          if (k > 0) const Divider(indent: 64),
                          _RandInstanta(i),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _RandInstanta extends StatelessWidget {
  final InstantaPortal i;

  const _RandInstanta(this.i);

  @override
  Widget build(BuildContext context) {
    final dosare = _dosareLa(i).length;
    final (icon, culoare, fundal) = switch (i.tip) {
      TipInstanta.curteDeApel => (Icons.gavel, AppColors.accent, AppColors.accentContainer),
      TipInstanta.tribunal => (Icons.balance, AppColors.primary, AppColors.primaryContainer),
      TipInstanta.judecatorie => (Icons.account_balance, AppColors.onSurfaceVariant, AppColors.surfaceVariant),
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InstantaScreen(instanta: i)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: fundal, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: culoare),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(i.nume, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            if (dosare > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  dosare == 1 ? '1 dosar' : '$dosare dosare',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success),
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Pagina unei instanțe: contact și program (pagina oficială), rută, lista
/// de ședințe și dosarele tale de acolo.
class InstantaScreen extends StatelessWidget {
  final InstantaPortal instanta;

  const InstantaScreen({super.key, required this.instanta});

  Future<void> _deschide(BuildContext context, Uri uri, {bool inAplicatie = true}) async {
    final messenger = ScaffoldMessenger.of(context);
    var reusit = false;
    try {
      reusit = await launchUrl(
        uri,
        mode: inAplicatie ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!reusit) {
      messenger.showSnackBar(const SnackBar(content: Text('Nu am putut deschide pagina.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = instanta;
    return Scaffold(
      appBar: AppBar(title: const Text('Instanță')),
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final dosare = _dosareLa(i);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(i.nume, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 6),
              Text(
                [
                  i.judet == 'București' ? 'Municipiul București' : 'Județul ${i.judet}',
                  if (i.tip != TipInstanta.curteDeApel) 'raza Curții de Apel ${i.curte}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _Actiune(
                      icon: Icons.contact_phone_outlined,
                      titlu: 'Date de contact și program',
                      text: 'Adresă, telefoane, email și programul la registratură, '
                          'arhivă, relații cu publicul și celelalte servicii',
                      principal: true,
                      onTap: () => _deschide(context, i.paginaContact),
                    ),
                    const Divider(indent: 64),
                    _Actiune(
                      icon: Icons.event_note_outlined,
                      titlu: 'Lista de ședințe',
                      text: 'Cauzele programate pe complete',
                      onTap: () => _deschide(context, i.listaSedinte),
                    ),
                    const Divider(indent: 64),
                    _Actiune(
                      icon: Icons.public,
                      titlu: 'Pagina instanței pe portal',
                      text: 'Comunicate, informații de interes public',
                      onTap: () => _deschide(context, i.paginaAcasa),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deschide(context, rutaGoogleMaps(i.nume), inAplicatie: false),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Google Maps'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deschide(context, rutaWaze(i.nume), inAplicatie: false),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: const Text('Waze'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Informațiile sunt cele publicate de instanță pe portal.just.ro, '
                'mereu la zi. Ruta pornește din locația ta.',
                style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.onSurfaceVariant),
              ),
              if (dosare.isNotEmpty) ...[
                const SizedBox(height: 24),
                AntetSectiune(dosare.length == 1 ? 'Dosarul tău aici' : 'Dosarele tale aici (${dosare.length})'),
                for (final s in dosare) ...[
                  const SizedBox(height: 12),
                  DosarCardWidget(key: ValueKey(s.dosar.cheie), dosar: s.dosar, salvat: s),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Actiune extends StatelessWidget {
  final IconData icon;
  final String titlu;
  final String text;
  final bool principal;
  final VoidCallback onTap;

  const _Actiune({
    required this.icon,
    required this.titlu,
    required this.text,
    required this.onTap,
    this.principal = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: principal ? AppColors.primary : AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: principal ? AppColors.onPrimary : AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titlu, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, size: 18, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
