import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/acte_cunoscute.dart';
import '../services/act_structura.dart';
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
  late final LegislatieService _service =
      widget.service ?? LegislatieService.instance;

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
      if (widget.tipInitial != null)
        _filtre = FiltreLegislatie(tipuri: {widget.tipInitial!});
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
    if (c.numar.isNotEmpty)
      return c.an == null ? c.numar : '${c.numar}/${c.an}';
    return c.text.isNotEmpty ? c.text : c.titlu;
  }

  Future<void> _incarcaRecente() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted)
        setState(() => _recente = p.getStringList(_cheieRecente) ?? []);
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
    if (directa.isNotEmpty &&
        (directa.first.fel == FelSugestie.numar || rest.length >= 4)) {
      _aplica(directa.first, intrare);
      return;
    }
    _aplica(
      SugestieLegislatie(
        _doarTitlu ? FelSugestie.titlu : FelSugestie.text,
        rest,
        '',
        _doarTitlu
            ? CerereLegislatie(titlu: rest)
            : CerereLegislatie(text: rest),
        articol: articol,
      ),
      intrare,
    );
  }

  void _aplica(SugestieLegislatie s, [String? deSalvat]) {
    FocusScope.of(context).unfocus();
    final eticheta =
        deSalvat ?? s.titlu.replaceAll('„', '').replaceAll('”', '');
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
    // „Legea 307” fără an: serviciul întoarce actele cu numărul 307 de toate
    // tipurile; dacă filtrul le ascunde pe toate, mai aducem câteva pagini.
    if (mounted &&
        cerere == _cerere &&
        _eroare == null &&
        _maiSunt &&
        _pagina < 5 &&
        aplicaFiltre(_acte, _filtre).isEmpty) {
      await _incarcaPagina();
    }
  }

  /// Deschide actul; din rezultatele căutării în text, direct la articolul
  /// în care apare termenul.
  void _deschide(ActNormativ a, {String? laArticol}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ActNormativScreen(act: a, articolInitial: _articol ?? laArticol),
        ),
      );

  List<ActNormativ> _vizibile() {
    final filtrate = aplicaFiltre(_acte, _filtre);
    final c = _cerere;
    if (_filtre.ordine != OrdineLegislatie.relevanta || c == null)
      return filtrate;
    final q = c.text.isNotEmpty ? c.text : c.titlu;
    return q.isEmpty ? filtrate : ordoneazaDupaRelevanta(filtrate, q);
  }

  bool get _aratSugestii => _focus.hasFocus && _text.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final vizibile = _vizibile();
    final areRezultate = _cerere != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Legislație')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _CasetaCautare(
            controller: _text,
            focus: _focus,
            doarTitlu: _doarTitlu,
            onSchimbat: () => setState(() {}),
            onCauta: _cautaDinBara,
            onMod: (v) => setState(() => _doarTitlu = v),
          ),
          if (_aratSugestii) ...[
            const SizedBox(height: 10),
            _Sugestii(
              lista: sugestii(_text.text, recente: _recente),
              interogare: extrageArticol(_text.text).rest,
              onAlege: _aplica,
            ),
          ] else ...[
            if (areRezultate) ...[
              const SizedBox(height: 12),
              _BaraFiltre(
                filtre: _filtre,
                emitenti: emitentiDin(_acte),
                onSchimbat: (f) => setState(() => _filtre = f),
              ),
            ],
            const SizedBox(height: 16),
            ..._continut(vizibile),
            const SizedBox(height: 24),
            const Text(
              'Sursa: Portalul Legislativ al Ministerului Justiției (legislatie.just.ro). '
              'Textele au caracter informativ; forma oficială este cea publicată în Monitorul Oficial.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _continut(List<ActNormativ> vizibile) {
    if (_cerere == null) return _ecranInitial();
    if (_seIncarca && _acte.isEmpty) {
      return const [
        _IncarcareLegislatie(),
        SizedBox(height: 12),
        CardSchelet(),
        CardSchelet(),
      ];
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
          text: 'Încearcă alte cuvinte, doar numărul și anul (ex. 287/2009) sau caută în tot textul.',
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
            onSchimbat: (o) =>
                setState(() => _filtre = _filtre.copyWith(ordine: o)),
          ),
        ],
      ),
      if (ascunse > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$ascunse ${ascunse == 1 ? 'act ascuns' : 'acte ascunse'} de filtre',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      const SizedBox(height: 4),
      for (final a in vizibile)
        _CardAct(
          act: a,
          articol: _articol,
          termen: c.text.isNotEmpty ? c.text : c.titlu,
          onTap: () => _deschide(
            a,
            laArticol: c.text.isNotEmpty
                ? fragmentDinAct(a.text, c.text)?.nrArticol
                : null,
          ),
        ),
      if (vizibile.isEmpty)
        StareMesaj(
          icon: Icons.filter_alt_off_outlined,
          titlu: 'Filtrele ascund toate actele',
          text:
              'Am găsit ${_acte.length} acte, dar niciunul nu se potrivește filtrelor alese.',
          buton: 'Șterge filtrele',
          onButon: () => setState(
            () => _filtre = FiltreLegislatie(ordine: _filtre.ordine),
          ),
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
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TitluSectiune('Favorite'),
                Card(
                  child: Column(
                    children: [
                      for (final (i, s) in salvate.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 64),
                        _RandLista(
                          icon: Icons.star_rounded,
                          culoare: AppColors.accent,
                          fundal: AppColors.accentContainer,
                          titlu: s.denumire,
                          subtitlu: s.titlu,
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
        Row(
          children: [
            const Expanded(child: _TitluSectiune('Căutări recente')),
            TextButton(onPressed: _stergeRecente, child: const Text('Șterge')),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _recente)
              ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text(r),
                onPressed: () {
                  _text.text = r;
                  _cautaDinBara();
                },
              ),
          ],
        ),
        const SizedBox(height: 22),
      ],
      const _TitluSectiune('Coduri și legi uzuale'),
      LayoutBuilder(
        builder: (context, c) {
          final latime = (c.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in coduri)
                SizedBox(
                  width: latime,
                  child: _TileCod(
                    act: a,
                    onTap: () => _aplica(_sugestieAct(a)),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

class _TitluSectiune extends StatelessWidget {
  final String text;
  const _TitluSectiune(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
    ),
  );
}

/// Caseta de căutare: câmp alb, cu umbră fină, și alegerea „text / titlu”
/// dedesubt, ca pe un motor de căutare.
class _CasetaCautare extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool doarTitlu;
  final VoidCallback onSchimbat;
  final VoidCallback onCauta;
  final ValueChanged<bool> onMod;

  const _CasetaCautare({
    required this.controller,
    required this.focus,
    required this.doarTitlu,
    required this.onSchimbat,
    required this.onCauta,
    required this.onMod,
  });

  @override
  Widget build(BuildContext context) {
    Widget mod(String text, bool valoare) {
      final activ = doarTitlu == valoare;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onMod(valoare),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: activ ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: activ ? AppColors.onPrimary : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focus.hasFocus ? AppColors.primary : AppColors.outline,
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            onChanged: (_) => onSchimbat(),
            onSubmitted: (_) => onCauta(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
              hintText: 'Lege, cod sau cuvinte cheie',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Șterge',
                      icon: const Icon(Icons.cancel, size: 20),
                      onPressed: () {
                        controller.clear();
                        focus.requestFocus();
                        onSchimbat();
                      },
                    ),
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                // Pe ecrane înguste (sau cu text mărit) se micșorează, nu ies din cadru.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Caută în',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          mod('Tot textul', false),
                          mod('Titluri', true),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Caută',
                  onPressed: onCauta,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(40, 40),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rând de listă cu pictogramă într-un cerc colorat.
class _RandLista extends StatelessWidget {
  final IconData icon;
  final Color culoare;
  final Color fundal;
  final String titlu;
  final InlineSpan? titluBogat;
  final String subtitlu;
  final Widget? dreapta;
  final VoidCallback onTap;

  const _RandLista({
    required this.icon,
    required this.titlu,
    required this.subtitlu,
    required this.onTap,
    this.titluBogat,
    this.dreapta,
    this.culoare = AppColors.primary,
    this.fundal = AppColors.primaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: fundal, shape: BoxShape.circle),
              child: Icon(icon, size: 19, color: culoare),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    titluBogat ?? TextSpan(text: titlu),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (subtitlu.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitlu,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (dreapta != null) ...[const SizedBox(width: 8), dreapta!],
          ],
        ),
      ),
    );
  }
}

/// Culoarea fiecărui tip de act, ca să se recunoască dintr-o privire.
(Color, Color) culoriTip(String tip) {
  final t = fataDiacritice(tip).toUpperCase();
  if (t.startsWith('ORDONANTA'))
    return (AppColors.accent, AppColors.accentContainer);
  if (t.startsWith('HOTAR'))
    return (AppColors.success, AppColors.successContainer);
  if (t.startsWith('ORDIN') || t.startsWith('DECIZI') || t.startsWith('NORM')) {
    return (AppColors.warning, AppColors.warningContainer);
  }
  if (t.startsWith('CONSTITU'))
    return (AppColors.onPrimaryContainer, AppColors.primaryContainer);
  return (AppColors.primary, AppColors.primaryContainer);
}

class _TileCod extends StatelessWidget {
  final ActCunoscut act;
  final VoidCallback onTap;

  const _TileCod({required this.act, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (culoare, fundal) = culoriTip(act.tip);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: fundal,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  act.numar.isEmpty ? '1991' : '${act.numar}/${act.an}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: culoare,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                act.nume,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de sugestii de sub bară, ca la motoarele de căutare juridice:
/// actele cunoscute întâi, apoi căutarea în text și în titluri.
class _Sugestii extends StatelessWidget {
  final List<SugestieLegislatie> lista;
  final String interogare;
  final void Function(SugestieLegislatie) onAlege;

  const _Sugestii({
    required this.lista,
    required this.interogare,
    required this.onAlege,
  });

  IconData _icon(FelSugestie f) => switch (f) {
    FelSugestie.actCunoscut => Icons.menu_book_rounded,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final (i, s) in lista.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 64),
              _RandLista(
                icon: _icon(s.fel),
                culoare:
                    s.fel == FelSugestie.recenta ||
                        s.fel == FelSugestie.titlu ||
                        s.fel == FelSugestie.text
                    ? AppColors.onSurfaceVariant
                    : AppColors.primary,
                fundal:
                    s.fel == FelSugestie.recenta ||
                        s.fel == FelSugestie.titlu ||
                        s.fel == FelSugestie.text
                    ? AppColors.surfaceVariant
                    : AppColors.primaryContainer,
                titlu: s.titlu,
                titluBogat: TextSpan(
                  children: _evidentiaza(s.titlu, interogare),
                ),
                subtitlu: s.subtitlu,
                dreapta: s.deschideDirect
                    ? const Icon(
                        Icons.north_east,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      )
                    : null,
                onTap: () => onAlege(s),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Literele scrise apar îngroșate în sugestie („Codul civil”).
List<TextSpan> _evidentiaza(
  String text,
  String interogare, {
  bool cuvantIntreg = false,
}) {
  final cuvinte = fataDiacritice(interogare.toLowerCase())
      .split(RegExp(r'\s+'))
      .where((c) => c.length >= 2)
      .toList();
  final baza = fataDiacritice(text.toLowerCase());
  if (cuvinte.isEmpty || baza.length != text.length)
    return [TextSpan(text: text)];
  final marcat = List.filled(text.length, false);
  for (final c in cuvinte) {
    var start = 0;
    while (true) {
      final i = baza.indexOf(c, start);
      if (i < 0) break;
      var sf = i + c.length;
      // În fragmente evidențiem cuvântul întreg („Uzucapiunea”, nu „Uzucapiune”+„a”).
      if (cuvantIntreg) {
        while (sf < text.length &&
            RegExp(r'[\wăâîșțşţĂÂÎȘȚŞŢ]').hasMatch(text[sf])) {
          sf++;
        }
      }
      for (var k = i; k < sf; k++) {
        marcat[k] = true;
      }
      start = sf;
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
            ? (cuvantIntreg
                  ? const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      backgroundColor: AppColors.accentContainer,
                    )
                  : const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ))
            : const TextStyle(fontWeight: FontWeight.w400),
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

class _CardAct extends StatelessWidget {
  final ActNormativ act;
  final String? articol;
  final String termen;
  final VoidCallback onTap;

  const _CardAct({
    required this.act,
    required this.onTap,
    this.articol,
    this.termen = '',
  });

  @override
  Widget build(BuildContext context) {
    final d = act.dataVigoare;
    final fragment = fragmentDinAct(act.text, termen);
    final titlu = titluPrezentare(act);
    final (culoare, fundal) = culoriTip(act.tipAct);
    final aprobare = act.aprobatPrin;
    final meta = [
      if (act.emitent.isNotEmpty) act.emitent,
      if (d != null) 'în vigoare din ${_zi(d)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.outline),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: fundal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        act.denumireScurta,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: culoare,
                        ),
                      ),
                    ),
                    if (articol != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '→ art. $articol',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(children: _evidentiaza(titlu.principal, termen)),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                if (titlu.secundar.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    titlu.secundar,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (aprobare != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.verified_outlined,
                          size: 15,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Aprobat prin ${aprobare.denumire}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (fragment != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (fragment.articol != null) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.subdirectory_arrow_right,
                                size: 14,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  fragment.articol!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text.rich(
                          TextSpan(
                            children: [
                              if (fragment.inceputTaiat)
                                const TextSpan(text: '… '),
                              ..._evidentiaza(
                                fragment.text,
                                termen,
                                cuvantIntreg: true,
                              ),
                              if (fragment.sfarsitTaiat)
                                const TextSpan(text: ' …'),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
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
        for (final e in _etichete.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
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

  const _BaraFiltre({
    required this.filtre,
    required this.emitenti,
    required this.onSchimbat,
  });

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
              if (r != null)
                onSchimbat(
                  filtre.copyWith(anDe: () => r.$1, anPana: () => r.$2),
                );
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
              const Text(
                'Tip act',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tipuriActe)
                    FilterChip(
                      label: Text(etichetaTip(t)),
                      selected: ales.contains(t),
                      onSelected: (v) =>
                          setState(() => v ? ales.add(t) : ales.remove(t)),
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
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Anul actului',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
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
                    decoration: const InputDecoration(
                      labelText: 'Până în anul',
                    ),
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
                  onPressed: () =>
                      Navigator.pop(context, (an(cDe.text), an(cPana.text))),
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

Future<String?> _alegeEmitent(
  BuildContext context,
  String curent,
  List<String> sugestii,
) {
  final c = TextEditingController(text: curent);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Emitent',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: sugestii.isEmpty,
              decoration: const InputDecoration(
                hintText: 'Ex.: Parlamentul, Guvernul, ANAF',
              ),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),
            if (sugestii.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Din rezultate',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
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
