import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/acte_cunoscute.dart';
import '../services/legislatie_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elemente.dart';
import 'act_normativ_screen.dart';

/// Căutare în Portalul Legislativ (legislatie.just.ro). Bara înțelege
/// „Legea 85/2014”, „OUG 195/2002”, numele codurilor („codul civ”) și
/// „codul civil art. 1357”; în timp ce scrii arată sugestii. Rezultatele
/// au filtre după tip, an și emitent și sunt ordonate după relevanță.
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
  final _focus = FocusNode();
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

  /// Când căutarea vine dintr-un act anume (cod, favorit, „Legea 85/2014”),
  /// îl deschidem direct, eventual la [_articol].
  bool _deschideDirect = false;
  String? _articol;

  @override
  void initState() {
    super.initState();
    _incarcaRecente();
    ActeSalvateService.instance.incarca();
    _focus.addListener(() => setState(() {}));
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
    _focus.dispose();
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

  /// Enter în bară: număr („85/2014”) sau un act cunoscut („codul civil”)
  /// merg direct la act; altfel căutăm textul.
  void _cautaDinBara() {
    final intrare = _text.text.trim();
    if (intrare.isEmpty) return;
    final lista = sugestii(intrare);
    final directa = lista.where(
      (s) => s.fel == FelSugestie.numar || s.fel == FelSugestie.actCunoscut,
    );
    final (:rest, :articol) = extrageArticol(intrare);
    if (directa.isNotEmpty && (directa.first.fel == FelSugestie.numar || rest.length >= 4)) {
      _aplica(directa.first, intrare);
      return;
    }
    _aplica(
      SugestieLegislatie(
        _doarTitlu ? FelSugestie.titlu : FelSugestie.text,
        rest,
        '',
        _doarTitlu ? CerereLegislatie(titlu: rest) : CerereLegislatie(text: rest),
        articol: articol,
      ),
      intrare,
    );
  }

  void _aplica(SugestieLegislatie s, [String? deSalvat]) {
    FocusScope.of(context).unfocus();
    final eticheta = deSalvat ?? s.titlu.replaceAll('„', '').replaceAll('”', '');
    _text.text = eticheta;
    setState(() {
      _filtre = FiltreLegislatie(
        tipuri: s.tip != null ? {s.tip!} : const {},
        ordine: _filtre.ordine,
      );
      _deschideDirect = s.deschideDirect;
      _articol = s.articol;
      if (s.fel == FelSugestie.titlu) _doarTitlu = true;
      if (s.fel == FelSugestie.text) _doarTitlu = false;
    });
    _salveazaRecenta(eticheta);
    _porneste(s.cerere);
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
      if (_deschideDirect) {
        _deschideDirect = false;
        final tip = _filtre.tipuri.length == 1 ? _filtre.tipuri.first : null;
        final exact = potrivireExacta(_acte, cerere, tip);
        if (exact != null) _deschide(exact);
      }
    } catch (e) {
      if (mounted) setState(() => _eroare = e.toString());
    } finally {
      if (mounted) setState(() => _seIncarca = false);
    }
  }

  void _deschide(ActNormativ a) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ActNormativScreen(act: a, articolInitial: _articol),
    ),
  );

  List<ActNormativ> _vizibile() {
    final filtrate = aplicaFiltre(_acte, _filtre);
    final c = _cerere;
    if (_filtre.ordine != OrdineLegislatie.relevanta || c == null) return filtrate;
    final q = c.text.isNotEmpty ? c.text : c.titlu;
    return q.isEmpty ? filtrate : ordoneazaDupaRelevanta(filtrate, q);
  }

  bool get _aratSugestii => _focus.hasFocus && _text.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final vizibile = _vizibile();
    return Scaffold(
      appBar: AppBar(title: const Text('Legislație')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            controller: _text,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _cautaDinBara(),
            decoration: InputDecoration(
              hintText: 'Codul civil art. 1357, Legea 85/2014, uzucapiune',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _text.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Șterge',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _text.clear();
                        _focus.requestFocus();
                        setState(() {});
                      },
                    ),
            ),
          ),
          if (_aratSugestii) ...[
            const SizedBox(height: 8),
            _Sugestii(
              lista: sugestii(_text.text, recente: _recente),
              interogare: extrageArticol(_text.text).rest,
              onAlege: _aplica,
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('În tot textul')),
                      ButtonSegment(value: true, label: Text('Doar în titlu')),
                    ],
                    selected: {_doarTitlu},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _doarTitlu = s.first),
                  ),
                ),
              ],
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
    final c = _cerere!;
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
          articol: _articol,
          termen: c.text.isNotEmpty ? c.text : c.titlu,
          onTap: () => _deschide(a),
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

  SugestieLegislatie _sugestieAct(ActCunoscut a) => SugestieLegislatie(
    FelSugestie.actCunoscut,
    a.nume,
    a.trimitere,
    cerereActCunoscut(a),
    tip: a.tip,
    deschideDirect: true,
  );

  List<Widget> _ecranInitial() {
    final coduri = acteCunoscute.take(10).toList();
    return [
      ListenableBuilder(
        listenable: ActeSalvateService.instance,
        builder: (context, _) {
          final salvate = ActeSalvateService.instance.acte;
          if (salvate.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AntetSectiune('Favorite'),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      for (final (i, s) in salvate.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.star_rounded, color: AppColors.accent),
                          title: Text(
                            s.denumire,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(s.titlu, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _aplica(
                            SugestieLegislatie(
                              FelSugestie.actCunoscut,
                              s.denumire,
                              '',
                              s.cerere,
                              tip: s.tip,
                              deschideDirect: true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      if (_recente.isNotEmpty) ...[
        AntetSectiune('Căutări recente', actiune: 'Șterge', onActiune: _stergeRecente),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _recente)
              Pastila(
                r,
                icon: Icons.history,
                onTap: () {
                  _text.text = r;
                  _cautaDinBara();
                },
              ),
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
          for (final a in coduri)
            Pastila(a.nume, icon: Icons.menu_book_outlined, onTap: () => _aplica(_sugestieAct(a))),
        ],
      ),
      const SizedBox(height: 18),
      const _Sfaturi(),
    ];
  }
}

/// Lista de sugestii de sub bară, ca la motoarele de căutare juridice:
/// actele cunoscute întâi, apoi căutarea în text și în titluri.
class _Sugestii extends StatelessWidget {
  final List<SugestieLegislatie> lista;
  final String interogare;
  final void Function(SugestieLegislatie) onAlege;

  const _Sugestii({required this.lista, required this.interogare, required this.onAlege});

  IconData _icon(FelSugestie f) => switch (f) {
    FelSugestie.actCunoscut => Icons.menu_book_outlined,
    FelSugestie.numar => Icons.tag,
    FelSugestie.text => Icons.search,
    FelSugestie.titlu => Icons.title,
    FelSugestie.recenta => Icons.history,
  };

  @override
  Widget build(BuildContext context) {
    if (lista.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SUGESTII',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          for (final (i, s) in lista.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            ListTile(
              dense: true,
              leading: Icon(_icon(s.fel), color: AppColors.primary),
              title: Text.rich(
                TextSpan(children: _evidentiaza(s.titlu, interogare)),
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text(s.subtitlu),
              trailing: s.deschideDirect
                  ? const Icon(Icons.north_east, size: 18, color: AppColors.onSurfaceVariant)
                  : null,
              onTap: () => onAlege(s),
            ),
          ],
        ],
      ),
    );
  }
}

/// Literele scrise apar îngroșate în sugestie („Codul civil”).
List<TextSpan> _evidentiaza(String text, String interogare) {
  final cuvinte = fataDiacritice(interogare.toLowerCase())
      .split(RegExp(r'\s+'))
      .where((c) => c.length >= 2)
      .toList();
  final baza = fataDiacritice(text.toLowerCase());
  if (cuvinte.isEmpty || baza.length != text.length) return [TextSpan(text: text)];
  final marcat = List.filled(text.length, false);
  for (final c in cuvinte) {
    var start = 0;
    while (true) {
      final i = baza.indexOf(c, start);
      if (i < 0) break;
      for (var k = i; k < i + c.length; k++) {
        marcat[k] = true;
      }
      start = i + c.length;
    }
  }
  final r = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    var j = i;
    while (j < text.length && marcat[j] == marcat[i]) {
      j++;
    }
    r.add(
      TextSpan(
        text: text.substring(i, j),
        style: marcat[i]
            ? const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)
            : null,
      ),
    );
    i = j;
  }
  return r;
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
            rand('codul civ', 'sugestii în timp ce scrii; codurile după nume'),
            rand('Legea 85/2014', 'actul exact, după tip, număr și an'),
            rand('c. civ. art. 1357', 'deschide direct articolul'),
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
  final String? articol;
  final String termen;
  final VoidCallback onTap;

  const _CardAct({required this.act, required this.onTap, this.articol, this.termen = ''});

  /// Primul loc din text unde apare termenul căutat, cu puțin context.
  String? get _fragment {
    final t = termen.trim();
    if (t.length < 3 || act.text.isEmpty) return null;
    final baza = fataDiacritice(act.text.toLowerCase());
    final i = baza.indexOf(fataDiacritice(t.toLowerCase()));
    if (i < 0 || baza.length != act.text.length) return null;
    final start = (i - 70).clamp(0, act.text.length);
    final end = (i + t.length + 110).clamp(0, act.text.length);
    final f = act.text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${start > 0 ? '…' : ''}$f${end < act.text.length ? '…' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final d = act.dataVigoare;
    final fragment = _fragment;
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
                  if (articol != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'art. $articol',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: _evidentiaza(
                    act.titlu.isEmpty ? act.denumireScurta : act.titlu,
                    termen,
                  ),
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600),
              ),
              if (fragment != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceVariant,
                    border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
                  ),
                  child: Text.rich(
                    TextSpan(children: _evidentiaza(fragment, termen)),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (act.emitent.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_outlined,
                      size: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        act.emitent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              if (act.publicatie.isNotEmpty || d != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 14, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          if (act.publicatie.isNotEmpty) act.publicatie,
                          if (d != null) 'în vigoare din ${_zi(d)}',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ],
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
