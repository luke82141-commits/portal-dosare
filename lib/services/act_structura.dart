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

  const BlocAct(this.tip, {this.eticheta = '', this.titlu = '', this.text = '', this.articol});

  /// Tot textul blocului, pentru căutare și copiere.
  String get textComplet => [eticheta, titlu, text].where((s) => s.isNotEmpty).join(' ');
}

final _reStructura = RegExp(
  r'^(PARTEA|CARTEA|TITLUL|CAPITOLUL|SEC[ȚŢT]IUNEA|SUBSEC[ȚŢT]IUNEA|'
  r'Partea|Cartea|Titlul|Capitolul|Sec[țţt]iunea|Subsec[țţt]iunea)'
  r'\s+([IVXLCDM]+|\d+|PRELIMINAR[AĂ]?|preliminar[aă]?|a\s+\d+-a|[ÎîIi]nt[âa]i|UNIC[AĂ]?|unic[aă]?)'
  r'(\^\d+)?(?![\wăâîșțşţ])\s*[-–.:]?\s*(.*)$',
);
final _reAnexa = RegExp(r'^(ANEXA|Anexa)(\s+(?:nr\.\s*)?\d+)?\s*[-–.:]?\s*$');

final _reArticol = RegExp(
  r'^(?:Art\.|ART\.|Articolul|ARTICOLUL|Art)\s*(\d+(?:\s*\^\s*\d+)?)\s*[.:]?\s*(?:[-–—]\s*)?(.*)$',
);
final _reAlineat = RegExp(r'^\((\d+(?:\^\d+)?)\)\s*(.*)$');
final _reLitera = RegExp(r'^([a-z]{1,2}(?:\^\d+)?\)|\d{1,3}(?:\^\d+)?\.)\s+(.+)$');
final _reNota = RegExp(
  r'^(\(la \d{1,2}[-.]\d{1,2}[-.]\d{4}|Not[aă]\b|NOT[AĂ]\b|\(\*|\*\)|Text actualizat|Reglementări)',
);

String _nrArticol(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// Unele texte vin fără rânduri noi; le despărțim înainte de articole,
/// alineate și titluri, ca să poată fi structurate.
String spargeRanduri(String text) {
  final t = text.replaceAll('\r\n', '\n');
  final randuri = '\n'.allMatches(t).length;
  if (t.length < 400 || randuri * 600 > t.length) return t;
  return t
      .replaceAllMapped(RegExp(r'\s+(Art\.\s*\d+(?:\^\d+)?\s*\.?\s*[-–])'), (m) => '\n${m[1]}')
      .replaceAllMapped(RegExp(r'\s+(Articolul\s+\d+)'), (m) => '\n${m[1]}')
      .replaceAllMapped(RegExp(r'\s+(\(\d+(?:\^\d+)?\)\s)'), (m) => '\n${m[1]}')
      .replaceAllMapped(
        RegExp(r'\s+((?:TITLUL|CAPITOLUL|SECȚIUNEA|SECŢIUNEA|CARTEA|PARTEA)\s+[IVXLCDM\d]+)'),
        (m) => '\n${m[1]}',
      );
}

bool _eDenumire(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 140) return false;
  if (t.endsWith('.') || t.endsWith(';') || t.endsWith(':') || t.endsWith(',')) return false;
  if (_reArticol.hasMatch(t) || _reAlineat.hasMatch(t) || _reStructura.hasMatch(t)) {
    return false;
  }
  if (_reLitera.hasMatch(t) || _reNota.hasMatch(t)) return false;
  return true;
}

/// Transformă textul actului în blocuri.
List<BlocAct> structureazaAct(String text) {
  final linii = spargeRanduri(text)
      .split('\n')
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
        (s != null && restStructura.length <= 140 && !restStructura.endsWith('.'))) {
      final eticheta = anexa != null
          ? l.replaceAll(RegExp(r'\s*[-–.:]\s*$'), '')
          : '${s![1]} ${s[2]}${s[3] ?? ''}';
      var titlu = anexa != null ? '' : restStructura;
      // Denumirea e de obicei pe rândul următor („TITLUL I” / „Despre legea civilă”).
      if (titlu.isEmpty && i + 1 < linii.length && _eDenumire(linii[i + 1])) {
        titlu = linii[i + 1];
        i++;
      }
      blocuri.add(BlocAct(TipBloc.structura, eticheta: eticheta.toUpperCase(), titlu: titlu));
      i++;
      continue;
    }

    final a = _reArticol.firstMatch(l);
    if (a != null && (l.length < 400 || RegExp(r'^Art\.\s*\d+\s*\.?\s*[-–]').hasMatch(l))) {
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
      } else {
        corp = rest;
      }
      blocuri.add(
        BlocAct(TipBloc.articol, eticheta: 'Art. $articol', titlu: titlu, articol: articol),
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
      BlocAct(TipBloc.alineat, eticheta: '(${al[1]})', text: al[2]!.trim(), articol: articol),
    ];
  }
  if (_reNota.hasMatch(l)) return [BlocAct(TipBloc.nota, text: l, articol: articol)];
  final lit = _reLitera.firstMatch(l);
  if (lit != null && articol != null) {
    return [BlocAct(TipBloc.litera, eticheta: lit[1]!, text: lit[2]!.trim(), articol: articol)];
  }
  return [BlocAct(TipBloc.text, text: l, articol: articol)];
}

/// Indicele blocului cu titlul articolului [nr] („712”, „5^1”, „art. 712”).
int? indiceArticol(List<BlocAct> blocuri, String nr) {
  final m = RegExp(r'(\d+(?:\s*\^\s*\d+)?)').firstMatch(nr);
  if (m == null) return null;
  final cautat = _nrArticol(m[1]!);
  final i = blocuri.indexWhere((b) => b.tip == TipBloc.articol && b.articol == cautat);
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
      if (x.tip != TipBloc.nota) [x.eticheta, x.text].where((s) => s.isNotEmpty).join(' '),
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
        final bucata = structureazaAct(linii.sublist(k, (k + 2).clamp(0, linii.length)).join('\n'));
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
    final m = RegExp(r'^(?:Art\.\s*\d+(?:\^\d+)?\s*\.?\s*[-–]\s*|\(\d+(?:\^\d+)?\)\s*|[a-z]\)\s*)')
        .firstMatch(linieCorp);
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
