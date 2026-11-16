import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'act_structura.dart';
import 'legislatie_service.dart';

/// Forma consolidată (la zi) a unui act și „acțiunile suferite” de el, de pe
/// legislatie.just.ro. Serviciul SOAP dă doar forma inițială, fără
/// modificări și fără stare; pagina actului are însă textul la zi, cu
/// „(la 30-06-2021, ... a fost modificat de ...)” la fiecare element, iar
/// fișa actului spune dacă a fost abrogat și prin ce (verificat 15.11.2026).

const _baza = 'https://legislatie.just.ro';

/// Portalul refuză (403) cererile cu identificarea implicită a clienților
/// HTTP; cu una de browser răspunde normal (verificat 15.11.2026).
const _antetBrowser = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36',
};

/// Id-ul actului din linkul lui: „.../Public/DetaliiDocument/73657” → „73657”.
String? idDinLink(String link) =>
    RegExp(r'DetaliiDocument(?:Afis)?/(\d+)').firstMatch(link)?.group(1);

String linkAct(String id) => '$_baza/Public/DetaliiDocument/$id';

// ---------------------------------------------------------------------------
// HTML: un cititor mic, cât pentru paginile portalului.

class _Nod {
  final String tag;
  final Map<String, String> atribute;
  final List<Object> copii = []; // _Nod sau String
  _Nod(this.tag, this.atribute);

  String get clasa => atribute['class'] ?? '';
  String get stil => atribute['style'] ?? '';
  bool get albastru => stil.replaceAll(' ', '').contains('color:blue');

  Iterable<_Nod> get noduri => copii.whereType<_Nod>();

  _Nod? copilCu(String cls) {
    for (final n in noduri) {
      if (n.clasa == cls) return n;
    }
    return null;
  }

  /// Primul descendent cu clasa dată.
  _Nod? gaseste(bool Function(_Nod) f) {
    for (final n in noduri) {
      if (f(n)) return n;
      final r = n.gaseste(f);
      if (r != null) return r;
    }
    return null;
  }
}

const _faraInchidere = {
  'br',
  'input',
  'img',
  'meta',
  'link',
  'hr',
  'col',
  'wbr',
};

final _reToken = RegExp(
  r'''<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|[^<]+|<''',
);
final _reAtribut = RegExp(
  r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?''',
);

_Nod _citesteHtml(String html) {
  final radacina = _Nod('#', const {});
  final stiva = <_Nod>[radacina];
  for (final m in _reToken.allMatches(html)) {
    final tok = m.group(0)!;
    if (tok.startsWith('<!--')) continue;
    final tag = m.group(2);
    if (tag == null) {
      stiva.last.copii.add(decodeazaEntitati(tok));
      continue;
    }
    final t = tag.toLowerCase();
    if (m.group(1) == '/') {
      final i = stiva.lastIndexWhere((n) => n.tag == t);
      if (i > 0) stiva.removeRange(i, stiva.length);
      continue;
    }
    final atribute = <String, String>{};
    for (final a in _reAtribut.allMatches(m.group(3) ?? '')) {
      atribute[a.group(1)!.toLowerCase()] = decodeazaEntitati(
        a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
      );
    }
    final nod = _Nod(t, atribute);
    stiva.last.copii.add(nod);
    final autoInchis = (m.group(3) ?? '').trimRight().endsWith('/');
    if (!_faraInchidere.contains(t) && !autoInchis) stiva.add(nod);
  }
  return radacina;
}

const _entitati = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'laquo': '«',
  'raquo': '»',
  'bdquo': '„',
  'rdquo': '”',
  'ldquo': '“',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'icirc': 'î',
  'Icirc': 'Î',
  'acirc': 'â',
  'Acirc': 'Â',
};

String decodeazaEntitati(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
    final e = m.group(1)!;
    if (e.startsWith('#x')) {
      return String.fromCharCode(int.parse(e.substring(2), radix: 16));
    }
    if (e.startsWith('#'))
      return String.fromCharCode(int.parse(e.substring(1)));
    return _entitati[e] ?? m.group(0)!;
  });
}

// ---------------------------------------------------------------------------
// Text inline, cu trimiteri.

class _TextInline {
  final b = StringBuffer();
  final legaturi = <Legatura>[];

  void adauga(String t) {
    var x = t.replaceAll(RegExp(r'[\s ]+'), ' ');
    if (x.isEmpty) return;
    final s = b.toString();
    if (x.startsWith(' ') && (s.isEmpty || s.endsWith(' '))) {
      x = x.substring(1);
    }
    b.write(x);
  }

  ({String text, List<Legatura> legaturi}) gata() {
    final s = b.toString();
    final inceput = s.length - s.trimLeft().length;
    final text = s.trim();
    return (
      text: text,
      legaturi: [
        for (final l in legaturi)
          if (l.end - inceput > 0 && l.start - inceput < text.length)
            Legatura(
              (l.start - inceput).clamp(0, text.length),
              (l.end - inceput).clamp(0, text.length),
              l.idAct,
            ),
      ],
    );
  }
}

final _reClasaBloc = RegExp(r'^S_[A-Z]+$');
const _claseInline = {'S_LGI', 'S_REF'};

bool _eBloc(_Nod n) =>
    (_reClasaBloc.hasMatch(n.clasa) && !_claseInline.contains(n.clasa)) ||
    const {'table', 'div', 'p', 'ul', 'ol', 'tr'}.contains(n.tag);

bool _ascuns(_Nod n) =>
    n.clasa.endsWith('_SHORT') ||
    n.clasa == 'TAG_COLLAPSED' ||
    (n.atribute['id'] ?? '').endsWith('_scurt') ||
    n.tag == 'script' ||
    n.tag == 'style' ||
    n.tag == 'select';

void _inline(_Nod n, _TextInline t, {bool faraBlocuri = true}) {
  for (final c in n.copii) {
    if (c is String) {
      t.adauga(c);
      continue;
    }
    final k = c as _Nod;
    if (_ascuns(k)) continue;
    if (faraBlocuri && _eBloc(k)) continue;
    if (k.tag == 'br') {
      t.adauga(' ');
      continue;
    }
    if (k.tag == 'a') {
      final id = idDinLink(k.atribute['href'] ?? '');
      final start = t.b.length;
      // Un link poate cuprinde un paragraf întreg (anexele „REGULAMENT
      // privind ...”): îl luăm tot, ca text al linkului.
      _inline(k, t, faraBlocuri: false);
      if (id != null) {
        // Fără spațiile de la început, ca linkul să înceapă pe cuvânt.
        var s = start;
        final text = t.b.toString();
        while (s < text.length && text[s] == ' ') {
          s++;
        }
        if (text.length > s) t.legaturi.add(Legatura(s, text.length, id));
      }
      continue;
    }
    final eBloc = _eBloc(k);
    if (eBloc) t.adauga(' ');
    _inline(k, t, faraBlocuri: faraBlocuri);
    if (eBloc) t.adauga(' ');
  }
}

String _textDin(_Nod? n) {
  if (n == null) return '';
  final t = _TextInline();
  _inline(n, t, faraBlocuri: false);
  return t.gata().text;
}

// ---------------------------------------------------------------------------
// Modificări: „(la 30-06-2021, Alineatul (2) din Articolul 10 a fost abrogat
// de Punctul 5, Articolul III din ORDONANȚA DE URGENȚĂ nr. 80 ...)”.

final _reModificare = RegExp(
  r'^\(la (\d{1,2})[-.](\d{1,2})[-.](\d{4}),?\s*(.+?)\s+a\s+fost\s+([a-zA-ZăâîșțşţĂÂÎȘȚ]+)\s+(?:de|prin)\s+(.+?)\s*\)?\s*$',
  dotAll: true,
);

Modificare? modificareDinText(String text, {String? idAct}) {
  final m = _reModificare.firstMatch(text.trim());
  if (m == null) return null;
  final verb = m.group(5)!.toLowerCase();
  final tip = verb.startsWith('modificat')
      ? TipModificare.modificat
      : verb.startsWith('completat') || verb.startsWith('introdus')
      ? TipModificare.completat
      : verb.startsWith('abrogat')
      ? TipModificare.abrogat
      : TipModificare.altul;
  final element = m
      .group(4)!
      .replaceAll(RegExp(r'\s+,'), ',')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return Modificare(
    data: DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
    ),
    tip: tip,
    verb: verb,
    element: element,
    act: m.group(6)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
    idAct: idAct,
  );
}

// ---------------------------------------------------------------------------
// Pagina actului → blocuri.

class FormaConsolidata {
  /// „LEGEA nr. 307 din 12 iulie 2006 (*republicată*)”.
  final String titlu;

  /// „privind apărarea împotriva incendiilor”.
  final String descriere;
  final String emitent;

  /// „MONITORUL OFICIAL nr. 297 din 17 aprilie 2019”.
  final String publicatie;

  /// Data consolidării afișate („08.05.2026”), dacă pagina o dă.
  final DateTime? dataConsolidare;
  final List<BlocAct> blocuri;

  const FormaConsolidata({
    required this.titlu,
    required this.descriere,
    required this.emitent,
    required this.publicatie,
    required this.dataConsolidare,
    required this.blocuri,
  });

  /// Câte elemente au fost modificate, completate sau abrogate.
  int get numarModificari => blocuri.where((b) => b.modificare != null).length;

  /// Textul simplu, pentru copiere și căutare.
  String get textSimplu => blocuri.map((b) => b.textComplet).join('\n');
}

final _reNotaVeche = RegExp(
  r'^\*{0,4}\)?\s*(?:Art\.|Articolul|Alin\.|Alineatul|Lit\.|Litera|Literele|Pct\.|Punctul|Partea|Titlul|Capitolul|Sec[țţ]iunea)[^\n]{0,200}?\b(?:a|au)\s+(?:fost|revenit)\b',
);

class _Constructor {
  final blocuri = <BlocAct>[];
  String? articol;

  /// Blocurile din [n], și cele ascunse în elemente inline (nu și în linkuri,
  /// al căror text a fost deja luat).
  void blocuriDin(_Nod n) {
    for (final d in n.noduri) {
      if (_ascuns(d) || d.tag == 'a') continue;
      if (_eBloc(d)) {
        bloc(d);
      } else {
        blocuriDin(d);
      }
    }
  }

  void copii(_Nod n) {
    // Textul liber dintre blocuri (rar) devine un bloc de text.
    final t = _TextInline();
    void golesteText() {
      final g = t.gata();
      if (g.text.isNotEmpty && g.text != '+') {
        blocuri.add(
          BlocAct(
            TipBloc.text,
            text: g.text,
            articol: articol,
            legaturi: g.legaturi,
          ),
        );
      }
      t.b.clear();
      t.legaturi.clear();
    }

    for (final c in n.copii) {
      if (c is String) {
        t.adauga(c);
        continue;
      }
      final k = c as _Nod;
      if (_ascuns(k)) continue;
      if (_eBloc(k)) {
        golesteText();
        bloc(k);
      } else if (k.tag == 'br') {
        t.adauga(' ');
      } else {
        // Inline: S_LGI, linkuri, text formatat.
        final tmp = _TextInline();
        _inline(k, tmp, faraBlocuri: true);
        final baza = t.b.length;
        final g = tmp.b.toString();
        t.adauga(g);
        final delta = t.b.length - baza - g.length;
        for (final l in tmp.legaturi) {
          t.legaturi.add(
            Legatura(baza + l.start + delta, baza + l.end + delta, l.idAct),
          );
        }
        // Blocurile din interiorul unui element inline (rar).
        if (k.tag != 'a' && k.gaseste(_eBloc) != null) {
          golesteText();
          blocuriDin(k);
        }
      }
    }
    golesteText();
  }

  void bloc(_Nod n) {
    final cls = n.clasa;
    switch (cls) {
      case 'S_DEN' || 'S_HDR' || 'S_EMT' || 'S_PUB':
        return;
      case 'S_ART':
        final ttl = _textDin(n.copilCu('S_ART_TTL'));
        final nr = RegExp(
          r'(\d{1,3}(?:\.\d{3})+(?!\d)(?:\s*\^\s*\d+)?|\d+(?:\s*\^\s*\d+)?)',
        ).firstMatch(ttl)?.group(1);
        articol = nr == null ? articol : nrArticol(nr);
        final corp = n.copilCu('S_ART_BDY');
        var denumire = _textDin(n.copilCu('S_ART_DEN'));
        // Codurile (civil, penal, de procedură) au S_ART_DEN gol, iar
        // denumirea marginală e primul paragraf din corp: „Dovada denumirii
        // și sediului”. O mutăm în capul articolului.
        if (denumire.isEmpty && corp != null) {
          final primul = corp.noduri.where((k) => !_ascuns(k)).firstOrNull;
          if (primul != null && primul.clasa == 'S_PAR') {
            final t = _textDin(primul);
            if (_eDenumire(t)) {
              denumire = t;
              corp.copii.remove(primul);
            }
          }
        }
        blocuri.add(
          BlocAct(
            TipBloc.articol,
            eticheta: nr == null ? ttl : 'Art. $nr',
            titlu: denumire,
            articol: articol,
            actualizat: n.albastru,
          ),
        );
        if (corp != null) copii(corp);
        return;
      case 'S_ALN' || 'S_LIT' || 'S_PCT' || 'S_LIN':
        final ttl = _textDin(n.copilCu('${cls}_TTL'));
        final corp = n.copilCu('${cls}_BDY');
        final t = _TextInline();
        if (corp != null) _inline(corp, t);
        var g = t.gata();
        var eticheta = ttl;
        // Formele vechi au eticheta în text: „g) cererile pentru ...”.
        if (eticheta.isEmpty && cls != 'S_LIN') {
          final e = RegExp(r'^([a-z]{1,2}(?:\^\d+)?\)|\d{1,3}(?:\^\d+)?\.)\s+')
              .firstMatch(g.text);
          if (e != null) {
            eticheta = e.group(1)!;
            final n = e.end;
            g = (
              text: g.text.substring(n),
              legaturi: [
                for (final l in g.legaturi)
                  if (l.start >= n) Legatura(l.start - n, l.end - n, l.idAct),
              ],
            );
          }
        }
        final roman = RegExp(r'^[IVXLC]+\.$').hasMatch(eticheta);
        blocuri.add(
          BlocAct(
            cls == 'S_ALN' || (cls == 'S_PCT' && roman)
                ? TipBloc.alineat
                : TipBloc.litera,
            eticheta: eticheta.isEmpty && cls == 'S_LIN' ? '–' : eticheta,
            text: g.text,
            articol: articol,
            actualizat: n.albastru,
            legaturi: g.legaturi,
          ),
        );
        if (corp != null) blocuriDin(corp);
        return;
      case 'S_PAR':
        final t = _TextInline();
        _inline(n, t);
        final g = t.gata();
        final mod = n.albastru && g.text.startsWith('(la ')
            ? modificareDinText(
                g.text,
                idAct: g.legaturi.isEmpty ? null : g.legaturi.first.idAct,
              )
            : null;
        // Formele vechi: linii „------” și note „Art. 2 a fost modificat de ...”.
        if (RegExp(r'^-{3,}$').hasMatch(g.text)) return;
        final notaVeche =
            mod == null && g.text.length < 700 && _reNotaVeche.hasMatch(g.text);
        if (g.text.isNotEmpty) {
          blocuri.add(
            BlocAct(
              mod != null || notaVeche ? TipBloc.nota : TipBloc.text,
              text: g.text,
              articol: articol,
              modificare: mod,
              actualizat: n.albastru,
              legaturi: g.legaturi,
            ),
          );
        }
        blocuriDin(n);
        return;
      case 'S_NTA':
        final parti = <String>[];
        final leg = <Legatura>[];
        void par(_Nod p) {
          final t = _TextInline();
          _inline(p, t, faraBlocuri: false);
          final g = t.gata();
          if (g.text.isEmpty) return;
          final baza = parti.isEmpty ? 0 : parti.join('\n').length + 1;
          parti.add(g.text);
          for (final l in g.legaturi) {
            leg.add(Legatura(baza + l.start, baza + l.end, l.idAct));
          }
        }

        void cauta(_Nod x) {
          for (final d in x.noduri) {
            if (d.clasa == 'S_NTA_PAR') {
              par(d);
            } else if (!d.clasa.startsWith('S_NTA_')) {
              cauta(d);
            }
          }
        }

        cauta(n);
        if (parti.isNotEmpty) {
          blocuri.add(
            BlocAct(
              TipBloc.nota,
              text: 'Notă: ${parti.join('\n')}',
              articol: articol,
              legaturi: [
                for (final l in leg) Legatura(l.start + 6, l.end + 6, l.idAct),
              ],
            ),
          );
        }
        return;
      case 'S_SMN':
        final semnaturi = [
          for (final d in n.noduri)
            if (d.clasa == 'S_SMN_PAR') _textDin(d),
        ].where((s) => s.isNotEmpty).toList();
        if (semnaturi.isNotEmpty) {
          blocuri.add(
            BlocAct(TipBloc.text, text: semnaturi.join('\n'), articol: articol),
          );
        }
        return;
      case 'S_CIT':
        copii(n);
        return;
    }
    if (n.tag == 'tr') {
      final celule = [
        for (final d in n.noduri)
          if (d.tag == 'td' || d.tag == 'th') _textDin(d),
      ].where((s) => s.isNotEmpty).toList();
      if (celule.isNotEmpty) {
        blocuri.add(
          BlocAct(TipBloc.text, text: celule.join(' | '), articol: articol),
        );
      }
      return;
    }
    // Structură: capitole, secțiuni, titluri, anexe („S_CAP”, „S_ANX”...).
    final ttl = n.copilCu('${cls}_TTL');
    final corp = n.copilCu('${cls}_BDY');
    if (cls.isNotEmpty && ttl != null) {
      if (cls == 'S_ANX') articol = null;
      blocuri.add(
        BlocAct(
          TipBloc.structura,
          eticheta: _textDin(ttl),
          titlu: _textDin(n.copilCu('${cls}_DEN')),
          articol: articol,
          actualizat: n.albastru,
        ),
      );
      if (corp != null) copii(corp);
      return;
    }
    copii(n);
  }
}

/// Citește pagina unui act (Public/DetaliiDocument/<id>). Null dacă pagina
/// nu are forma așteptată (atunci rămâne textul din căutare).
FormaConsolidata? formaDinHtml(String html) {
  final start = html.indexOf('<span class="S_DEN"');
  if (start < 0) return null;
  var sfarsit = html.indexOf('<div id="div_Formerepublicate"', start);
  if (sfarsit < 0)
    sfarsit = html.indexOf('<div id="fisa_act_container"', start);
  if (sfarsit < 0) sfarsit = html.length;
  final radacina = _citesteHtml(html.substring(start, sfarsit));

  _Nod? gaseste(String cls) => radacina.gaseste((n) => n.clasa == cls);

  final c = _Constructor();
  c.copii(radacina);
  // Ultimele închideri de div aparțin paginii, nu actului.
  final blocuri = c.blocuri;

  final dataCons = RegExp(
    r'''title='Consolidarea din (\d{2})\.(\d{2})\.(\d{4})' style='color:red''',
  ).firstMatch(html);
  return FormaConsolidata(
    titlu: _textDin(gaseste('S_DEN')),
    descriere: _textDin(gaseste('S_HDR')),
    emitent: _textDin(gaseste('S_EMT_BDY')),
    publicatie: _textDin(gaseste('S_PUB_BDY')),
    dataConsolidare: dataCons == null
        ? null
        : DateTime(
            int.parse(dataCons.group(3)!),
            int.parse(dataCons.group(2)!),
            int.parse(dataCons.group(1)!),
          ),
    blocuri: blocuri,
  );
}

/// Un act cu datele din pagina lui, pentru actele deschise doar după id.
ActNormativ actDinForma(FormaConsolidata f, String link) {
  final t = f.titlu;
  final nr = RegExp(r'nr\.\s*([\d.]+)').firstMatch(t)?.group(1) ?? '';
  final primul = t.split(RegExp(r'\s+nr\.|\s+din\s')).first;
  return ActNormativ(
    tipAct: fataDiacritice(tipDinAbreviere(primul) ?? primul).toUpperCase(),
    numar: nr.replaceAll('.', ''),
    titlu: [t, f.descriere].where((x) => x.isNotEmpty).join(' '),
    emitent: f.emitent,
    publicatie: f.publicatie,
    linkHtml: link,
    text: '',
  );
}

// ---------------------------------------------------------------------------
// Acțiuni suferite: „Actul | ABROGAT DE | LEGE 76 24/05/2012”.

class ActiuneSuferita {
  /// „Actul”, „ART. 1”, „CAP. 2”.
  final String sectiune;

  /// „MODIFICAT DE”, „ABROGAT DE”, „COMPLETAT DE”...
  final String operatie;

  /// Actul care a făcut schimbarea, scris ca pe portal: „LEGE 76 24/05/2012”.
  final String act;
  final String? idAct;

  /// Pentru acțiunile luate din notele formei la zi.
  final String? denumireExplicita;
  final DateTime? dataExplicita;

  const ActiuneSuferita({
    required this.sectiune,
    required this.operatie,
    required this.act,
    this.idAct,
    this.denumireExplicita,
    this.dataExplicita,
  });

  bool get peTotActul => sectiune.toLowerCase() == 'actul';

  /// „Legea nr. 76/2012”, „OUG nr. 80/2021”.
  String get denumireAct => denumireExplicita ?? denumireActScurta(act);

  /// Data actului („24/05/2012”).
  DateTime? get data {
    if (dataExplicita != null) return dataExplicita;
    final m = RegExp(r'(\d{2})/(\d{2})/(\d{4})').firstMatch(act);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
    );
  }

  /// „modificat de”, „abrogat parțial de”.
  String get operatieText {
    final o = operatie.toLowerCase();
    return switch (o) {
      'abrogat partial de' => 'abrogat parțial de',
      'neconstitutionalitate admisa' =>
        'excepție de neconstituționalitate admisă',
      'intrat in vigoare' => 'intrat în vigoare',
      'prorogat de' => 'termen prorogat de',
      _ => o,
    };
  }
}

const _tipuriPortal = {
  'LEGE': 'Legea',
  'ORD DE URGENTA': 'OUG',
  'ORDONANTA DE URGENTA': 'OUG',
  'ORDONANTA': 'OG',
  'HOTARARE': 'HG',
  'DECRET': 'Decretul',
  'DECRET-LEGE': 'Decretul-lege',
  'DECIZIE': 'Decizia',
  'ORDIN': 'Ordinul',
  'REGULAMENT': 'Regulamentul',
  'NORMA': 'Norma',
  'COD': 'Codul',
};

/// „ORD DE URGENTA        80 30/06/2021” → „OUG nr. 80/2021”.
String denumireActScurta(String act) {
  final a = act.replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(r'^(.+?)(?: (\d+))? (\d{2})/(\d{2})/(\d{4})$').firstMatch(a);
  if (m == null) return a;
  final tip = m.group(1)!.toUpperCase();
  final nume = _tipuriPortal[tip] ?? _capitalizeaza(tip);
  if ((m.group(2) ?? '0') == '0')
    return '$nume din ${m.group(3)}.${m.group(4)}.${m.group(5)}';
  return '$nume nr. ${m.group(2)}/${m.group(5)}';
}

String _capitalizeaza(String s) {
  final t = s.toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

List<ActiuneSuferita> actiuniDinJson(String json) {
  String html;
  try {
    final d = jsonDecode(json.startsWith('﻿') ? json.substring(1) : json);
    html = d is Map ? '${d['acte'] ?? ''}' : '';
  } catch (_) {
    return const [];
  }
  final r = <ActiuneSuferita>[];
  final reCelula = RegExp(r'<td[^>]*>([\s\S]*?)</td>');
  String curat(String s) =>
      decodeazaEntitati(s.replaceAll(RegExp(r'<[^>]*>'), ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  for (final rand in html.split(RegExp(r'<tr[\s>]')).skip(1)) {
    final celule = reCelula
        .allMatches(rand.split('</tr>').first)
        .map((m) => m.group(1)!)
        .toList();
    if (celule.length != 3) continue;
    final sectiune = curat(celule[0]);
    final operatie = curat(celule[1]);
    if (sectiune == 'SECTIUNE ACT' || operatie.isEmpty) continue;
    r.add(
      ActiuneSuferita(
        sectiune: sectiune,
        operatie: operatie,
        act: curat(celule[2]),
        idAct: idDinLink(celule[2]),
      ),
    );
  }
  return r;
}

const _tipuriText = {
  'LEGEA': 'Legea',
  'LEGII': 'Legea',
  'ORDONANȚA DE URGENȚĂ': 'OUG',
  'ORDONANȚEI DE URGENȚĂ': 'OUG',
  'ORDONANȚA': 'OG',
  'ORDONANȚEI': 'OG',
  'HOTĂRÂREA': 'HG',
  'HOTĂRÂRII': 'HG',
  'DECIZIA': 'Decizia',
  'ORDINUL': 'Ordinul',
  'DECRETUL': 'Decretul',
};

/// „Punctul 1, Articolul III din ORDONANȚA DE URGENȚĂ nr. 80 din 30 iunie
/// 2021, publicată ...” → „OUG nr. 80/2021”.
String denumireDinText(String act) {
  final m = RegExp(
    r'(LEGEA|LEGII|ORDONANȚA DE URGENȚĂ|ORDONANȚEI DE URGENȚĂ|ORDONANȚA|ORDONANȚEI|HOTĂRÂREA|HOTĂRÂRII|DECIZIA|ORDINUL|DECRETUL)\s+nr\.\s*([\d.]+)\s+din\s+\d{1,2}\s+\S+\s+(\d{4})',
  ).firstMatch(act);
  if (m == null) return act.split(',').first.trim();
  return '${_tipuriText[m.group(1)!]} nr. ${m.group(2)}/${m.group(3)}';
}

/// Modificările din notele formei la zi, ca acțiuni: „ART. 3 · completat de
/// OUG nr. 17/2026”. Fișa actului de pe portal nu le are mereu pe cele noi.
List<ActiuneSuferita> actiuniDinForma(FormaConsolidata f) {
  final r = <ActiuneSuferita>[];
  final vazute = <String>{};
  for (final b in f.blocuri) {
    final m = b.modificare;
    if (m == null) continue;
    final art = RegExp(
      r'(?:Articolul|\bart\.)\s*(\d{1,3}(?:\.\d{3})+(?!\d)(?:\^\d+)?|\d+(?:\^\d+)?)',
      caseSensitive: false,
    ).firstMatch(m.element)?.group(1);
    final sectiune = art != null
        ? 'ART. $art'
        : m.element.startsWith('Titlul actului')
        ? 'Titlul actului'
        : m.element.split(' ').first;
    final operatie = switch (m.tip) {
      TipModificare.modificat => 'MODIFICAT DE',
      TipModificare.completat => 'COMPLETAT DE',
      TipModificare.abrogat => 'ABROGAT DE',
      TipModificare.altul => '${fataDiacritice(m.verb).toUpperCase()} DE',
    };
    final denumire = denumireDinText(m.act);
    if (!vazute.add('$sectiune|$operatie|$denumire')) continue;
    r.add(
      ActiuneSuferita(
        sectiune: sectiune,
        operatie: operatie,
        act: m.act,
        idAct: m.idAct,
        denumireExplicita: denumire,
        dataExplicita: m.data,
      ),
    );
  }
  return r;
}

/// Fișa actului plus notele formei la zi, fără dubluri (aceeași secțiune,
/// operație și act).
List<ActiuneSuferita> istoricComplet(StareAct? s, FormaConsolidata? f) {
  final r = <ActiuneSuferita>[...?s?.actiuni];
  String cheie(ActiuneSuferita a) =>
      '${a.sectiune.toUpperCase()}|${a.operatie.toUpperCase()}|${a.denumireAct.toLowerCase()}';
  final vazute = r.map(cheie).toSet();
  if (f != null) {
    for (final a in actiuniDinForma(f)) {
      if (vazute.add(cheie(a))) r.add(a);
    }
  }
  return StareAct(r).ordonate;
}

/// Starea unui act, din acțiunile suferite.
class StareAct {
  final List<ActiuneSuferita> actiuni;
  const StareAct(this.actiuni);

  ActiuneSuferita? get abrogatDe {
    for (final a in actiuni) {
      if (a.peTotActul && a.operatie.toUpperCase() == 'ABROGAT DE') return a;
    }
    return null;
  }

  bool get abrogat => abrogatDe != null;

  /// Acțiunile pe tot actul, apoi pe articole, cele mai noi întâi.
  List<ActiuneSuferita> get ordonate {
    final l = [...actiuni];
    l.sort((x, y) {
      final p = (y.peTotActul ? 1 : 0).compareTo(x.peTotActul ? 1 : 0);
      if (p != 0) return p;
      return (y.data ?? DateTime(0)).compareTo(x.data ?? DateTime(0));
    });
    return l;
  }
}

// ---------------------------------------------------------------------------

class FormaConsolidataService {
  FormaConsolidataService._({http.Client? client})
    : _client = client ?? http.Client();

  static FormaConsolidataService instance = FormaConsolidataService._();

  /// Pentru teste.
  factory FormaConsolidataService.cuClient(http.Client client) =>
      FormaConsolidataService._(client: client);

  final http.Client _client;
  final _forme = <String, FormaConsolidata?>{};
  final _stari = <String, StareAct>{};

  /// Forma la zi a actului cu [id] (id-ul din linkul lui). Null dacă
  /// pagina nu poate fi citită.
  Future<FormaConsolidata?> forma(String id) async {
    if (_forme.containsKey(id)) return _forme[id];
    final r = await _client
        .get(Uri.parse(linkAct(id)), headers: _antetBrowser)
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw Exception('Portalul legislativ a răspuns cu ${r.statusCode}.');
    }
    final html = utf8.decode(r.bodyBytes, allowMalformed: true);
    final f = await Isolate.run(() => formaDinHtml(html));
    _forme[id] = f;
    return f;
  }

  /// Ce i s-a întâmplat actului: abrogări, modificări, completări.
  Future<StareAct> stare(String id) async {
    final dinCache = _stari[id];
    if (dinCache != null) return dinCache;
    final r = await _client
        .post(
          Uri.parse('$_baza/Public/actiuniSuferite'),
          headers: {
            ..._antetBrowser,
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          },
          body: 'contor=$id',
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('Portalul legislativ a răspuns cu ${r.statusCode}.');
    }
    final s = StareAct(
      actiuniDinJson(utf8.decode(r.bodyBytes, allowMalformed: true)),
    );
    _stari[id] = s;
    return s;
  }
}

/// Un paragraf scurt, fără punct la final, care nu e o notă sau un alineat:
/// denumirea marginală a unui articol din coduri.
bool _eDenumire(String t) {
  final x = t.trim();
  if (x.isEmpty || x.length > 160) return false;
  if (RegExp(r'[.;:,]$').hasMatch(x)) return false;
  if (RegExp(r'^(\(|\*|Not[aă]|\[|[a-z]\)|\d)').hasMatch(x)) return false;
  return RegExp(r'^[A-ZĂÂÎȘŞȚŢ]').hasMatch(x);
}
