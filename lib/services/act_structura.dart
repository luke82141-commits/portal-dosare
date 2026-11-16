import 'legislatie_service.dart' show fataDiacritice;

/// Textul unui act, împărțit în blocuri ca să fie afișat ca o lege, nu ca
/// un text compact: titluri și capitole, articole cu denumirea lor,
/// alineate, litere și note de modificare.
enum TipBloc { structura, articol, alineat, litera, nota, text }

class BlocAct {
  final TipBloc tip;

  /// „TITLUL I”, „Art. 1”, „(2)”, „a)”. Gol la text și note.
  final String eticheta;

  /// Denumirea: „Despre legea civilă”, „Izvoarele dreptului civil”.
  final String titlu;

  /// Corpul blocului (la alineate, litere, text, note).
  final String text;

  /// Numărul articolului din care face parte blocul („1”, „5^1”); la
  /// blocurile de structură e articolul următor sau null.
  final String? articol;

  /// La notele „(la 30-06-2021, ... a fost modificat de ...)” din forma
  /// consolidată: ce s-a schimbat, când și prin ce act.
  final Modificare? modificare;

  /// Textul a fost schimbat față de forma inițială (albastru pe portal).
  final bool actualizat;

  /// Trimiteri către alte acte, în [text]: pot fi deschise în aplicație.
  final List<Legatura> legaturi;

  const BlocAct(
    this.tip, {
    this.eticheta = '',
    this.titlu = '',
    this.text = '',
    this.articol,
    this.modificare,
    this.actualizat = false,
    this.legaturi = const [],
  });

  /// „Abrogat.”, „Abrogată.”: elementul nu mai e în vigoare.
  bool get abrogat => RegExp(
    r'^\(?abrogat[ăa]?[.;]?\)?$',
    caseSensitive: false,
  ).hasMatch(text.trim());

  /// Tot textul blocului, pentru căutare și copiere.
  String get textComplet =>
      [eticheta, titlu, text].where((s) => s.isNotEmpty).join(' ');
}

enum TipModificare { modificat, completat, abrogat, altul }

/// „(la 30-06-2021, Alineatul (2) din Articolul 10 a fost abrogat de
/// Punctul 5, Articolul III din OUG nr. 80/2021)”.
class Modificare {
  final DateTime? data;
  final TipModificare tip;

  /// Cum scrie portalul: „modificat”, „completat”, „abrogat”, „înlocuită”.
  final String verb;

  /// „Alineatul (2) din Articolul 10”.
  final String element;

  /// Actul care a făcut schimbarea, așa cum e scris pe portal.
  final String act;

  /// Id-ul actului de pe legislatie.just.ro, dacă e dat.
  final String? idAct;

  const Modificare({
    this.data,
    required this.tip,
    this.verb = '',
    required this.element,
    required this.act,
    this.idAct,
  });
}

/// O trimitere din text către alt act: caracterele [start, end) din text.
class Legatura {
  final int start;
  final int end;
  final String idAct;
  const Legatura(this.start, this.end, this.idAct);
}

final _reStructura = RegExp(
  r'^(PARTEA|CARTEA|TITLUL|CAPITOLUL|SEC[ȚŢT]IUNEA|SUBSEC[ȚŢT]IUNEA|'
  r'Partea|Cartea|Titlul|Capitolul|Sec[țţt]iunea|Subsec[țţt]iunea)'
  r'\s+([IVXLCDM]+|\d+|PRELIMINAR[AĂ]?|preliminar[aă]?|a\s+\d+-a|[ÎîIi]nt[âa]i|UNIC[AĂ]?|unic[aă]?)'
  r'(\^\d+)?(?![\wăâîșțşţ])\s*[-–.:]?\s*(.*)$',
);
final _reAnexa = RegExp(r'^(ANEXA|Anexa)(\s+(?:nr\.\s*)?\d+)?\s*[-–.:]?\s*$');

final _reArticol = RegExp(
  r'^(?:Art\.|ART\.|Articolul|ARTICOLUL|Art)\s*(\d{1,3}(?:\.\d{3})+(?!\d)(?:\s*\^\s*\d+)?|\d+(?:\s*\^\s*\d+)?)\s*[.:]?\s*(?:[-–—]\s*)?(.*)$',
);
final _reAlineat = RegExp(r'^\((\d+(?:\^\d+)?)\)\s*(.*)$');
final _reLitera = RegExp(
  r'^([a-z]{1,2}(?:\^\d+)?\)|\d{1,3}(?:\^\d+)?\.)\s+(.+)$',
);
final _reNota = RegExp(
  r'^(\(la \d{1,2}[-.]\d{1,2}[-.]\d{4}|Not[aă]\b|NOT[AĂ]\b|\(\*|\*\)|Text actualizat|Reglementări)',
);

/// „2.500” → „2500”, „5 ^ 1” → „5^1”: codurile scriu miile cu punct.
String nrArticol(String s) => s
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAllMapped(
      RegExp(r'^(\d{1,3})((?:\.\d{3})+)'),
      (m) => m[1]! + m[2]!.replaceAll('.', ''),
    );

String _nrArticol(String s) => nrArticol(s);

/// Unele texte vin fără rânduri noi; le despărțim înainte de articole,
/// alineate și titluri, ca să poată fi structurate.
String spargeRanduri(String text) {
  final t = text.replaceAll('\r\n', '\n');
  final randuri = '\n'.allMatches(t).length;
  if (t.length < 400 || randuri * 600 > t.length) return t;
  return t
      .replaceAllMapped(
        RegExp(r'\s+(Art\.\s*\d+(?:\^\d+)?\s*\.?\s*[-–])'),
        (m) => '\n${m[1]}',
      )
      .replaceAllMapped(RegExp(r'\s+(Articolul\s+\d+)'), (m) => '\n${m[1]}')
      .replaceAllMapped(RegExp(r'\s+(\(\d+(?:\^\d+)?\)\s)'), (m) => '\n${m[1]}')
      .replaceAllMapped(
        RegExp(
          r'\s+((?:TITLUL|CAPITOLUL|SECȚIUNEA|SECŢIUNEA|CARTEA|PARTEA)\s+[IVXLCDM\d]+)',
        ),
        (m) => '\n${m[1]}',
      );
}

final _reMarcajPortal = RegExp(r'\n[\t \u00a0]*\+[\t \u00a0]*\n');
final _reEticheta = RegExp(
  r'^(\(\d+(?:\^\d+)?\)|[a-z]{1,2}(?:\^\d+)?\)|\d{1,3}(?:\^\d+)?\.)[\s\u00a0]+',
);

/// Textul integral de pe legislatie.just.ro (verificat pe 15.11.2026): fără
/// HTML, cu blocuri despărțite de „\n\t\t\t\t + \n\t\t\t  ”. Într-un bloc,
/// spațiile multiple despart părțile: „Articolul 3     Aplicarea generală a
/// Codului civil      (1) Dispozițiile ...   ...        (2) Sunt ...   ...”.
/// După fiecare paragraf vine „ ... ”. Notele au „Notă” și chenare „────”.
/// Întoarce rândurile curate, câte unul pe articol, denumire, alineat, literă.
List<String>? randuriPortal(String text) {
  if (!_reMarcajPortal.hasMatch(text)) return null;
  final r = <String>[];
  String curat(String x) => x.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
  final spatii = RegExp(r'[ \t\u00a0]{2,}');

  void corp(String c) {
    // Paragrafele se termină cu „...”; chenarele notelor sunt linii.
    final bucati = c
        .split(RegExp(r'[\s\u00a0]+\.\.\.(?=[\s\u00a0]|$)|[─━]{3,}|-{6,}'))
        .expand(
          // Etichetele de alineat, punct („I.”, „1.”) și literă vin după 2+
          // spații sau după „:” / „;”.
          (b) => b.split(
            RegExp(
              r'(?:[ \t\u00a0]{2,}|(?<=[:;])[ \t\u00a0]+)'
              r'(?=(?:\(\d+(?:\^\d+)?\)|[a-z]{1,2}(?:\^\d+)?\)|[IVX]{1,4}\.|\d{1,3}(?:\^\d+)?\.)[\s\u00a0])',
            ),
          ),
        );
    for (final b in bucati) {
      final t = curat(b);
      if (t.isEmpty || t == '...' || t == '…') continue;
      r.add(t);
    }
  }

  for (final bloc in text.split(_reMarcajPortal)) {
    final b = bloc.replaceAll('\r', '').trim();
    if (b.isEmpty) continue;
    // Fără spații multiple nu putem despărți după ele; ghicim după majuscule.
    if (!spatii.hasMatch(b)) {
      r.addAll(
        _preproceseaza(b).split('\n').map(curat).where((x) => x.isNotEmpty),
      );
      continue;
    }
    final art = RegExp(
      r'^(Articolul|ARTICOLUL|Art\.)[\s\u00a0]+(\d{1,3}(?:\.\d{3})+(?!\d)(?:[\s\u00a0]*\^[\s\u00a0]*\d+)?|\d+(?:[\s\u00a0]*\^[\s\u00a0]*\d+)?)[\s\u00a0]*',
    ).firstMatch(b);
    if (art != null) {
      r.add(
        'Articolul ${nrArticol(art[2]!.replaceAll(RegExp(r'[\s\u00a0]'), ''))}',
      );
      var rest = b.substring(art.end);
      // Denumirea: până la primele 2+ spații, dacă nu e deja textul.
      final sep = spatii.firstMatch(rest);
      if (sep != null && !_reEticheta.hasMatch(rest)) {
        final denumire = curat(rest.substring(0, sep.start));
        if (denumire.isNotEmpty &&
            denumire.length <= 200 &&
            !RegExp(r'[.;:,]$').hasMatch(denumire)) {
          r.add(denumire);
          rest = rest.substring(sep.end);
        }
      }
      corp(rest);
      continue;
    }
    final str = _reStructura.firstMatch(curat(b.split(spatii).first));
    if (str != null || RegExp(r'^(ANEXA|Anexa)\b').hasMatch(b)) {
      // „Titlul PRELIMINAR   Despre legea civilă”: eticheta, apoi denumirea.
      final parti = b.split(spatii).where((x) => x.trim().isNotEmpty).toList();
      if (parti.isNotEmpty) r.add(curat(parti.first));
      if (parti.length > 1)
        r.add(curat(parti[1]).replaceAll(RegExp(r'\*+\)$'), ''));
      if (parti.length > 2) corp(parti.skip(2).join('  '));
      continue;
    }
    corp(b);
  }
  return r;
}

/// Textul de pe legislatie.just.ro vine cu „+” pe rânduri separate (butoanele
/// de pliere din pagină) și cu denumirea articolului, alineatele și literele
/// lipite pe același rând: „Articolul 5 Aplicarea legii penale mai favorabile
/// (1) În cazul în care...”. Le despărțim, oricâte rânduri noi ar avea textul.
String _preproceseaza(String text) {
  final faraPlus = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*\+(\s+|$)'), ''))
      // După fiecare paragraf portalul pune „...” (marcajul pentru istoric).
      .map(
        (l) => l.replaceAllMapped(
          RegExp(r'([.;:!?])[ \t\u00a0]*(?:\.\.\.|…)(?=\s|$)'),
          (m) => m[1]!,
        ),
      )
      .map((l) => l.replaceFirst(RegExp(r'^\s*(?:\.\.\.|…)\s*$'), ''))
      .where((l) => l.trim().isNotEmpty)
      .join('\n');
  final dupaArticole = faraPlus.replaceAllMapped(
    RegExp(r'[ \t\u00a0]+(Articolul\s+\d+(?:\s*\^\s*\d+)?(?![\d^]))'),
    (m) => '\n${m[1]}',
  );
  final dupaAlineate = dupaArticole.replaceAllMapped(
    RegExp(r'(\S+)[ \t\u00a0]+(\(\d+(?:\^\d+)?\)[ \u00a0]+[A-ZĂÂÎȘŞȚŢ])'),
    (m) {
      final inainte = fataDiacritice(m[1]!.toLowerCase());
      final referinta = RegExp(
        r'^(alin\.?|alineatul|alineatele|art\.?|si|sau|la|nr\.?)$',
      );
      if (referinta.hasMatch(inainte)) return m[0]!;
      return '${m[1]}\n${m[2]}';
    },
  );
  return dupaAlineate.replaceAllMapped(
    RegExp(
      r'([:;])[ \t\u00a0]+([a-z]{1,2}\)[ \u00a0]|[IVX]{1,4}\.[ \u00a0]|\d{1,3}\.[ \u00a0])',
    ),
    (m) => '${m[1]}\n${m[2]}',
  );
}

const _legaturi = {
  'si',
  'sau',
  'de',
  'la',
  'in',
  'din',
  'cu',
  'pe',
  'a',
  'al',
  'ale',
  'ai',
  'pentru',
  'privind',
  'prin',
  'catre',
  'fata',
  'asupra',
  'intre',
  'sub',
  'dupa',
  'fara',
};
const _verbe = {
  'se',
  'este',
  'sunt',
  'are',
  'au',
  'va',
  'vor',
  'poate',
  'pot',
  'intra',
  'trebuie',
  'constituie',
  'reprezinta',
  'cuprinde',
  'aproba',
  'abroga',
  'modifica',
  'face',
  'fi',
};

/// Desparte „Aplicarea legii penale de dezincriminare Legea penală nu se
/// aplică...” în denumire și text: denumirea se termină înaintea primului
/// cuvânt cu majusculă care începe o frază. Null când nu pare să aibă denumire.
({String titlu, String corp})? _despartDenumire(String rest) {
  final cuvinte = rest.split(' ');
  for (var k = 1; k < cuvinte.length && k <= 14; k++) {
    final w = cuvinte[k];
    if (w.isEmpty || !RegExp(r'^[A-ZĂÂÎȘŞȚŢ][a-zăâîșşțţ]').hasMatch(w))
      continue;
    final prec = cuvinte[k - 1];
    if (RegExp(r'[,.;:]$').hasMatch(prec)) continue;
    // „Monitorul Oficial”, „Codul civil”: substantive proprii în denumire.
    if (RegExp(r'^[A-ZĂÂÎȘŞȚŢ]').hasMatch(prec) && k > 1) continue;
    final titlu = cuvinte.sublist(0, k);
    final norm = titlu.map((x) => fataDiacritice(x.toLowerCase())).toList();
    if (_legaturi.contains(norm.last)) continue;
    if (norm.any(_verbe.contains)) return null;
    if (titlu.any((x) => RegExp(r'\d').hasMatch(x))) return null;
    final corp = cuvinte.sublist(k).join(' ');
    if (corp.length < 15) return null;
    return (titlu: titlu.join(' '), corp: corp);
  }
  return null;
}

bool _eDenumire(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 140) return false;
  if (t.endsWith('.') || t.endsWith(';') || t.endsWith(':') || t.endsWith(','))
    return false;
  if (_reArticol.hasMatch(t) ||
      _reAlineat.hasMatch(t) ||
      _reStructura.hasMatch(t)) {
    return false;
  }
  if (_reLitera.hasMatch(t) || _reNota.hasMatch(t)) return false;
  return true;
}

/// Transformă textul actului în blocuri.
List<BlocAct> structureazaAct(String text) {
  final linii =
      (randuriPortal(text) ?? _preproceseaza(spargeRanduri(text)).split('\n'))
          .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
          .where((l) => l.isNotEmpty)
          .toList();
  final blocuri = <BlocAct>[];
  String? articol;
  var i = 0;
  while (i < linii.length) {
    final l = linii[i];

    final s = _reStructura.firstMatch(l);
    final anexa = _reAnexa.firstMatch(l);
    final restStructura = (s?[4] ?? '').trim();
    if (anexa != null ||
        (s != null &&
            restStructura.length <= 140 &&
            !restStructura.endsWith('.'))) {
      final eticheta = anexa != null
          ? l.replaceAll(RegExp(r'\s*[-–.:]\s*$'), '')
          : '${s![1]} ${s[2]}${s[3] ?? ''}';
      var titlu = anexa != null ? '' : restStructura;
      // Denumirea e de obicei pe rândul următor („TITLUL I” / „Despre legea civilă”).
      if (titlu.isEmpty && i + 1 < linii.length && _eDenumire(linii[i + 1])) {
        titlu = linii[i + 1];
        i++;
      }
      blocuri.add(
        BlocAct(
          TipBloc.structura,
          eticheta: eticheta.toUpperCase(),
          titlu: titlu,
        ),
      );
      i++;
      continue;
    }

    final a = _reArticol.firstMatch(l);
    if (a != null &&
        (l.length < 400 ||
            RegExp(r'^(Art\.\s*\d+(?:\.\d{3})*\s*\.?\s*[-–]|Articolul\s+\d)')
                .hasMatch(l))) {
      articol = _nrArticol(a[1]!);
      var rest = (a[2] ?? '').trim();
      var titlu = '';
      String corp = '';
      if (rest.isEmpty) {
        if (i + 1 < linii.length && _eDenumire(linii[i + 1])) {
          titlu = linii[i + 1];
          i++;
        }
      } else if (_eDenumire(rest)) {
        titlu = rest;
      } else if (_despartDenumire(rest) case final d?) {
        titlu = d.titlu;
        corp = d.corp;
      } else {
        corp = rest;
      }
      blocuri.add(
        BlocAct(
          TipBloc.articol,
          eticheta: 'Art. $articol',
          titlu: titlu,
          articol: articol,
        ),
      );
      if (corp.isNotEmpty) blocuri.addAll(_blocuriCorp(corp, articol));
      i++;
      continue;
    }

    blocuri.addAll(_blocuriCorp(l, articol));
    i++;
  }
  return blocuri;
}

List<BlocAct> _blocuriCorp(String l, String? articol) {
  final al = _reAlineat.firstMatch(l);
  if (al != null) {
    return [
      BlocAct(
        TipBloc.alineat,
        eticheta: '(${al[1]})',
        text: al[2]!.trim(),
        articol: articol,
      ),
    ];
  }
  if (_reNota.hasMatch(l))
    return [BlocAct(TipBloc.nota, text: l, articol: articol)];
  // Punctele cu cifre romane („I. cu amendă de la 500 lei la 1.000 lei:”)
  // grupează literele de sub ele, ca un alineat.
  final roman = RegExp(r'^([IVX]{1,4}\.)\s+(.+)$').firstMatch(l);
  if (roman != null && articol != null) {
    return [
      BlocAct(
        TipBloc.alineat,
        eticheta: roman[1]!,
        text: roman[2]!.trim(),
        articol: articol,
      ),
    ];
  }
  final lit = _reLitera.firstMatch(l);
  if (lit != null && articol != null) {
    return [
      BlocAct(
        TipBloc.litera,
        eticheta: lit[1]!,
        text: lit[2]!.trim(),
        articol: articol,
      ),
    ];
  }
  return [BlocAct(TipBloc.text, text: l, articol: articol)];
}

/// Indicele blocului cu titlul articolului [nr] („712”, „5^1”, „art. 712”).
int? indiceArticol(List<BlocAct> blocuri, String nr) {
  final m = RegExp(
    r'(\d{1,3}(?:\.\d{3})+(?!\d)(?:\s*\^\s*\d+)?|\d+(?:\s*\^\s*\d+)?)',
  ).firstMatch(nr);
  if (m == null) return null;
  final cautat = _nrArticol(m[1]!);
  final i = blocuri.indexWhere(
    (b) => b.tip == TipBloc.articol && b.articol == cautat,
  );
  return i < 0 ? null : i;
}

/// Blocurile unui articol întreg, de la titlu până la următorul articol sau
/// titlu de structură.
List<BlocAct> blocuriArticol(List<BlocAct> blocuri, int start) {
  var j = start + 1;
  while (j < blocuri.length &&
      blocuri[j].tip != TipBloc.articol &&
      blocuri[j].tip != TipBloc.structura) {
    j++;
  }
  return blocuri.sublist(start, j);
}

/// Textul unui articol, gata de copiat sau trimis, cu sursa la final.
String textArticol(List<BlocAct> blocuri, int start, String sursa) {
  final b = blocuriArticol(blocuri, start);
  final antet = b.first;
  final linii = [
    [antet.eticheta, if (antet.titlu.isNotEmpty) antet.titlu].join(' - '),
    for (final x in b.skip(1))
      if (x.tip != TipBloc.nota)
        [x.eticheta, x.text].where((s) => s.isNotEmpty).join(' '),
  ];
  return '${linii.join('\n')}\n\n(${antet.eticheta.toLowerCase()} din $sursa)';
}

/// Indicii blocurilor care conțin [termen] (fără diacritice și majuscule).
List<int> potriviri(List<BlocAct> blocuri, String termen) {
  final t = fataDiacritice(termen.trim().toLowerCase());
  if (t.length < 2) return const [];
  return [
    for (final (i, b) in blocuri.indexed)
      if (fataDiacritice(b.textComplet.toLowerCase()).contains(t)) i,
  ];
}

/// Pozițiile lui [termen] în [text], pentru evidențiere.
List<(int, int)> pozitii(String text, String termen) {
  final t = fataDiacritice(termen.trim().toLowerCase());
  if (t.isEmpty) return const [];
  final baza = fataDiacritice(text.toLowerCase());
  if (baza.length != text.length) return const [];
  final r = <(int, int)>[];
  var start = 0;
  while (true) {
    final i = baza.indexOf(t, start);
    if (i < 0) break;
    r.add((i, i + t.length));
    start = i + t.length;
  }
  return r;
}

/// Cuprinsul: titlurile de structură și articolele, cu nivelul de indentare.
class IntrareCuprins {
  final int indice;
  final int nivel;
  final String text;
  final bool eArticol;

  const IntrareCuprins(this.indice, this.nivel, this.text, this.eArticol);
}

int _nivelStructura(String eticheta) {
  final e = fataDiacritice(eticheta.toUpperCase());
  if (e.startsWith('PARTEA')) return 0;
  if (e.startsWith('CARTEA')) return 0;
  if (e.startsWith('TITLUL')) return 1;
  if (e.startsWith('CAPITOLUL')) return 2;
  if (e.startsWith('SUBSECTIUNEA')) return 4;
  if (e.startsWith('SECTIUNEA')) return 3;
  return 1;
}

List<IntrareCuprins> cuprins(List<BlocAct> blocuri, {bool cuArticole = true}) {
  final r = <IntrareCuprins>[];
  var nivel = 0;
  for (final (i, b) in blocuri.indexed) {
    if (b.tip == TipBloc.structura) {
      nivel = _nivelStructura(b.eticheta);
      r.add(
        IntrareCuprins(
          i,
          nivel,
          [b.eticheta, b.titlu].where((s) => s.isNotEmpty).join(' · '),
          false,
        ),
      );
    } else if (cuArticole && b.tip == TipBloc.articol) {
      r.add(
        IntrareCuprins(
          i,
          nivel + 1,
          [b.eticheta, b.titlu].where((s) => s.isNotEmpty).join(' · '),
          true,
        ),
      );
    }
  }
  return r;
}

/// Locul din act unde apare termenul căutat, pentru cardul de rezultat:
/// articolul („Art. 930 · Uzucapiunea extratabulară”) și o bucată curată
/// din paragraf, tăiată la margini de cuvânt.
class FragmentAct {
  final String? articol;

  /// Numărul articolului („930”), ca să deschidem actul direct acolo.
  final String? nrArticol;
  final String text;
  final bool inceputTaiat;
  final bool sfarsitTaiat;

  const FragmentAct(
    this.articol,
    this.text, {
    this.nrArticol,
    this.inceputTaiat = false,
    this.sfarsitTaiat = false,
  });
}

final _cacheFragmente = <(int, String), FragmentAct?>{};

/// Ca [_fragment], dar ținut minte: cardurile se redesenează des, iar
/// textele mari (Codul civil) au câțiva MB.
FragmentAct? fragmentDinAct(String textAct, String termen, {int latime = 150}) {
  final cheie = (identityHashCode(textAct) ^ textAct.length, termen);
  if (_cacheFragmente.containsKey(cheie)) return _cacheFragmente[cheie];
  if (_cacheFragmente.length > 200) _cacheFragmente.clear();
  return _cacheFragmente[cheie] = _fragment(textAct, termen, latime);
}

FragmentAct? _fragment(String textAct, String termen, int latime) {
  final t = fataDiacritice(termen.trim().toLowerCase());
  if (t.length < 3 || textAct.isEmpty) return null;
  final linii = spargeRanduri(textAct).split('\n');
  for (var i = 0; i < linii.length; i++) {
    final linie = linii[i].replaceAll(RegExp(r'\s+'), ' ').trim();
    final baza = fataDiacritice(linie.toLowerCase());
    final poz = baza.indexOf(t);
    if (poz < 0 || baza.length != linie.length) continue;

    // Articolul în care se află: căutăm înapoi titlul lui.
    String? articol;
    String? nrArticol;
    for (var k = i; k >= 0 && k > i - 60; k--) {
      final l = linii[k].trim();
      if (_reArticol.hasMatch(l) && l.length < 400) {
        final bucata = structureazaAct(
          linii.sublist(k, (k + 2).clamp(0, linii.length)).join('\n'),
        );
        final a = bucata.where((b) => b.tip == TipBloc.articol).firstOrNull;
        if (a != null) {
          articol = [a.eticheta, if (a.titlu.isNotEmpty) a.titlu].join(' · ');
          nrArticol = a.articol;
        }
        break;
      }
    }

    // Termenul e chiar în titlul articolului: arătăm primul rând din corp.
    var corp = linie;
    var pozCorp = poz;
    var inlocuit = false;
    if (articol != null && _reArticol.hasMatch(linie) && i + 1 < linii.length) {
      final urm = linii[i + 1].replaceAll(RegExp(r'\s+'), ' ').trim();
      if (urm.isNotEmpty && !_reArticol.hasMatch(urm)) {
        corp = urm;
        pozCorp = 0;
        inlocuit = true;
      }
    }
    final linieCorp = corp;
    var start = 0;
    final m = RegExp(
      r'^(?:Art\.\s*\d+(?:\^\d+)?\s*\.?\s*[-–]\s*|\(\d+(?:\^\d+)?\)\s*|[a-z]\)\s*)',
    ).firstMatch(linieCorp);
    if (m != null && (m.end <= pozCorp || inlocuit)) start = m.end;
    corp = linieCorp.substring(start);
    final p = (pozCorp - start).clamp(0, corp.length).toInt();
    final lungimeT = inlocuit ? 0 : t.length;

    var a = (p - latime ~/ 3).clamp(0, corp.length);
    var b = (p + lungimeT + latime).clamp(0, corp.length);
    if (a > 0) {
      final s = corp.indexOf(' ', a);
      a = s < 0 || s > p ? a : s + 1;
    }
    if (b < corp.length) {
      final s = corp.lastIndexOf(' ', b);
      b = s <= p + lungimeT ? b : s;
    }
    return FragmentAct(
      articol,
      corp.substring(a, b).trim(),
      nrArticol: nrArticol,
      inceputTaiat: a > 0,
      sfarsitTaiat: b < corp.length,
    );
  }
  return null;
}
