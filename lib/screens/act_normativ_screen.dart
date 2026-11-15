import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/act_export.dart';
import '../services/act_structura.dart';
import '../services/legislatie_service.dart';
import '../theme/app_theme.dart';

/// Un act normativ, așezat ca o lege: titluri și capitole centrate, articole
/// evidențiate, alineate cu numărul îngroșat. Are bară de unelte: mergi la
/// articol, cuprins, caută în act, mărimea textului, PDF și Word.
class ActNormativScreen extends StatefulWidget {
  final ActNormativ act;

  /// Articolul la care se deschide („1357”).
  final String? articolInitial;

  /// Pentru teste; altfel serviciul comun.
  final LegislatieService? service;

  const ActNormativScreen({
    super.key,
    required this.act,
    this.articolInitial,
    this.service,
  });

  @override
  State<ActNormativScreen> createState() => _ActNormativScreenState();
}

const _cheieMarime = 'legislatie_marime_text';

class _ActNormativScreenState extends State<ActNormativScreen> {
  final _lista = ItemScrollController();
  final _pozitii = ItemPositionsListener.create();
  final _cauta = TextEditingController();
  final _focusCauta = FocusNode();

  List<BlocAct>? _blocuri;
  double _marime = 1.0;
  bool _cautareDeschisa = false;
  List<int> _potriviri = const [];
  int _curent = 0;
  int? _articolEvidentiat;
  bool _seExporta = false;

  /// Codul anexat legii („Codul amenajării teritoriului...”), căutat separat.
  String? _numeCod;
  ActNormativ? _cod;
  bool _cautCod = false;

  ActNormativ get _act => widget.act;

  @override
  void initState() {
    super.initState();
    ActeSalvateService.instance.incarca();
    _incarcaMarime();
    _structureaza();
  }

  @override
  void dispose() {
    _cauta.dispose();
    _focusCauta.dispose();
    super.dispose();
  }

  Future<void> _structureaza() async {
    final text = _act.text;
    final blocuri = await structureazaInFundal(text);
    if (!mounted) return;
    setState(() => _blocuri = blocuri);
    final cod = numeCodAnexat(_act);
    if (cod != null) _gasesteCod(cod);
    final art = widget.articolInitial;
    if (art != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _mergiLaArticol(art));
    }
  }

  Future<void> _incarcaMarime() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getDouble(_cheieMarime);
      if (m != null && mounted) setState(() => _marime = m);
    } catch (_) {}
  }

  Future<void> _schimbaMarime(double m) async {
    setState(() => _marime = m.clamp(0.85, 1.6));
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_cheieMarime, _marime);
    } catch (_) {}
  }

  void _arata(String mesaj) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(mesaj)));
  }

  /// Blocul i e pe poziția i+1 în listă (prima e antetul actului).
  void _saltLa(int indiceBloc) {
    if (!_lista.isAttached) return;
    _lista.scrollTo(
      index: indiceBloc + 1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  bool _mergiLaArticol(String nr) {
    final b = _blocuri;
    if (b == null) return false;
    final i = indiceArticol(b, nr);
    if (i == null) {
      _arata('Articolul $nr nu apare în acest text.');
      return false;
    }
    setState(() => _articolEvidentiat = i);
    _saltLa(i);
    return true;
  }

  Future<void> _dialogArticol() async {
    final c = TextEditingController();
    final nr = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mergi la articolul'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            hintText: 'Ex.: 1357 sau 5^1',
            prefixText: 'Art. ',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Mergi'),
          ),
        ],
      ),
    );
    if (nr != null && nr.trim().isNotEmpty) _mergiLaArticol(nr.trim());
  }

  Future<void> _deschideCuprins() async {
    final b = _blocuri;
    if (b == null) return;
    final intrari = cuprins(b);
    if (intrari.isEmpty) {
      _arata('Actul nu are titluri sau articole de afișat în cuprins.');
      return;
    }
    final ales = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _Cuprins(intrari: intrari),
    );
    if (ales != null) {
      setState(
        () => _articolEvidentiat = b[ales].tip == TipBloc.articol ? ales : null,
      );
      _saltLa(ales);
    }
  }

  void _deschideCautarea() {
    setState(() => _cautareDeschisa = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusCauta.requestFocus(),
    );
  }

  void _inchideCautarea() {
    _cauta.clear();
    setState(() {
      _cautareDeschisa = false;
      _potriviri = const [];
    });
  }

  void _cautaInAct(String termen) {
    final b = _blocuri ?? const [];
    final p = potriviri(b, termen);
    setState(() {
      _potriviri = p;
      _curent = 0;
    });
    if (p.isNotEmpty) _saltLa(p.first);
  }

  void _urmatoarea(int pas) {
    if (_potriviri.isEmpty) return;
    setState(() => _curent = (_curent + pas) % _potriviri.length);
    _saltLa(_potriviri[_curent]);
  }

  Future<void> _gasesteCod(String nume) async {
    setState(() {
      _numeCod = nume;
      _cautCod = true;
    });
    ActNormativ? gasit;
    final service = widget.service ?? LegislatieService.instance;
    // Codul are titlul „CODUL ... din 5 august 2026 ( Legea nr. 169/2026 )”.
    final cereri = [
      CerereLegislatie(titlu: nume),
      if (_act.numar.isNotEmpty && _act.an != null)
        CerereLegislatie(titlu: 'Legea nr. ${_act.numar}/${_act.an}'),
    ];
    for (final c in cereri) {
      try {
        final p = await service.cauta(c, simplu: true);
        gasit = alegeCodAnexat(p.acte, _act, nume);
      } catch (_) {}
      if (gasit != null) break;
    }
    if (!mounted) return;
    setState(() {
      _cod = gasit;
      _cautCod = false;
    });
    // Legea are doar antetul: deschidem direct codul, în locul ei.
    final cod = gasit;
    if (cod != null && _act.text.length < 3000) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActNormativScreen(
            act: cod,
            articolInitial: widget.articolInitial,
            service: widget.service,
          ),
        ),
      );
    }
  }

  void _deschideCod() {
    final cod = _cod;
    if (cod == null) {
      _deschidePortal();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActNormativScreen(act: cod, service: widget.service),
      ),
    );
  }

  Future<void> _deschidePortal() async {
    final uri = Uri.tryParse(_act.linkHtml);
    var reusit = false;
    if (uri != null) {
      try {
        reusit = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {}
    }
    if (!reusit) _arata('Nu am putut deschide pagina.');
  }

  Future<void> _partajeazaActul() async {
    await SharePlus.instance.share(
      ShareParams(
        text: [
          _act.denumireScurta,
          if (_act.titlu.isNotEmpty) _act.titlu,
          if (_act.linkHtml.isNotEmpty) _act.linkHtml,
        ].join('\n'),
        subject: _act.denumireScurta,
      ),
    );
  }

  Future<void> _exporta(String format) async {
    final b = _blocuri;
    if (b == null || _seExporta) return;
    setState(() => _seExporta = true);
    try {
      final Uint8List date;
      final String tip;
      if (format == 'pdf') {
        Future<Uint8List> font(String nume) async =>
            (await rootBundle.load('assets/fonts/LiberationSerif-$nume.ttf'))
                .buffer
                .asUint8List();
        final normal = await font('Regular');
        final bold = await font('Bold');
        final italic = await font('Italic');
        date = await actPdfInFundal(_act, b, normal, bold, italic);
        tip = 'application/pdf';
      } else {
        date = await actDocxInFundal(_act, b);
        tip = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      }
      final nume = numeFisierAct(_act, format);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(date, mimeType: tip, name: nume)],
          fileNameOverrides: [nume],
          subject: nume,
        ),
      );
    } catch (e) {
      _arata('Fișierul nu a putut fi creat: $e');
    } finally {
      if (mounted) setState(() => _seExporta = false);
    }
  }

  Future<void> _actiuniArticol(int indice) async {
    final b = _blocuri!;
    final antet = b[indice];
    final text = textArticol(b, indice, _act.denumireScurta);
    final ales = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                [
                  antet.eticheta,
                  if (antet.titlu.isNotEmpty) antet.titlu,
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copiază articolul'),
              subtitle: const Text(
                'Cu trimiterea la act, gata de pus într-o cerere',
              ),
              onTap: () => Navigator.pop(context, 'copiaza'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Trimite articolul'),
              onTap: () => Navigator.pop(context, 'trimite'),
            ),
          ],
        ),
      ),
    );
    if (ales == 'copiaza') {
      await Clipboard.setData(ClipboardData(text: text));
      _arata('${antet.eticheta} a fost copiat.');
    } else if (ales == 'trimite') {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: antet.eticheta),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocuri = _blocuri;
    return Scaffold(
      appBar: AppBar(
        title: Text(_act.denumireScurta),
        actions: [
          ListenableBuilder(
            listenable: ActeSalvateService.instance,
            builder: (context, _) {
              final salvat = ActeSalvateService.instance.esteSalvat(_act);
              return IconButton(
                tooltip: salvat ? 'Scoate din favorite' : 'Adaugă la favorite',
                icon: Icon(
                  salvat ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: salvat ? AppColors.accent : null,
                ),
                onPressed: () async {
                  final acum = await ActeSalvateService.instance.comuta(_act);
                  _arata(
                    acum
                        ? 'Actul a fost adăugat la favorite.'
                        : 'Actul a fost scos din favorite.',
                  );
                },
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'portal' => _deschidePortal(),
              'partajeaza' => _partajeazaActul(),
              'copiaza' => Clipboard.setData(
                ClipboardData(text: _act.text),
              ).then((_) => _arata('Textul actului a fost copiat.')),
              _ => null,
            },
            itemBuilder: (_) => [
              if (_act.linkHtml.isNotEmpty)
                const PopupMenuItem(
                  value: 'portal',
                  child: Text('Forma de pe legislatie.just.ro'),
                ),
              const PopupMenuItem(
                value: 'partajeaza',
                child: Text('Trimite linkul actului'),
              ),
              if (_act.text.isNotEmpty)
                const PopupMenuItem(
                  value: 'copiaza',
                  child: Text('Copiază tot textul'),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _cautareDeschisa ? _baraCautare() : _baraUnelte(),
        ),
      ),
      body: blocuri == null
          ? const Center(child: CircularProgressIndicator())
          : ScrollablePositionedList.builder(
              itemScrollController: _lista,
              itemPositionsListener: _pozitii,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: blocuri.length + 1,
              itemBuilder: (context, i) {
                if (i == 0)
                  return _AntetAct(
                    act: _act,
                    goala: blocuri.isEmpty && _numeCod == null,
                    onPortal: _deschidePortal,
                    cod: _numeCod == null
                        ? null
                        : _CardCod(
                            nume: _numeCod!,
                            seCauta: _cautCod,
                            gasit: _cod != null,
                            onDeschide: _deschideCod,
                          ),
                  );
                final k = i - 1;
                final b = blocuri[k];
                final potrivireCurenta =
                    _potriviri.isNotEmpty && _potriviri[_curent] == k;
                return _VizualBloc(
                  bloc: b,
                  marime: _marime,
                  termen: _cautareDeschisa ? _cauta.text : '',
                  curent: potrivireCurenta,
                  evidentiat: _articolEvidentiat == k,
                  onArticol: b.tip == TipBloc.articol
                      ? () => _actiuniArticol(k)
                      : null,
                );
              },
            ),
    );
  }

  Widget _baraUnelte() {
    final gata = _blocuri != null;
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _Unealta(
            icon: Icons.manage_search,
            text: 'Caută în act',
            onTap: gata ? _deschideCautarea : null,
          ),
          _Unealta(
            icon: Icons.turn_right,
            text: 'Mergi la art.',
            onTap: gata ? _dialogArticol : null,
          ),
          _Unealta(
            icon: Icons.account_tree_outlined,
            text: 'Cuprins',
            onTap: gata ? _deschideCuprins : null,
          ),
          _Unealta(
            icon: Icons.text_decrease,
            text: 'A−',
            onTap: _marime > 0.85 ? () => _schimbaMarime(_marime - 0.1) : null,
          ),
          _Unealta(
            icon: Icons.text_increase,
            text: 'A+',
            onTap: _marime < 1.6 ? () => _schimbaMarime(_marime + 0.1) : null,
          ),
          _Unealta(
            icon: Icons.picture_as_pdf_outlined,
            text: 'PDF',
            incarca: _seExporta,
            onTap: gata && !_seExporta ? () => _exporta('pdf') : null,
          ),
          _Unealta(
            icon: Icons.description_outlined,
            text: 'Word',
            onTap: gata && !_seExporta ? () => _exporta('docx') : null,
          ),
        ],
      ),
    );
  }

  Widget _baraCautare() {
    final n = _potriviri.length;
    final areTermen = _cauta.text.trim().length >= 2;
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cauta,
              focusNode: _focusCauta,
              textInputAction: TextInputAction.search,
              onChanged: _cautaInAct,
              onSubmitted: (_) => _urmatoarea(1),
              decoration: const InputDecoration(
                hintText: 'Caută în act',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            !areTermen ? '' : (n == 0 ? '0' : '${_curent + 1}/$n'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Anterior',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: n > 0 ? () => _urmatoarea(-1) : null,
          ),
          IconButton(
            tooltip: 'Următor',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: n > 0 ? () => _urmatoarea(1) : null,
          ),
          IconButton(
            tooltip: 'Închide',
            icon: const Icon(Icons.close),
            onPressed: _inchideCautarea,
          ),
        ],
      ),
    );
  }
}

class _Unealta extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool incarca;

  const _Unealta({
    required this.icon,
    required this.text,
    this.onTap,
    this.incarca = false,
  });

  @override
  Widget build(BuildContext context) {
    final activ = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: AppColors.primaryContainer.withValues(alpha: activ ? 1 : 0.5),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                incarca
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        icon,
                        size: 18,
                        color: activ
                            ? AppColors.onPrimaryContainer
                            : AppColors.onSurfaceVariant,
                      ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: activ
                        ? AppColors.onPrimaryContainer
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Prima pagină a actului, în același stil ca titlurile din text: eticheta
/// aurie, titlul centrat, datele de identificare discret, dedesubt.
class _AntetAct extends StatelessWidget {
  final ActNormativ act;
  final bool goala;
  final VoidCallback onPortal;

  final Widget? cod;

  const _AntetAct({
    required this.act,
    required this.goala,
    required this.onPortal,
    this.cod,
  });

  @override
  Widget build(BuildContext context) {
    final d = act.dataVigoare;
    final date = <(IconData, String)>[
      if (act.emitent.isNotEmpty) (Icons.account_balance_outlined, act.emitent),
      if (act.publicatie.isNotEmpty) (Icons.menu_book_outlined, act.publicatie),
      if (d != null)
        (
          Icons.event_available_outlined,
          'În vigoare din ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Column(
        children: [
          Text(
            act.denumireScurta.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            titluCurat(act.titlu.isEmpty ? act.denumireScurta : act.titlu),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          for (final (icon, text) in date)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Container(
            width: 56,
            height: 3,
            color: AppColors.accent.withValues(alpha: 0.5),
          ),
          ?cod,
          if (goala)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Serviciul nu a trimis textul acestui act.'),
                subtitle: const Text('Îl poți citi pe legislatie.just.ro.'),
                onTap: onPortal,
              ),
            ),
        ],
      ),
    );
  }
}

/// Legea doar aprobă codul; prevederile sunt în cod, publicat separat.
class _CardCod extends StatelessWidget {
  final String nume;
  final bool seCauta;
  final bool gasit;
  final VoidCallback onDeschide;

  const _CardCod({
    required this.nume,
    required this.seCauta,
    required this.gasit,
    required this.onDeschide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Prevederile sunt în cod',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Legea aprobă $nume, care e publicat separat, ca anexă.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: seCauta ? null : onDeschide,
              icon: seCauta
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      gasit
                          ? Icons.arrow_forward_rounded
                          : Icons.open_in_new_rounded,
                    ),
              label: Text(
                seCauta
                    ? 'Caut codul…'
                    : gasit
                    ? 'Deschide codul'
                    : 'Deschide pe legislatie.just.ro',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un bloc din textul actului, cu stilul potrivit tipului lui.
class _VizualBloc extends StatelessWidget {
  final BlocAct bloc;
  final double marime;
  final String termen;
  final bool curent;
  final bool evidentiat;
  final VoidCallback? onArticol;

  const _VizualBloc({
    required this.bloc,
    required this.marime,
    required this.termen,
    required this.curent,
    required this.evidentiat,
    this.onArticol,
  });

  List<InlineSpan> _cuEvidentiere(String text, TextStyle? stil) {
    final p = pozitii(text, termen);
    if (p.isEmpty) return [TextSpan(text: text, style: stil)];
    final fundal = curent ? const Color(0xFFFFD166) : AppColors.accentContainer;
    final r = <InlineSpan>[];
    var start = 0;
    for (final (a, b) in p) {
      if (a > start)
        r.add(TextSpan(text: text.substring(start, a), style: stil));
      r.add(
        TextSpan(
          text: text.substring(a, b),
          style: (stil ?? const TextStyle()).copyWith(
            backgroundColor: fundal,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = b;
    }
    if (start < text.length)
      r.add(TextSpan(text: text.substring(start), style: stil));
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final m = marime;
    final corp = TextStyle(
      fontSize: 15 * m,
      height: 1.55,
      color: AppColors.onSurface,
    );
    switch (bloc.tip) {
      case TipBloc.structura:
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  children: _cuEvidentiere(
                    bloc.eticheta,
                    TextStyle(
                      fontSize: 13 * m,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                textAlign: TextAlign.center,
              ),
              if (bloc.titlu.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: _cuEvidentiere(
                      bloc.titlu,
                      TextStyle(
                        fontSize: 18 * m,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 3,
                color: AppColors.accent.withValues(alpha: 0.5),
              ),
            ],
          ),
        );
      case TipBloc.articol:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Material(
            color: evidentiat || curent
                ? AppColors.accentContainer
                : AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onArticol,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        bloc.eticheta,
                        style: TextStyle(
                          fontSize: 13 * m,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(
                            children: _cuEvidentiere(
                              bloc.titlu,
                              TextStyle(
                                fontSize: 15 * m,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case TipBloc.alineat:
      case TipBloc.litera:
        final litera = bloc.tip == TipBloc.litera;
        return Padding(
          padding: EdgeInsets.only(left: litera ? 18 : 0, top: 4, bottom: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${bloc.eticheta} ',
                  style: corp.copyWith(
                    fontWeight: FontWeight.w700,
                    color: litera ? AppColors.onSurface : AppColors.primary,
                  ),
                ),
                ..._cuEvidentiere(bloc.text, corp),
              ],
            ),
            textAlign: TextAlign.start,
          ),
        );
      case TipBloc.nota:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: const BoxDecoration(
            color: AppColors.surfaceVariant,
            border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
          ),
          child: Text.rich(
            TextSpan(
              children: _cuEvidentiere(
                bloc.text,
                TextStyle(
                  fontSize: 12.5 * m,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      case TipBloc.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(children: _cuEvidentiere(bloc.text, corp)),
            textAlign: TextAlign.start,
          ),
        );
    }
  }
}

class _Cuprins extends StatefulWidget {
  final List<IntrareCuprins> intrari;

  const _Cuprins({required this.intrari});

  @override
  State<_Cuprins> createState() => _CuprinsState();
}

class _CuprinsState extends State<_Cuprins> {
  bool _articole = false;
  String _filtru = '';

  @override
  Widget build(BuildContext context) {
    final areStructura = widget.intrari.any((e) => !e.eArticol);
    final arataArticole = _articole || !areStructura;
    final f = fataDiacritice(_filtru.toLowerCase());
    final lista = widget.intrari
        .where((e) => arataArticole || !e.eArticol)
        .where(
          (e) => f.isEmpty || fataDiacritice(e.text.toLowerCase()).contains(f),
        )
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cuprins',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (areStructura)
                  FilterChip(
                    label: const Text('Cu articole'),
                    selected: _articole,
                    onSelected: (v) => setState(() => _articole = v),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _filtru = v),
              decoration: const InputDecoration(
                hintText: 'Filtrează cuprinsul',
                isDense: true,
                prefixIcon: Icon(Icons.filter_list, size: 20),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: lista.length,
              itemBuilder: (context, i) {
                final e = lista[i];
                return InkWell(
                  onTap: () => Navigator.pop(context, e.indice),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16.0 + e.nivel * 14,
                      10,
                      16,
                      10,
                    ),
                    child: Text(
                      e.text,
                      style: TextStyle(
                        fontSize: e.eArticol ? 13.5 : 14.5,
                        fontWeight: e.eArticol
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: e.eArticol
                            ? AppColors.onSurface
                            : AppColors.primary,
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
  }
}
