import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

/// Din ce element al detaliului s-a pornit filtrarea.
enum TipFiltru { instanta, stadiu, categorie, an }

String _faraDiacritice(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ăâ]'), 'a')
    .replaceAll('î', 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't');

bool _contine(String text, String cautat) =>
    _faraDiacritice(text).contains(_faraDiacritice(cautat.trim()));

bool _inPerioada(DateTime? d, DateTimeRange? p) {
  if (p == null) return true;
  if (d == null) return false;
  final zi = DateUtils.dateOnly(d);
  return !zi.isBefore(p.start) && !zi.isAfter(p.end);
}

String _perioada(DateTimeRange p) => p.start == p.end
    ? formateazaData(p.start)
    : '${formateazaData(p.start)} – ${formateazaData(p.end)}';

/// Criteriile de filtrare a dosarelor salvate. Toate se combină: un dosar
/// trebuie să le îndeplinească pe toate. În cadrul unei liste (ex. două
/// instanțe) e suficientă una dintre valori.
class FiltreDosare {
  Set<String> institutii;
  Set<String> stadii;
  Set<String> categorii;
  Set<String> sectii;
  String obiect;
  String parte;
  DateTimeRange? inregistrare;
  DateTimeRange? modificare;

  FiltreDosare({
    Set<String>? institutii,
    Set<String>? stadii,
    Set<String>? categorii,
    Set<String>? sectii,
    this.obiect = '',
    this.parte = '',
    this.inregistrare,
    this.modificare,
  })  : institutii = institutii ?? {},
        stadii = stadii ?? {},
        categorii = categorii ?? {},
        sectii = sectii ?? {};

  /// Filtrul pornit dintr-un element apăsat în detaliul [d].
  factory FiltreDosare.din(TipFiltru tip, Dosar d) => switch (tip) {
        TipFiltru.instanta => FiltreDosare(institutii: {d.institutie}),
        TipFiltru.stadiu => FiltreDosare(stadii: {d.stadiuProcesual}),
        TipFiltru.categorie => FiltreDosare(categorii: {d.categorie}),
        TipFiltru.an => FiltreDosare(
            inregistrare: d.data == null
                ? null
                : DateTimeRange(
                    start: DateTime(d.data!.year),
                    end: DateTime(d.data!.year, 12, 31),
                  ),
          ),
      };

  FiltreDosare copie() => FiltreDosare(
        institutii: {...institutii},
        stadii: {...stadii},
        categorii: {...categorii},
        sectii: {...sectii},
        obiect: obiect,
        parte: parte,
        inregistrare: inregistrare,
        modificare: modificare,
      );

  bool potriveste(Dosar d) =>
      (institutii.isEmpty || institutii.contains(d.institutie)) &&
      (stadii.isEmpty || stadii.contains(d.stadiuProcesual)) &&
      (categorii.isEmpty || categorii.contains(d.categorie)) &&
      (sectii.isEmpty || sectii.contains(d.sectie)) &&
      (obiect.trim().isEmpty || _contine(d.obiect, obiect)) &&
      (parte.trim().isEmpty || d.parti.any((p) => _contine(p.nume, parte))) &&
      _inPerioada(d.data, inregistrare) &&
      _inPerioada(d.dataModificare, modificare);

  /// Filtrele active, ca etichete care se pot scoate pe rând.
  List<(String, VoidCallback)> etichete() => [
        for (final i in institutii) (numeInstanta(i), () => institutii.remove(i)),
        for (final s in stadii) (s, () => stadii.remove(s)),
        for (final c in categorii) (c, () => categorii.remove(c)),
        for (final s in sectii) (s, () => sectii.remove(s)),
        if (obiect.trim().isNotEmpty) ('Obiect: „${obiect.trim()}”', () => obiect = ''),
        if (parte.trim().isNotEmpty) ('Parte: „${parte.trim()}”', () => parte = ''),
        if (inregistrare != null)
          ('Data dosarului: ${_perioada(inregistrare!)}', () => inregistrare = null),
        if (modificare != null)
          ('Modificat: ${_perioada(modificare!)}', () => modificare = null),
      ];

  bool get gol => etichete().isEmpty;
}

/// Dosarele salvate, filtrate după oricâte criterii combinate.
class DosareFiltrateScreen extends StatefulWidget {
  final FiltreDosare? filtre;

  const DosareFiltrateScreen({super.key, this.filtre});

  @override
  State<DosareFiltrateScreen> createState() => _DosareFiltrateScreenState();
}

class _DosareFiltrateScreenState extends State<DosareFiltrateScreen> {
  late FiltreDosare _filtre = widget.filtre?.copie() ?? FiltreDosare();

  Future<void> _deschideFiltre() async {
    final rezultat = await showModalBottomSheet<FiltreDosare>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _FoaieFiltre(initiale: _filtre),
    );
    if (rezultat != null) setState(() => _filtre = rezultat);
  }

  @override
  Widget build(BuildContext context) {
    final etichete = _filtre.etichete();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dosarele mele'),
        actions: [
          IconButton(
            tooltip: 'Filtre',
            onPressed: _deschideFiltre,
            icon: Badge(
              isLabelVisible: etichete.isNotEmpty,
              label: Text('${etichete.length}'),
              child: const Icon(Icons.tune),
            ),
          ),
        ],
        shape: const Border(bottom: BorderSide(color: AppColors.outline)),
        bottom: etichete.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: etichete.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final (text, scoate) = etichete[i];
                      return InputChip(
                        label: Text(text),
                        onDeleted: () => setState(scoate),
                        deleteButtonTooltipMessage: 'Scoate filtrul',
                        backgroundColor: AppColors.primaryContainer,
                        labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onPrimaryContainer,
                        ),
                        deleteIconColor: AppColors.onPrimaryContainer,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        visualDensity: VisualDensity.compact,
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
              .where((s) => _filtre.potriveste(s.dosar))
              .toList();

          if (dosare.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StareMesaj(
                  icon: Icons.filter_alt_off_outlined,
                  titlu: 'Niciun dosar găsit',
                  text: 'Niciun dosar din biblioteca ta nu îndeplinește toate filtrele. '
                      'Scoate unul dintre ele sau schimbă-le.',
                  buton: 'Schimbă filtrele',
                  onButon: _deschideFiltre,
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

/// Foaia de jos cu toate criteriile. Valorile de alegere (instanțe, stadii
/// etc.) sunt cele care apar efectiv în bibliotecă.
class _FoaieFiltre extends StatefulWidget {
  final FiltreDosare initiale;

  const _FoaieFiltre({required this.initiale});

  @override
  State<_FoaieFiltre> createState() => _FoaieFiltreState();
}

class _FoaieFiltreState extends State<_FoaieFiltre> {
  late final FiltreDosare _f = widget.initiale.copie();
  late final _obiect = TextEditingController(text: _f.obiect);
  late final _parte = TextEditingController(text: _f.parte);

  @override
  void dispose() {
    _obiect.dispose();
    _parte.dispose();
    super.dispose();
  }

  Future<void> _alegePerioada(
    DateTimeRange? actuala,
    void Function(DateTimeRange?) seteaza,
  ) async {
    final p = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      initialDateRange: actuala,
      helpText: 'Alege perioada',
      saveText: 'Gata',
    );
    if (p != null) setState(() => seteaza(p));
  }

  @override
  Widget build(BuildContext context) {
    final dosare = [for (final s in BibliotecaService.instance.dosare) s.dosar];
    List<String> valori(String Function(Dosar) f) =>
        {for (final d in dosare) f(d)}.where((e) => e.isNotEmpty).toList()..sort();
    final potrivite = dosare.where(_f.potriveste).length;

    Widget sectiune(String titlu, Widget continut) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titlu,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              continut,
            ],
          ),
        );

    Widget alegeri(List<String> toate, Set<String> alese, [String Function(String)? nume]) =>
        toate.isEmpty
            ? const Text('—', style: TextStyle(color: AppColors.onSurfaceVariant))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in toate)
                    Pastila(
                      nume?.call(v) ?? v,
                      activ: alese.contains(v),
                      icon: alese.contains(v) ? Icons.check : null,
                      onTap: () => setState(() => alese.contains(v) ? alese.remove(v) : alese.add(v)),
                    ),
                ],
              );

    Widget perioada(DateTimeRange? p, void Function(DateTimeRange?) seteaza) => Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => _alegePerioada(p, seteaza),
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(p == null ? 'Oricând' : _perioada(p)),
              ),
            ),
            if (p != null)
              IconButton(
                tooltip: 'Șterge perioada',
                onPressed: () => setState(() => seteaza(null)),
                icon: const Icon(Icons.close),
              ),
          ],
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Filtre', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  sectiune(
                    'Părți',
                    TextField(
                      controller: _parte,
                      onChanged: (v) => setState(() => _f.parte = v),
                      decoration: const InputDecoration(
                        hintText: 'Nume, ex. Popescu',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                    ),
                  ),
                  sectiune(
                    'Obiect',
                    TextField(
                      controller: _obiect,
                      onChanged: (v) => setState(() => _f.obiect = v),
                      decoration: const InputDecoration(
                        hintText: 'ex. pretenții, uzucapiune',
                        prefixIcon: Icon(Icons.subject, size: 20),
                      ),
                    ),
                  ),
                  sectiune('Instanță', alegeri(valori((d) => d.institutie), _f.institutii, numeInstanta)),
                  sectiune('Stadiu / cale de atac', alegeri(valori((d) => d.stadiuProcesual), _f.stadii)),
                  sectiune('Materie', alegeri(valori((d) => d.categorie), _f.categorii)),
                  sectiune('Secție', alegeri(valori((d) => d.sectie), _f.sectii)),
                  sectiune('Data dosarului (înregistrare la instanță)', perioada(_f.inregistrare, (p) => _f.inregistrare = p)),
                  sectiune('Data modificării pe portal', perioada(_f.modificare, (p) => _f.modificare = p)),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      final gol = FiltreDosare();
                      _f
                        ..institutii = gol.institutii
                        ..stadii = gol.stadii
                        ..categorii = gol.categorii
                        ..sectii = gol.sectii
                        ..obiect = ''
                        ..parte = ''
                        ..inregistrare = null
                        ..modificare = null;
                      _obiect.clear();
                      _parte.clear();
                    }),
                    child: const Text('Resetează'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_f),
                      child: Text(
                        potrivite == 1 ? 'Arată un dosar' : 'Arată $potrivite dosare',
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
