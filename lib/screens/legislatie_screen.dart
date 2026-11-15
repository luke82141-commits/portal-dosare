import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/legislatie_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elemente.dart';
import 'act_normativ_screen.dart';

/// Căutare în Portalul Legislativ (legislatie.just.ro): text liber sau titlu,
/// număr și an („Legea 85/2014”), cu filtre după tip, an și emitent.
class LegislatieScreen extends StatefulWidget {
  /// Căutare pornită direct (ex. din obiectul unui dosar).
  final CerereLegislatie? cerereInitiala;
  final String? tipInitial;
  final String? etichetaInitiala;

  /// Pentru teste.
  final LegislatieService? service;

  const LegislatieScreen({
    super.key,
    this.cerereInitiala,
    this.tipInitial,
    this.etichetaInitiala,
    this.service,
  });

  @override
  State<LegislatieScreen> createState() => _LegislatieScreenState();
}

const _cheieRecente = 'legislatie_cautari_recente';

class _LegislatieScreenState extends State<LegislatieScreen> {
  final _text = TextEditingController();
  late final LegislatieService _service = widget.service ?? LegislatieService.instance;

  bool _doarTitlu = false;
  FiltreLegislatie _filtre = const FiltreLegislatie();
  CerereLegislatie? _cerere;
  final List<ActNormativ> _acte = [];
  int _pagina = 0;
  bool _maiSunt = false;
  bool _seIncarca = false;
  String? _eroare;
  List<String> _recente = [];

  @override
  void initState() {
    super.initState();
    _incarcaRecente();
    final c = widget.cerereInitiala;
    if (c != null) {
      _text.text = widget.etichetaInitiala ?? _textPentru(c);
      if (widget.tipInitial != null) _filtre = FiltreLegislatie(tipuri: {widget.tipInitial!});
      WidgetsBinding.instance.addPostFrameCallback((_) => _porneste(c));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _textPentru(CerereLegislatie c) {
    if (c.numar.isNotEmpty) return c.an == null ? c.numar : '${c.numar}/${c.an}';
    return c.text.isNotEmpty ? c.text : c.titlu;
  }

  Future<void> _incarcaRecente() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => _recente = p.getStringList(_cheieRecente) ?? []);
    } catch (_) {}
  }

  Future<void> _salveazaRecenta(String s) async {
    final t = s.trim();
    if (t.isEmpty) return;
    final lista = [
      t,
      ..._recente.where((r) => r.toLowerCase() != t.toLowerCase()),
    ].take(8).toList();
    setState(() => _recente = lista);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_cheieRecente, lista);
    } catch (_) {}
  }

  Future<void> _stergeRecente() async {
    setState(() => _recente = []);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cheieRecente);
    } catch (_) {}
  }

  void _cautaDinBara() {
    final intrare = _text.text.trim();
    if (intrare.isEmpty) return;
    FocusScope.of(context).unfocus();
    final interpretat = CerereLegislatie.dinText(intrare);
    var cerere = interpretat.cerere;
    if (_doarTitlu && cerere.text.isNotEmpty) cerere = CerereLegislatie(titlu: cerere.text);
    if (interpretat.tip != null) {
      _filtre = _filtre.copyWith(tipuri: {interpretat.tip!});
    }
    _salveazaRecenta(intrare);
    _porneste(cerere);
  }

  Future<void> _porneste(CerereLegislatie cerere) async {
    setState(() {
      _cerere = cerere;
      _acte.clear();
      _pagina = 0;
      _maiSunt = false;
      _eroare = null;
    });
    await _incarcaPagina();
  }

  Future<void> _incarcaPagina() async {
    final cerere = _cerere;
    if (cerere == null || _seIncarca) return;
    setState(() {
      _seIncarca = true;
      _eroare = null;
    });
    try {
      final p = await _service.cauta(cerere, pagina: _pagina + 1);
      if (!mounted || cerere != _cerere) return;
      final vazute = _acte.map((a) => a.cheie).toSet();
      setState(() {
        _acte.addAll(p.acte.where((a) => vazute.add(a.cheie)));
        _pagina++;
        _maiSunt = p.maiSunt;
      });
    } catch (e) {
      if (mounted) setState(() => _eroare = e.toString());
    } finally {
      if (mounted) setState(() => _seIncarca = false);
    }
  }

  void _cautaRecenta(String s) {
    _text.text = s;
    _cautaDinBara();
  }

  @override
  Widget build(BuildContext context) {
    final vizibile = aplicaFiltre(_acte, _filtre);
    return Scaffold(
      appBar: AppBar(title: const Text('Legislație')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            controller: _text,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _cautaDinBara(),
            decoration: InputDecoration(
              hintText: 'Ex.: Legea 85/2014, OUG 195/2002, uzucapiune',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Caută',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _cautaDinBara,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('În tot textul')),
              ButtonSegment(value: true, label: Text('Doar în titlu')),
            ],
            selected: {_doarTitlu},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _doarTitlu = s.first),
          ),
          const SizedBox(height: 10),
          _BaraFiltre(
            filtre: _filtre,
            emitenti: emitentiDin(_acte),
            onSchimbat: (f) => setState(() => _filtre = f),
          ),
          const SizedBox(height: 14),
          ..._continut(vizibile),
          const SizedBox(height: 20),
          const Text(
            'Sursa: Portalul Legislativ al Ministerului Justiției (legislatie.just.ro). '
            'Textele au caracter informativ; forma oficială este cea publicată în Monitorul Oficial.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<Widget> _continut(List<ActNormativ> vizibile) {
    if (_cerere == null) return _ecranInitial();
    if (_seIncarca && _acte.isEmpty) {
      return const [_IncarcareLegislatie(), SizedBox(height: 12), CardSchelet(), CardSchelet()];
    }
    if (_eroare != null && _acte.isEmpty) {
      return [
        StareMesaj(
          icon: Icons.cloud_off,
          titlu: 'Căutarea nu a mers',
          text: _eroare!,
          buton: 'Reîncearcă',
          onButon: _incarcaPagina,
        ),
      ];
    }
    if (_acte.isEmpty) {
      return [
        const StareMesaj(
          icon: Icons.search_off,
          titlu: 'Niciun act găsit',
          text:
              'Încearcă alte cuvinte, doar numărul și anul (ex. 287/2009) sau caută în tot textul.',
        ),
      ];
    }
    final ascunse = _acte.length - vizibile.length;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              vizibile.length == 1 ? '1 act' : '${vizibile.length} acte',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          _MeniuOrdine(
            ordine: _filtre.ordine,
            onSchimbat: (o) => setState(() => _filtre = _filtre.copyWith(ordine: o)),
          ),
        ],
      ),
      if (ascunse > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$ascunse ${ascunse == 1 ? 'act ascuns' : 'acte ascunse'} de filtre',
            style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
        ),
      const SizedBox(height: 4),
      for (final a in vizibile)
        _CardAct(
          act: a,
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ActNormativScreen(act: a))),
        ),
      if (vizibile.isEmpty)
        StareMesaj(
          icon: Icons.filter_alt_off_outlined,
          titlu: 'Filtrele ascund toate actele',
          text: 'Am găsit ${_acte.length} acte, dar niciunul nu se potrivește filtrelor alese.',
          buton: 'Șterge filtrele',
          onButon: () => setState(() => _filtre = FiltreLegislatie(ordine: _filtre.ordine)),
        ),
      if (_eroare != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_eroare!, style: const TextStyle(color: AppColors.error)),
        ),
      if (_maiSunt)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _seIncarca ? null : _incarcaPagina,
            icon: _seIncarca
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: const Text('Încarcă mai multe'),
          ),
        ),
    ];
  }

  List<Widget> _ecranInitial() {
    const exemple = [
      ('Codul civil', CerereLegislatie(numar: '287', an: 2009), 'LEGE'),
      ('Codul de procedură civilă', CerereLegislatie(numar: '134', an: 2010), 'LEGE'),
      ('Codul penal', CerereLegislatie(numar: '286', an: 2009), 'LEGE'),
      ('Codul de procedură penală', CerereLegislatie(numar: '135', an: 2010), 'LEGE'),
      ('Codul muncii', CerereLegislatie(numar: '53', an: 2003), 'LEGE'),
      ('Insolvența (Legea 85/2014)', CerereLegislatie(numar: '85', an: 2014), 'LEGE'),
    ];
    return [
      if (_recente.isNotEmpty) ...[
        AntetSectiune('Căutări recente', actiune: 'Șterge', onActiune: _stergeRecente),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _recente)
              Pastila(r, icon: Icons.history, onTap: () => _cautaRecenta(r)),
          ],
        ),
        const SizedBox(height: 18),
      ],
      const AntetSectiune('Coduri și legi des folosite'),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in exemple)
            Pastila(
              e.$1,
              icon: Icons.menu_book_outlined,
              onTap: () {
                _text.text = e.$1;
                setState(() => _filtre = _filtre.copyWith(tipuri: {e.$3}));
                _porneste(e.$2);
              },
            ),
        ],
      ),
      const SizedBox(height: 18),
      const _Sfaturi(),
    ];
  }
}

class _IncarcareLegislatie extends StatelessWidget {
  const _IncarcareLegislatie();

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
          Text(
            'Se caută pe legislatie.just.ro…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onPrimaryContainer,
            ),
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
        ],
      ),
    );
  }
}

class _Sfaturi extends StatelessWidget {
  const _Sfaturi();

  @override
  Widget build(BuildContext context) {
    Widget rand(String a, String b) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(a, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(b, style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cum cauți', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            rand('Legea 85/2014', 'actul exact, după tip, număr și an'),
            rand('OUG 195/2002', 'merge și cu OUG, OG, HG, Decret, Ordin'),
            rand('uzucapiune', 'cuvinte din textul actelor'),
            rand('Filtre', 'restrâng rezultatele după tip, an și emitent'),
          ],
        ),
      ),
    );
  }
}

class _CardAct extends StatelessWidget {
  final ActNormativ act;
  final VoidCallback onTap;

  const _CardAct({required this.act, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = act.dataVigoare;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StadiuChip.stadiu(act.denumireScurta),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                act.titlu.isEmpty ? act.denumireScurta : act.titlu,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600),
              ),
              if (act.emitent.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  act.emitent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ],
              if (act.publicatie.isNotEmpty || d != null) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (act.publicatie.isNotEmpty) act.publicatie,
                    if (d != null) 'în vigoare din ${_zi(d)}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _zi(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class _MeniuOrdine extends StatelessWidget {
  final OrdineLegislatie ordine;
  final ValueChanged<OrdineLegislatie> onSchimbat;

  const _MeniuOrdine({required this.ordine, required this.onSchimbat});

  static const _etichete = {
    OrdineLegislatie.relevanta: 'Relevanță',
    OrdineLegislatie.celeMaiNoi: 'Cele mai noi',
    OrdineLegislatie.celeMaiVechi: 'Cele mai vechi',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OrdineLegislatie>(
      initialValue: ordine,
      onSelected: onSchimbat,
      itemBuilder: (_) => [
        for (final e in _etichete.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 18, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            _etichete[ordine]!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastilele de filtre: Tip act, An, Emitent, plus „Șterge” când sunt active.
class _BaraFiltre extends StatelessWidget {
  final FiltreLegislatie filtre;
  final List<String> emitenti;
  final ValueChanged<FiltreLegislatie> onSchimbat;

  const _BaraFiltre({required this.filtre, required this.emitenti, required this.onSchimbat});

  String get _textTip {
    if (filtre.tipuri.isEmpty) return 'Tip act';
    if (filtre.tipuri.length == 1) return etichetaTip(filtre.tipuri.first);
    return 'Tip act · ${filtre.tipuri.length}';
  }

  String get _textAn {
    final de = filtre.anDe, pana = filtre.anPana;
    if (de == null && pana == null) return 'An';
    if (de != null && pana != null) return de == pana ? '$de' : '$de–$pana';
    return de != null ? 'din $de' : 'până în $pana';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Pastila(
            _textTip,
            icon: Icons.gavel,
            activ: filtre.tipuri.isNotEmpty,
            onTap: () async {
              final r = await _alegeTipuri(context, filtre.tipuri);
              if (r != null) onSchimbat(filtre.copyWith(tipuri: r));
            },
          ),
          const SizedBox(width: 8),
          Pastila(
            _textAn,
            icon: Icons.calendar_today_outlined,
            activ: filtre.anDe != null || filtre.anPana != null,
            onTap: () async {
              final r = await _alegeAni(context, filtre.anDe, filtre.anPana);
              if (r != null) onSchimbat(filtre.copyWith(anDe: () => r.$1, anPana: () => r.$2));
            },
          ),
          const SizedBox(width: 8),
          Pastila(
            filtre.emitent.isEmpty ? 'Emitent' : filtre.emitent,
            icon: Icons.account_balance_outlined,
            activ: filtre.emitent.isNotEmpty,
            onTap: () async {
              final r = await _alegeEmitent(context, filtre.emitent, emitenti);
              if (r != null) onSchimbat(filtre.copyWith(emitent: r));
            },
          ),
          if (filtre.active) ...[
            const SizedBox(width: 8),
            Pastila(
              'Șterge filtrele',
              icon: Icons.close,
              onTap: () => onSchimbat(FiltreLegislatie(ordine: filtre.ordine)),
            ),
          ],
        ],
      ),
    );
  }
}

Future<Set<String>?> _alegeTipuri(BuildContext context, Set<String> curente) {
  final ales = {...curente};
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tip act', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tipuriActe)
                    FilterChip(
                      label: Text(etichetaTip(t)),
                      selected: ales.contains(t),
                      onSelected: (v) => setState(() => v ? ales.add(t) : ales.remove(t)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, <String>{}),
                    child: const Text('Toate'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, ales),
                    child: const Text('Aplică'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<(int?, int?)?> _alegeAni(BuildContext context, int? de, int? pana) {
  final cDe = TextEditingController(text: de?.toString() ?? '');
  final cPana = TextEditingController(text: pana?.toString() ?? '');
  int? an(String s) {
    final v = int.tryParse(s.trim());
    return v != null && v >= 1800 && v <= 2100 ? v : null;
  }

  return showModalBottomSheet<(int?, int?)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Anul actului', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cDe,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Din anul'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: cPana,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Până în anul'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, (null, null)),
                  child: const Text('Oricare'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (an(cDe.text), an(cPana.text))),
                  child: const Text('Aplică'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _alegeEmitent(BuildContext context, String curent, List<String> sugestii) {
  final c = TextEditingController(text: curent);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Emitent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: sugestii.isEmpty,
              decoration: const InputDecoration(hintText: 'Ex.: Parlamentul, Guvernul, ANAF'),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),
            if (sugestii.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Din rezultate',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in sugestii.take(8))
                    Pastila(s, onTap: () => Navigator.pop(context, s)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Oricare'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, c.text.trim()),
                  child: const Text('Aplică'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
