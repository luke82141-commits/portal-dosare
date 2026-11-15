import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/legislatie_service.dart';
import '../theme/app_theme.dart';

/// Un act normativ: date de identificare, textul integral și căutare în text
/// („art. 712” sare la articol; orice alt cuvânt arată paragrafele cu el).
class ActNormativScreen extends StatefulWidget {
  final ActNormativ act;

  const ActNormativScreen({super.key, required this.act});

  @override
  State<ActNormativScreen> createState() => _ActNormativScreenState();
}

class _ActNormativScreenState extends State<ActNormativScreen> {
  final _cauta = TextEditingController();
  late final List<String> _paragrafe = paragrafeAct(widget.act.text);
  String _termen = '';

  @override
  void dispose() {
    _cauta.dispose();
    super.dispose();
  }

  Future<void> _deschidePortal() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(widget.act.linkHtml);
    var reusit = false;
    if (uri != null) {
      try {
        reusit = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {}
    }
    if (!reusit) {
      messenger.showSnackBar(const SnackBar(content: Text('Nu am putut deschide pagina.')));
    }
  }

  Future<void> _partajeaza() async {
    final a = widget.act;
    await SharePlus.instance.share(
      ShareParams(
        text: [
          a.denumireScurta,
          if (a.titlu.isNotEmpty) a.titlu,
          if (a.linkHtml.isNotEmpty) a.linkHtml,
        ].join('\n'),
        subject: a.denumireScurta,
      ),
    );
  }

  Future<void> _copiaza(String text, String mesaj) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(mesaj)));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.act;
    final selectie = selecteazaParagrafe(_paragrafe, _termen);
    return Scaffold(
      appBar: AppBar(
        title: Text(a.denumireScurta),
        actions: [
          IconButton(
            tooltip: 'Partajează',
            icon: const Icon(Icons.share_outlined),
            onPressed: _partajeaza,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.list(
              children: [
                _Antet(act: a),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (a.linkHtml.isNotEmpty)
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _deschidePortal,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Forma de pe portal'),
                        ),
                      ),
                    if (a.linkHtml.isNotEmpty) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: a.text.isEmpty
                            ? null
                            : () => _copiaza(a.text, 'Textul actului a fost copiat.'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiază textul'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_paragrafe.isNotEmpty)
                  TextField(
                    controller: _cauta,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _termen = v),
                    decoration: InputDecoration(
                      hintText: 'Caută în act sau „art. 712”',
                      prefixIcon: const Icon(Icons.manage_search),
                      suffixIcon: _termen.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _cauta.clear();
                                setState(() => _termen = '');
                              },
                            ),
                    ),
                  ),
                if (_termen.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      selectie.articol != null
                          ? (selectie.paragrafe.isEmpty
                                ? 'Articolul ${selectie.articol} nu apare în acest text.'
                                : 'Articolul ${selectie.articol}')
                          : '${selectie.paragrafe.length} '
                                '${selectie.paragrafe.length == 1 ? 'paragraf' : 'paragrafe'} cu „${_termen.trim()}”',
                      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 10),
                if (_paragrafe.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Serviciul nu a trimis textul acestui act. Deschide forma de pe portal.',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: selectie.paragrafe.length,
              itemBuilder: (context, i) {
                final p = selectie.paragrafe[i];
                return _Paragraf(
                  text: p,
                  evidentiaza: selectie.articol == null ? _termen.trim() : '',
                  onLongPress: () => _copiaza(p, 'Paragraful a fost copiat.'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Antet extends StatelessWidget {
  final ActNormativ act;

  const _Antet({required this.act});

  @override
  Widget build(BuildContext context) {
    final d = act.dataVigoare;
    final randuri = [
      ('Tip', act.tipAct.isEmpty ? '' : etichetaTip(act.tipAct)),
      ('Număr', act.numar),
      ('Emitent', act.emitent),
      ('Publicat în', act.publicatie),
      if (d != null)
        (
          'În vigoare din',
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
        ),
    ].where((r) => r.$2.trim().isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              act.titlu.isEmpty ? act.denumireScurta : act.titlu,
              style: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final r in randuri)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.$1,
                        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

class _Paragraf extends StatelessWidget {
  final String text;
  final String evidentiaza;
  final VoidCallback onLongPress;

  const _Paragraf({required this.text, required this.evidentiaza, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final titluArticol = esteTitluArticol(text) || esteTitluStructura(text);
    final stil = TextStyle(
      fontSize: titluArticol ? 15 : 14,
      height: 1.5,
      fontWeight: titluArticol ? FontWeight.w700 : FontWeight.w400,
      color: AppColors.onSurface,
    );
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(top: titluArticol ? 14 : 4, bottom: 4),
        child: Text.rich(TextSpan(style: stil, children: evidentieri(text, evidentiaza))),
      ),
    );
  }
}

/// Bucăți de text cu [termen] evidențiat (fără să conteze diacriticele și
/// literele mari).
List<TextSpan> evidentieri(String text, String termen) {
  if (termen.isEmpty) return [TextSpan(text: text)];
  final baza = fataDiacritice(text.toLowerCase());
  final t = fataDiacritice(termen.toLowerCase());
  final bucati = <TextSpan>[];
  var start = 0;
  while (true) {
    final i = baza.indexOf(t, start);
    if (i < 0) break;
    if (i > start) bucati.add(TextSpan(text: text.substring(start, i)));
    bucati.add(
      TextSpan(
        text: text.substring(i, i + t.length),
        style: const TextStyle(
          backgroundColor: AppColors.accentContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    start = i + t.length;
  }
  if (start < text.length) bucati.add(TextSpan(text: text.substring(start)));
  return bucati;
}

/// Textul actului, pe paragrafe nevide.
List<String> paragrafeAct(String text) =>
    text.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

final _reArticol = RegExp(r'^(?:art\.|articolul)\s*(\d+(?:\^\d+)?)', caseSensitive: false);

bool esteTitluArticol(String p) => _reArticol.hasMatch(p) && p.length < 80;

bool esteTitluStructura(String p) =>
    p.length < 80 && RegExp(r'^(TITLUL|CAPITOLUL|SECȚIUNEA|SECŢIUNEA|CARTEA|PARTEA)\b').hasMatch(p);

/// Ce afișăm după ce scrie omul în căutarea din act: un număr („712”,
/// „art. 712”) arată articolul întreg; altceva arată paragrafele care conțin
/// termenul. Gol = tot textul.
({String? articol, List<String> paragrafe}) selecteazaParagrafe(
  List<String> paragrafe,
  String termen,
) {
  final t = termen.trim();
  if (t.isEmpty) return (articol: null, paragrafe: paragrafe);
  final m = RegExp(
    r'^(?:art(?:icolul|\.)?\s*)?(\d+(?:\^\d+)?)$',
    caseSensitive: false,
  ).firstMatch(t);
  if (m != null) {
    final nr = m.group(1)!;
    final i = paragrafe.indexWhere((p) {
      final a = _reArticol.firstMatch(p);
      return a != null && a.group(1) == nr && p.length < 200;
    });
    if (i < 0) return (articol: nr, paragrafe: const []);
    var j = i + 1;
    while (j < paragrafe.length &&
        !esteTitluArticol(paragrafe[j]) &&
        !esteTitluStructura(paragrafe[j])) {
      j++;
    }
    return (articol: nr, paragrafe: paragrafe.sublist(i, j));
  }
  final baza = fataDiacritice(t.toLowerCase());
  return (
    articol: null,
    paragrafe: paragrafe.where((p) => fataDiacritice(p.toLowerCase()).contains(baza)).toList(),
  );
}
