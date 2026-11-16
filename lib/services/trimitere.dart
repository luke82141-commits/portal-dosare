import 'act_structura.dart';

/// O trimitere din text către o prevedere: „art. 6 alin. (2) din OG 99/2000”.
class Trimitere {
  /// „6”, „30”, „III”, „5^1”.
  final String articol;
  final String? alineat;
  final String? litera;
  final String? punct;

  const Trimitere(this.articol, {this.alineat, this.litera, this.punct});

  /// „Art. 6 alin. (2)”.
  String get eticheta => [
    'Art. $articol',
    if (alineat != null) 'alin. ($alineat)',
    if (punct != null) 'pct. $punct',
    if (litera != null) 'lit. $litera)',
  ].join(' ');

  @override
  String toString() => eticheta;
}

const _nr = r'(\d+(?:\s*\^\s*\d+)?|[IVXLC]+\b)';

final _reArt = RegExp(
  r'\b(?:art\.|articol(?:ul|ului|ele|elor)?)\s*' + _nr,
  caseSensitive: false,
);
final _rePunctArt = RegExp(
  r'\bpunctul\s+(\d+(?:\^\d+)?)\.?\s*,\s*articolul\s+' + _nr,
  caseSensitive: false,
);
final _reAlin = RegExp(r'^\s*,?\s*alin\.\s*\((\d+(?:\s*\^\s*\d+)?)\)');
final _reLit = RegExp(r'^\s*,?\s*lit\.\s*([a-z]{1,2}(?:\^\d+)?)\)');
final _rePct = RegExp(r'^\s*,?\s*pct\.\s*(\d+(?:\^\d+)?)');

String _curat(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// Ce prevedere arată un link: din textul lui („art. 2 pct. 39 din Legea
/// nr. 273/2006”) sau, când linkul e doar actul („Legea nr. 10/1995”), din
/// cuvintele de dinaintea lui („art. 17 din ”). Null dacă trimiterea e la tot
/// actul.
Trimitere? trimitereDin(String textLink, [String inainte = '']) {
  final pa = _rePunctArt.firstMatch(textLink);
  if (pa != null) {
    return Trimitere(_curat(pa.group(2)!), punct: _curat(pa.group(1)!));
  }
  // Linkul începe cu numărul („3 din Hotărârea …”), iar „art.” e înainte.
  final s = inainte + textLink;
  final startLink = inainte.length;
  RegExpMatch? ales;
  for (final m in _reArt.allMatches(s)) {
    if (m.start >= startLink) {
      ales ??= m;
    } else if (m.end >= startLink - 1 ||
        // „art. 17 alin. (2) din ” chiar înaintea linkului.
        RegExp(
          r'^(?:\s*,?\s*(?:alin\.\s*\([^)]*\)|lit\.\s*[a-z^\d]+\)|pct\.\s*[\d^]+))*\s*(?:din|al|a|la)?\s*$',
          caseSensitive: false,
        ).hasMatch(s.substring(m.end, startLink))) {
      ales = m;
    }
  }
  if (ales == null) {
    // „alin. (1)” singur: alineatul din același articol, necunoscut aici.
    return null;
  }
  final articol = _curat(ales.group(1)!).toUpperCase();
  String? alineat, litera, punct;
  var rest = s.substring(ales.end);
  for (var i = 0; i < 4; i++) {
    final a = _reAlin.firstMatch(rest);
    if (a != null && alineat == null) {
      alineat = _curat(a.group(1)!);
      rest = rest.substring(a.end);
      continue;
    }
    final p = _rePct.firstMatch(rest);
    if (p != null && punct == null) {
      punct = _curat(p.group(1)!);
      rest = rest.substring(p.end);
      continue;
    }
    final l = _reLit.firstMatch(rest);
    if (l != null && litera == null) {
      litera = l.group(1);
      rest = rest.substring(l.end);
      continue;
    }
    break;
  }
  return Trimitere(articol, alineat: alineat, litera: litera, punct: punct);
}

bool _eArticolul(BlocAct b, String articol) {
  final a = b.articol;
  if (a != null) return _curat(a).toUpperCase() == articol;
  if (b.tip != TipBloc.articol) return false;
  final m = RegExp(
    r'^(?:Art\.|Articolul)\s*(\S+)',
    caseSensitive: false,
  ).firstMatch(b.eticheta);
  return m != null &&
      _curat(m.group(1)!).replaceAll(RegExp(r'[.:\-–]+$'), '').toUpperCase() ==
          articol;
}

/// Blocurile prevederii: articolul întreg sau doar alineatul / litera /
/// punctul cerut, cu notele lor. Gol dacă articolul nu e în act.
List<BlocAct> blocuriTrimitere(List<BlocAct> blocuri, Trimitere t) {
  final start = blocuri.indexWhere(
    (b) => b.tip == TipBloc.articol && _eArticolul(b, t.articol),
  );
  if (start < 0) return const [];
  var end = start + 1;
  while (end < blocuri.length &&
      blocuri[end].tip != TipBloc.articol &&
      blocuri[end].tip != TipBloc.structura) {
    end++;
  }
  final art = blocuri.sublist(start, end);
  var parte = art;

  int gaseste(List<BlocAct> l, bool Function(BlocAct) f) => l.indexWhere(f);

  if (t.alineat != null) {
    final i = gaseste(
      parte,
      (b) => b.tip == TipBloc.alineat && _curat(b.eticheta) == '(${t.alineat})',
    );
    if (i >= 0) {
      var j = i + 1;
      while (j < parte.length && parte[j].tip != TipBloc.alineat) {
        j++;
      }
      parte = parte.sublist(i, j);
    }
  }
  final sub = t.litera != null
      ? '${t.litera})'
      : (t.punct != null ? '${t.punct}.' : null);
  if (sub != null) {
    final i = gaseste(
      parte,
      (b) =>
          b.tip != TipBloc.nota &&
          (_curat(b.eticheta) == sub ||
              (t.punct != null && _curat(b.eticheta) == '${t.punct})')),
    );
    if (i >= 0) {
      var j = i + 1;
      while (j < parte.length && parte[j].tip == TipBloc.nota) {
        j++;
      }
      parte = parte.sublist(i, j);
    }
  }
  // Capul articolului (eticheta și denumirea) rămâne deasupra.
  if (!identical(parte, art) && parte.first != art.first) {
    return [art.first, ...parte];
  }
  return parte;
}

/// „Titlul III › Capitolul III” — unde stă articolul în act.
String caleArticol(List<BlocAct> blocuri, BlocAct articol) {
  final i = blocuri.indexOf(articol);
  if (i < 0) return '';
  const ranguri = [
    'partea',
    'cartea',
    'titlul',
    'capitolul',
    'secțiunea',
    'subsecțiunea',
  ];
  int rang(String e) {
    final w = e
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase()
        .replaceAll('ţ', 'ț')
        .replaceAll('ş', 'ș');
    final i = ranguri.indexOf(w);
    return i < 0 ? ranguri.length : i;
  }

  final cale = <String>[];
  var minim = ranguri.length + 1;
  for (var k = i - 1; k >= 0 && minim > 0; k--) {
    final b = blocuri[k];
    if (b.tip != TipBloc.structura) continue;
    final r = rang(b.eticheta);
    // Doar niveluri mai înalte decât cele deja găsite: secțiunea din
    // capitolul anterior nu e părintele articolului.
    if (r >= minim) continue;
    minim = r;
    cale.insert(0, b.eticheta.replaceAll('ţ', 'ț').replaceAll('ş', 'ș'));
  }
  return cale.join(' › ');
}

/// Rezultatul conține exact alineatul / litera / punctul cerut (altfel e tot
/// articolul, pentru că subdiviziunea nu mai există în forma la zi).
bool trimitereExacta(List<BlocAct> blocuri, Trimitere t) {
  if (blocuri.isEmpty) return false;
  final etichete = blocuri.skip(1).map((b) => _curat(b.eticheta)).toSet();
  if (t.alineat != null &&
      !etichete.contains('(${t.alineat})') &&
      t.litera == null &&
      t.punct == null) {
    return false;
  }
  if (t.litera != null && !etichete.contains('${t.litera})')) return false;
  if (t.punct != null &&
      !etichete.contains('${t.punct}.') &&
      !etichete.contains('${t.punct})')) {
    return false;
  }
  return true;
}
