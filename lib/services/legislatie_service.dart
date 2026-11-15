import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../data/acte_cunoscute.dart';

/// Un act normativ din Portalul Legislativ al Ministerului Justiției
/// (legislatie.just.ro).
class ActNormativ {
  final String tipAct;
  final String numar;
  final DateTime? dataVigoare;
  final String titlu;
  final String emitent;
  final String publicatie;
  final String linkHtml;
  final String text;

  const ActNormativ({
    required this.tipAct,
    required this.numar,
    this.dataVigoare,
    required this.titlu,
    required this.emitent,
    required this.publicatie,
    required this.linkHtml,
    required this.text,
  });

  /// Anul actului: din titlu („din 26 iunie 2014”) sau din publicație,
  /// altfel din data intrării în vigoare.
  int? get an {
    for (final sursa in [titlu, publicatie]) {
      final m = RegExp(r'\b(18|19|20)\d{2}\b').firstMatch(sursa);
      if (m != null) return int.parse(m.group(0)!);
    }
    return dataVigoare?.year;
  }

  /// „Lege 85/2014”, „Ordonanță de urgență 195/2002”.
  String get denumireScurta {
    final tip = tipAct.isEmpty ? 'Act' : etichetaTip(tipAct);
    final nr = numar.trim();
    if (nr.isEmpty || nr == '0') return tip;
    final a = an;
    return a == null ? '$tip nr. $nr' : '$tip nr. $nr/$a';
  }

  /// Cheie stabilă pentru dubluri: linkul oficial, dacă există.
  String get cheie => linkHtml.isNotEmpty ? linkHtml : '$tipAct|$numar|$titlu';

  Map<String, dynamic> toJson() => {
    'tipAct': tipAct,
    'numar': numar,
    'dataVigoare': dataVigoare?.toIso8601String(),
    'titlu': titlu,
    'emitent': emitent,
    'publicatie': publicatie,
    'linkHtml': linkHtml,
  };
}

String _majusculaInitiala(String s) {
  final t = s.trim().toLowerCase();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Ce trimitem serviciului. Serviciul caută după text liber SAU după
/// titlu, plus număr și an. Restul filtrelor (tip, emitent, interval de ani)
/// se aplică în aplicație, peste rezultate.
class CerereLegislatie {
  final String text;
  final String titlu;
  final String numar;
  final int? an;

  const CerereLegislatie({
    this.text = '',
    this.titlu = '',
    this.numar = '',
    this.an,
  });

  bool get goala =>
      text.trim().isEmpty && titlu.trim().isEmpty && numar.trim().isEmpty;

  /// Interpretează ce scrie omul în bara de căutare:
  /// „legea 85/2014”, „oug 195/2002”, „85/2014” → număr + an (+ tip);
  /// orice altceva → text liber.
  static ({CerereLegislatie cerere, String? tip}) dinText(String intrare) {
    final s = intrare.trim();
    final m = RegExp(
      r'^(?:(?<tip>[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ\. ]+?)\s*(?:nr\.?\s*)?)?(?<nr>\d{1,5})\s*/\s*(?<an>\d{4})$',
      caseSensitive: false,
    ).firstMatch(s);
    if (m != null) {
      final tip = tipDinAbreviere(m.namedGroup('tip') ?? '');
      return (
        cerere: CerereLegislatie(
          numar: m.namedGroup('nr')!,
          an: int.parse(m.namedGroup('an')!),
        ),
        tip: tip,
      );
    }
    return (cerere: CerereLegislatie(text: s), tip: null);
  }
}

/// Tipurile de acte cele mai folosite, cum le scrie serviciul (majuscule).
const tipuriActe = <String>[
  'LEGE',
  'ORDONANTA DE URGENTA',
  'ORDONANTA',
  'HOTARARE',
  'DECRET',
  'ORDIN',
  'DECIZIE',
  'REGULAMENT',
  'NORMA',
  'CONSTITUTIE',
];

/// Eticheta afișată pentru un tip de act.
String etichetaTip(String tip) => switch (tip) {
  'LEGE' => 'Lege',
  'ORDONANTA DE URGENTA' => 'OUG',
  'ORDONANTA' => 'Ordonanță',
  'HOTARARE' => 'Hotărâre',
  'DECRET' => 'Decret',
  'ORDIN' => 'Ordin',
  'DECIZIE' => 'Decizie',
  'REGULAMENT' => 'Regulament',
  'NORMA' => 'Normă',
  'CONSTITUTIE' => 'Constituție',
  _ => _majusculaInitiala(tip),
};

/// „OUG”, „Legea”, „HG”, „O.U.G.” → tipul din [tipuriActe].
String? tipDinAbreviere(String s) {
  final t = fataDiacritice(s)
      .toUpperCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return null;
  if (t == 'OUG' ||
      t.startsWith('ORDONANTA DE URGENTA') ||
      t.startsWith('ORDONANTEI DE URGENTA')) {
    return 'ORDONANTA DE URGENTA';
  }
  if (t == 'OG' || t.startsWith('ORDONANT')) return 'ORDONANTA';
  if (t == 'HG' || t.startsWith('HOTAR')) return 'HOTARARE';
  if (t.startsWith('LEGE') || t == 'L') return 'LEGE';
  if (t.startsWith('DECRET')) return 'DECRET';
  if (t.startsWith('ORDIN')) return 'ORDIN';
  if (t.startsWith('DECIZI')) return 'DECIZIE';
  return null;
}

/// Scoate diacriticele (inclusiv variantele cu sedilă ş/ţ), pentru comparații.
String fataDiacritice(String s) {
  const din = 'ăâîșşțţĂÂÎȘŞȚŢ';
  const in_ = 'aaissttAAISSTT';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = din.indexOf(c);
    b.write(i < 0 ? c : in_[i]);
  }
  return b.toString();
}

class LegislatieException implements Exception {
  final String mesaj;
  LegislatieException(this.mesaj);

  @override
  String toString() => mesaj;
}

/// O pagină de rezultate. [maiSunt] e true când serviciul a umplut pagina,
/// deci probabil există și pagina următoare.
class PaginaLegislatie {
  final List<ActNormativ> acte;
  final bool maiSunt;

  const PaginaLegislatie(this.acte, this.maiSunt);
}

/// Client pentru serviciul web public și gratuit al Portalului Legislativ
/// (legislatie.just.ro/apiws/FreeWebService.svc). Nu cere cont: un token
/// se obține cu GetToken și se trimite la fiecare Search.
class LegislatieService {
  LegislatieService._({http.Client? client})
    : _client = client ?? http.Client();

  static LegislatieService instance = LegislatieService._();

  /// Pentru teste.
  factory LegislatieService.cuClient(http.Client client) =>
      LegislatieService._(client: client);

  static final Uri _endpoint = Uri.parse(
    'https://legislatie.just.ro/apiws/FreeWebService.svc/SOAP',
  );
  static const _nsTempuri = 'http://tempuri.org/';
  static const _nsDate =
      'http://schemas.datacontract.org/2004/07/FreeWebService';

  /// Serviciul întoarce cel mult 20 de acte pe pagină.
  static const int rezultatePePagina = 20;

  /// Tokenul e reînnoit după 20 de minute.
  static const _durataToken = Duration(minutes: 20);

  /// Pauza minimă între două cereri, ca să nu încărcăm serviciul public.
  static Duration pauzaIntreCereri = const Duration(seconds: 1);

  final http.Client _client;
  String? _token;
  DateTime? _tokenObtinut;
  DateTime? _ultimaCerere;
  Future<void> _coada = Future.value();
  final Map<String, PaginaLegislatie> _cache = {};

  Future<void> _asteaptaRandul() {
    final rand = _coada.then((_) async {
      final ultima = _ultimaCerere;
      if (ultima != null) {
        final ramas = pauzaIntreCereri - DateTime.now().difference(ultima);
        if (ramas > Duration.zero) await Future<void>.delayed(ramas);
      }
      _ultimaCerere = DateTime.now();
    });
    _coada = rand.catchError((_) {});
    return rand;
  }

  Future<String> _post(
    String actiune,
    String envelope,
    Duration timeout,
  ) async {
    await _asteaptaRandul();
    final http.Response r;
    try {
      r = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'text/xml; charset=utf-8',
              'SOAPAction': '"http://tempuri.org/IFreeWebService/$actiune"',
            },
            body: utf8.encode(envelope),
          )
          .timeout(timeout);
    } catch (e) {
      throw LegislatieException(
        'Nu s-a putut contacta Portalul Legislativ. Verifică conexiunea la internet și reîncearcă.',
      );
    }
    if (r.statusCode == 429 || r.statusCode == 503) {
      throw LegislatieException(
        'Portalul Legislativ e ocupat acum. Reîncearcă peste un minut.',
      );
    }
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode != 200) {
      final fault = _fault(body);
      throw LegislatieException(
        fault != null
            ? 'Eroare de la Portalul Legislativ: $fault'
            : 'Portalul Legislativ a răspuns cu eroarea ${r.statusCode}.',
      );
    }
    return body;
  }

  Future<String> _obtineToken({bool fortat = false}) async {
    final t = _token;
    final obtinut = _tokenObtinut;
    if (!fortat &&
        t != null &&
        obtinut != null &&
        DateTime.now().difference(obtinut) < _durataToken) {
      return t;
    }
    final body = await _post(
      'GetToken',
      cerereToken(),
      const Duration(seconds: 20),
    );
    final token = parseazaToken(body);
    if (token == null || token.isEmpty) {
      throw LegislatieException(
        'Portalul Legislativ nu a dat acces (token lipsă).',
      );
    }
    _token = token;
    _tokenObtinut = DateTime.now();
    return token;
  }

  /// Caută acte normative. [pagina] începe de la 1. Rezultatele unei
  /// cereri identice sunt ținute în memorie cât e deschisă aplicația.
  ///
  /// Pentru căutările din mai multe cuvinte („codul urbanismului”) serviciul
  /// caută expresia exactă, care adesea nu apare nicăieri: titlul real e
  /// „Codul amenajării teritoriului, urbanismului și construcțiilor”. Așa că,
  /// pe prima pagină, mai cerem titlurile care conțin cuvântul cel mai rar
  /// („urbanism”) și le punem în față pe cele care au toate cuvintele.
  Future<PaginaLegislatie> cauta(
    CerereLegislatie cerere, {
    int pagina = 1,
  }) async {
    if (cerere.goala) return const PaginaLegislatie([], false);
    final expresie = cerere.numar.isEmpty
        ? (cerere.text.isNotEmpty ? cerere.text : cerere.titlu)
        : '';
    final cuvant = pagina <= 1 ? cuvantPentruTitlu(expresie) : null;
    if (cuvant == null) return _cautaPagina(cerere, pagina);

    PaginaLegislatie? principala;
    Object? eroare;
    try {
      principala = await _cautaPagina(cerere, pagina);
    } catch (e) {
      eroare = e;
    }
    final radacini = radaciniCautare(expresie);
    final dinTitluri = <ActNormativ>[];
    try {
      for (var p = 1; p <= 2; p++) {
        final r = await _cautaPagina(CerereLegislatie(titlu: cuvant), p);
        dinTitluri.addAll(
          r.acte.where((a) => titluContineToate(a.titlu, radacini)),
        );
        if (!r.maiSunt) break;
      }
    } catch (_) {
      // Căutarea suplimentară e un bonus; dacă pică, rămâne cea principală.
    }
    if (principala == null && dinTitluri.isEmpty) throw eroare!;
    final vazute = <String>{};
    final acte = [
      ...dinTitluri,
      ...?principala?.acte,
    ].where((a) => vazute.add(a.cheie)).toList();
    return PaginaLegislatie(acte, principala?.maiSunt ?? false);
  }

  Future<PaginaLegislatie> _cautaPagina(
    CerereLegislatie cerere,
    int pagina,
  ) async {
    final cheie =
        '${cerere.text}|${cerere.titlu}|${cerere.numar}|${cerere.an}|$pagina';
    final dinCache = _cache[cheie];
    if (dinCache != null) return dinCache;

    Future<String> trimite(String token) => _post(
      'Search',
      cerereCautare(cerere, token: token, pagina: pagina),
      const Duration(seconds: 40),
    );

    String body;
    try {
      body = await trimite(await _obtineToken());
    } on LegislatieException {
      // Tokenul poate fi expirat pe server înaintea noastră: încă o dată, cu unul nou.
      body = await trimite(await _obtineToken(fortat: true));
    }
    // Răspunsul conține textul integral al actelor (poate avea câțiva MB),
    // deci îl parsăm în alt isolate.
    final acte = await _parseazaInAltIsolate(body);
    final rezultat = PaginaLegislatie(acte, acte.length >= rezultatePePagina);
    if (_cache.length > 30) _cache.remove(_cache.keys.first);
    _cache[cheie] = rezultat;
    return rezultat;
  }
}

// Funcție de nivel superior: închiderea trimisă altui isolate nu trebuie să
// prindă serviciul (are Future-uri, care nu se pot trimite).
Future<List<ActNormativ>> _parseazaInAltIsolate(String body) =>
    Isolate.run(() => parseazaRaspunsCautare(body));

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String cerereToken() =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><GetToken xmlns="${LegislatieService._nsTempuri}"/></s:Body></s:Envelope>';

/// Cererea Search. Câmpurile SearchModel sunt în ordine alfabetică, cum le
/// cere serviciul WCF; cele goale pleacă ca `i:nil`.
String cerereCautare(
  CerereLegislatie c, {
  required String token,
  int pagina = 1,
}) {
  String camp(String nume, String valoare) => valoare.trim().isEmpty
      ? '<d:$nume i:nil="true"/>'
      : '<d:$nume>${_escape(valoare.trim())}</d:$nume>';
  // Paginile 0 și 1 întorc același lucru; numărăm de la 1.
  final p = pagina < 1 ? 1 : pagina;
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body><Search xmlns="${LegislatieService._nsTempuri}">'
      '<SearchModel xmlns:d="${LegislatieService._nsDate}" '
      'xmlns:i="http://www.w3.org/2001/XMLSchema-instance">'
      '<d:NumarPagina>$p</d:NumarPagina>'
      '<d:RezultatePagina>${LegislatieService.rezultatePePagina}</d:RezultatePagina>'
      '${camp('SearchAn', c.an?.toString() ?? '')}'
      '${camp('SearchNumar', c.numar)}'
      '${camp('SearchText', c.text)}'
      '${camp('SearchTitlu', c.titlu)}'
      '</SearchModel>'
      '<tokenKey>${_escape(token)}</tokenKey>'
      '</Search></s:Body></s:Envelope>';
}

String? _fault(String body) {
  try {
    final f = XmlDocument.parse(body)
        .findAllElements('faultstring')
        .firstOrNull;
    return f?.innerText.trim();
  } catch (_) {
    return null;
  }
}

String? parseazaToken(String body) {
  final doc = XmlDocument.parse(body);
  final fault = doc.findAllElements('faultstring').firstOrNull;
  if (fault != null) {
    throw LegislatieException(
      'Eroare de la Portalul Legislativ: ${fault.innerText}',
    );
  }
  return doc.descendantElements
      .where((e) => e.localName == 'GetTokenResult')
      .firstOrNull
      ?.innerText
      .trim();
}

List<ActNormativ> parseazaRaspunsCautare(String body) {
  final doc = XmlDocument.parse(body);
  final fault = doc.findAllElements('faultstring').firstOrNull;
  if (fault != null) {
    throw LegislatieException(
      'Eroare de la Portalul Legislativ: ${fault.innerText}',
    );
  }

  String text(XmlElement e, String nume) =>
      e.childElements
          .where((c) => c.localName == nume)
          .firstOrNull
          ?.innerText
          .trim() ??
      '';

  return doc.descendantElements.where((e) => e.localName == 'Legi').map((e) {
    var link = text(e, 'LinkHtml');
    if (link.startsWith('http://')) link = 'https://${link.substring(7)}';
    return ActNormativ(
      tipAct: text(e, 'TipAct').toUpperCase(),
      numar: text(e, 'Numar'),
      dataVigoare: _data(text(e, 'DataVigoare')),
      titlu: titluFaraAntet(text(e, 'Titlu')),
      emitent: text(e, 'Emitent'),
      publicatie: text(e, 'Publicatie'),
      linkHtml: link,
      text: textFaraAntet(curataText(text(e, 'Text'))),
    );
  }).toList();
}

/// Data poate veni ca ISO („2014-06-28T00:00:00”) sau „28.06.2014”.
DateTime? _data(String s) {
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.year < 1800 ? null : iso;
  final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
  );
}

/// Textul actelor poate conține marcaj HTML; păstrăm doar textul, cu
/// paragrafele pe rânduri separate.
String curataText(String s) {
  if (!s.contains('<')) return s.replaceAll('\r\n', '\n').trim();
  var t = s
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|tr|li|h\d)\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  t = t
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
  return t.trim();
}

// ---------------------------------------------------------------------------
// Filtre aplicate în aplicație

enum OrdineLegislatie { relevanta, celeMaiNoi, celeMaiVechi }

class FiltreLegislatie {
  final Set<String> tipuri;
  final String emitent;
  final int? anDe;
  final int? anPana;
  final OrdineLegislatie ordine;

  const FiltreLegislatie({
    this.tipuri = const {},
    this.emitent = '',
    this.anDe,
    this.anPana,
    this.ordine = OrdineLegislatie.relevanta,
  });

  bool get active =>
      tipuri.isNotEmpty ||
      emitent.trim().isNotEmpty ||
      anDe != null ||
      anPana != null;

  int get numarActive =>
      (tipuri.isNotEmpty ? 1 : 0) +
      (emitent.trim().isNotEmpty ? 1 : 0) +
      (anDe != null || anPana != null ? 1 : 0);

  FiltreLegislatie copyWith({
    Set<String>? tipuri,
    String? emitent,
    int? Function()? anDe,
    int? Function()? anPana,
    OrdineLegislatie? ordine,
  }) => FiltreLegislatie(
    tipuri: tipuri ?? this.tipuri,
    emitent: emitent ?? this.emitent,
    anDe: anDe != null ? anDe() : this.anDe,
    anPana: anPana != null ? anPana() : this.anPana,
    ordine: ordine ?? this.ordine,
  );
}

bool _potrivesteTip(ActNormativ a, String tip) {
  final t = fataDiacritice(a.tipAct).toUpperCase();
  if (tip == 'ORDONANTA')
    return t.startsWith('ORDONANTA') && !t.contains('URGENTA');
  return t.startsWith(tip);
}

List<ActNormativ> aplicaFiltre(List<ActNormativ> acte, FiltreLegislatie f) {
  final emitent = fataDiacritice(f.emitent.trim().toLowerCase());
  final rezultat = acte.where((a) {
    if (f.tipuri.isNotEmpty && !f.tipuri.any((t) => _potrivesteTip(a, t)))
      return false;
    if (emitent.isNotEmpty &&
        !fataDiacritice(a.emitent.toLowerCase()).contains(emitent)) {
      return false;
    }
    final an = a.an;
    if (f.anDe != null && (an == null || an < f.anDe!)) return false;
    if (f.anPana != null && (an == null || an > f.anPana!)) return false;
    return true;
  }).toList();
  int cheieData(ActNormativ a) =>
      a.dataVigoare?.millisecondsSinceEpoch ??
      DateTime(a.an ?? 1800).millisecondsSinceEpoch;
  switch (f.ordine) {
    case OrdineLegislatie.relevanta:
      break;
    case OrdineLegislatie.celeMaiNoi:
      rezultat.sort((a, b) => cheieData(b).compareTo(cheieData(a)));
    case OrdineLegislatie.celeMaiVechi:
      rezultat.sort((a, b) => cheieData(a).compareTo(cheieData(b)));
  }
  return rezultat;
}

/// Emitenții din rezultate, cei mai des întâlniți primii (pentru sugestii).
List<String> emitentiDin(List<ActNormativ> acte) {
  final n = <String, int>{};
  for (final a in acte) {
    final e = a.emitent.trim();
    if (e.isNotEmpty) n[e] = (n[e] ?? 0) + 1;
  }
  return (n.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => e.key)
      .toList();
}

// ---------------------------------------------------------------------------
// Legătura cu obiectul dosarului

/// O trimitere la lege găsită în obiectul unui dosar.
class TrimitereLegala {
  final String eticheta;
  final String? tip;
  final CerereLegislatie cerere;

  const TrimitereLegala(this.eticheta, this.cerere, {this.tip});
}

/// Codurile, ca legi (număr/an), ca să găsim actul exact.
final _coduri = <(String, String, String, int)>[
  (
    r'c\.?\s*proc\.?\s*civ|codul? de procedur[aă] civil[aă]|\bncpc\b|\bcpc\b',
    'Codul de procedură civilă',
    '134',
    2010,
  ),
  (
    r'c\.?\s*proc\.?\s*pen|codul? de procedur[aă] penal[aă]|\bncpp\b|\bcpp\b',
    'Codul de procedură penală',
    '135',
    2010,
  ),
  (
    r'c\.?\s*proc\.?\s*fisc|codul? de procedur[aă] fiscal[aă]',
    'Codul de procedură fiscală',
    '207',
    2015,
  ),
  (r'\bc\.?\s*civ\b|codul? civil|\bncc\b', 'Codul civil', '287', 2009),
  (r'\bc\.?\s*pen\b|codul? penal|\bncp\b', 'Codul penal', '286', 2009),
  (r'codul? muncii|\bc\.?\s*muncii', 'Codul muncii', '53', 2003),
  (r'codul? fiscal|\bc\.?\s*fisc\b', 'Codul fiscal', '227', 2015),
  (r'codul? administrativ', 'Codul administrativ', '57', 2019),
].map((c) => (RegExp(c.$1, caseSensitive: false), c.$2, c.$3, c.$4)).toList();

/// Caută în obiectul dosarului legi („Legea nr. 85/2014”, „OUG 195/2002”,
/// „L. 10/2001”) și coduri („art. 712 C.proc.civ.”). Fără nimic de găsit,
/// propune căutarea obiectului ca text.
List<TrimitereLegala> trimiteriDinObiect(String obiect) {
  final o = obiect.trim();
  if (o.isEmpty) return const [];
  final rezultat = <TrimitereLegala>[];
  final vazute = <String>{};

  void adauga(TrimitereLegala t) {
    final k = '${t.cerere.numar}/${t.cerere.an}|${t.cerere.text}';
    if (vazute.add(k)) rezultat.add(t);
  }

  final lege = RegExp(
    r'\b(legea|legii|lege|l\.|o\.?u\.?g\.?|o\.?g\.?|h\.?g\.?|ordonan[țţt]a de urgen[țţt][aă]|ordonan[țţt]a|hot[aă]r[aâ]rea|decretul|decret|ordinul)\s*(?:nr\.?\s*)?(\d{1,5})\s*/\s*(\d{4})',
    caseSensitive: false,
  );
  for (final m in lege.allMatches(o)) {
    final tip = tipDinAbreviere(m.group(1)!) ?? 'LEGE';
    final nr = m.group(2)!;
    final an = int.parse(m.group(3)!);
    adauga(
      TrimitereLegala(
        '${etichetaTip(tip)} $nr/$an',
        CerereLegislatie(numar: nr, an: an),
        tip: tip,
      ),
    );
  }
  for (final c in _coduri) {
    if (c.$1.hasMatch(o)) {
      adauga(
        TrimitereLegala(
          c.$2,
          CerereLegislatie(numar: c.$3, an: c.$4),
          tip: 'LEGE',
        ),
      );
    }
  }
  if (rezultat.isEmpty) {
    // „contestație la executare (art. 712 C.proc.civ.)” are deja cod; altfel
    // căutăm obiectul curățat de paranteze și articole.
    final curat = o
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\bart\.?\s*\d+\S*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (curat.isNotEmpty)
      adauga(TrimitereLegala('„$curat”', CerereLegislatie(text: curat)));
  }
  return rezultat;
}

// ---------------------------------------------------------------------------
// Sugestii în timp ce scrii

enum FelSugestie { actCunoscut, numar, text, titlu, recenta }

class SugestieLegislatie {
  final FelSugestie fel;
  final String titlu;
  final String subtitlu;
  final CerereLegislatie cerere;

  /// Filtrul de tip pus odată cu sugestia (ex. „LEGE” pentru Codul civil).
  final String? tip;

  /// Articolul cerut („codul civil art. 1357”), deschis direct.
  final String? articol;

  /// Deschide singur actul când căutarea găsește potrivirea exactă.
  final bool deschideDirect;

  const SugestieLegislatie(
    this.fel,
    this.titlu,
    this.subtitlu,
    this.cerere, {
    this.tip,
    this.articol,
    this.deschideDirect = false,
  });
}

String _norm(String s) =>
    fataDiacritice(s.toLowerCase())
        .replaceAll(RegExp(r'[^a-z0-9/ ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Desparte „codul civil art. 1357” în „codul civil” și articolul „1357”.
({String rest, String? articol}) extrageArticol(String intrare) {
  final m = RegExp(
    r'[\s,]+(?:art(?:icolul|\.)?|articol)\s*(\d+(?:\s*\^\s*\d+)?)\s*$',
    caseSensitive: false,
  ).firstMatch(intrare);
  if (m == null) return (rest: intrare.trim(), articol: null);
  return (
    rest: intrare.substring(0, m.start).trim(),
    articol: m[1]!.replaceAll(' ', ''),
  );
}

/// Actele cunoscute care se potrivesc cu ce s-a scris: fiecare cuvânt
/// scris trebuie să fie începutul unui cuvânt din nume, alias sau trimitere.
List<ActCunoscut> acteCunoscutePotrivite(String intrare) {
  final cuvinte = _norm(intrare).split(' ').where((c) => c.isNotEmpty).toList();
  if (cuvinte.isEmpty) return const [];
  final rezultat = <(ActCunoscut, int)>[];
  for (final a in acteCunoscute) {
    var cel = 1 << 30;
    for (final forma in [a.nume, ...a.alias, a.trimitere]) {
      final f = _norm(forma);
      final w = f.split(' ');
      final toate = cuvinte.every(
        (c) => w.any((x) => x.startsWith(c)) || f.startsWith(c),
      );
      if (toate) {
        final scor =
            w.length - cuvinte.length + (f.startsWith(cuvinte.first) ? 0 : 5);
        if (scor < cel) cel = scor;
      }
    }
    if (cel < (1 << 30)) rezultat.add((a, cel));
  }
  rezultat.sort((x, y) => x.$2.compareTo(y.$2));
  return rezultat.map((r) => r.$1).toList();
}

CerereLegislatie cerereActCunoscut(ActCunoscut a) => a.numar.isEmpty
    ? const CerereLegislatie(titlu: 'CONSTITUȚIA ROMÂNIEI')
    : CerereLegislatie(numar: a.numar, an: a.an);

List<SugestieLegislatie> sugestii(
  String intrare, {
  List<String> recente = const [],
}) {
  final s = intrare.trim();
  if (s.isEmpty) return const [];
  final (:rest, :articol) = extrageArticol(s);
  final faraArt = articol == null ? '' : ' · art. $articol';
  final r = <SugestieLegislatie>[];

  final nr = CerereLegislatie.dinText(rest);
  if (nr.cerere.numar.isNotEmpty) {
    final tip = nr.tip;
    r.add(
      SugestieLegislatie(
        FelSugestie.numar,
        '${tip == null ? 'Actul' : etichetaTip(tip)} nr. ${nr.cerere.numar}/${nr.cerere.an}$faraArt',
        'Caută actul exact',
        nr.cerere,
        tip: tip,
        articol: articol,
        deschideDirect: tip != null,
      ),
    );
  }

  for (final a in acteCunoscutePotrivite(rest).take(5)) {
    r.add(
      SugestieLegislatie(
        FelSugestie.actCunoscut,
        '${a.nume}$faraArt',
        a.trimitere,
        cerereActCunoscut(a),
        tip: a.tip,
        articol: articol,
        deschideDirect: true,
      ),
    );
  }

  final n = _norm(s);
  for (final x in recente) {
    if (r.length >= 8) break;
    if (_norm(x) != n && _norm(x).contains(n)) {
      final ex = extrageArticol(x);
      final d = CerereLegislatie.dinText(ex.rest);
      r.add(
        SugestieLegislatie(
          FelSugestie.recenta,
          x,
          'Căutare recentă',
          d.cerere,
          tip: d.tip,
          articol: ex.articol,
        ),
      );
    }
  }

  if (nr.cerere.numar.isEmpty && rest.length >= 2) {
    r.add(
      SugestieLegislatie(
        FelSugestie.text,
        '„$rest”',
        'Caută în textul actelor',
        CerereLegislatie(text: rest),
      ),
    );
    r.add(
      SugestieLegislatie(
        FelSugestie.titlu,
        '„$rest”',
        'Caută doar în titlurile actelor',
        CerereLegislatie(titlu: rest),
      ),
    );
  }
  return r;
}

/// Cuvinte prea comune ca să le căutăm singure în titluri.
const _cuvinteComune = {
  'si',
  'de',
  'la',
  'in',
  'din',
  'pentru',
  'privind',
  'cu',
  'al',
  'ale',
  'ai',
  'pe',
  'nr',
  'art',
  'cod',
  'codul',
  'codului',
  'legea',
  'lege',
  'legii',
  'ordonanta',
  'hotararea',
  'decretul',
  'ordinul',
  'decizia',
  'republicata',
  'actul',
  'privire',
  'unor',
  'masuri',
  'aprobarea',
  'modificarea',
  'completarea',
  'romaniei',
};

/// Rădăcina unui cuvânt fără diacritice: „urbanismului” → „urbanism”,
/// „construcțiilor” → „constructi”, „insolvenței” → „insolvent”.
String radacinaCuvant(String w) {
  const sufixe = [
    'urilor',
    'ilor',
    'elor',
    'ului',
    'lor',
    'ul',
    'ei',
    'ii',
    'le',
    'a',
    'e',
    'i',
  ];
  for (final s in sufixe) {
    if (w.endsWith(s) && w.length - s.length >= 4)
      return w.substring(0, w.length - s.length);
  }
  return w;
}

/// Rădăcinile cuvintelor care contează dintr-o căutare.
List<String> radaciniCautare(String interogare) => _norm(interogare)
    .split(' ')
    .where(
      (c) =>
          c.length > 2 &&
          !const {
            'si',
            'de',
            'la',
            'in',
            'din',
            'cu',
            'pe',
            'pentru',
            'privind',
          }.contains(c),
    )
    .map(radacinaCuvant)
    .toList();

bool titluContineToate(String titlu, List<String> radacini) {
  final t = _norm(titlu);
  return radacini.isNotEmpty && radacini.every(t.contains);
}

/// Cuvântul trimis serviciului ca titlu când căutarea are mai multe cuvinte:
/// cel mai lung cuvânt necomun, tăiat înainte de prima diacritică (serviciul
/// face diferența între „ş” și „ș”) și redus la rădăcină. Null când nu e cazul.
String? cuvantPentruTitlu(String interogare) {
  final cuvinte = interogare
      .toLowerCase()
      .split(RegExp(r'[^a-zăâîșşțţ0-9]+'))
      .where((c) => c.isNotEmpty)
      .toList();
  if (cuvinte.length < 2) return null;
  String? ales;
  for (final c in cuvinte) {
    if (_cuvinteComune.contains(fataDiacritice(c))) continue;
    final d = RegExp('[ăâîșşțţ]').firstMatch(c);
    var t = d == null ? c : c.substring(0, d.start);
    if (d == null) t = radacinaCuvant(t);
    if (t.length < 5) continue;
    if (ales == null || t.length > ales.length) ales = t;
  }
  return ales;
}

/// Ordinea „Relevanță”: întâi actele cu toată expresia în titlu, apoi cele
/// cu cele mai multe cuvinte căutate în titlu; legile și codurile înaintea
/// actelor care doar le modifică.
List<ActNormativ> ordoneazaDupaRelevanta(
  List<ActNormativ> acte,
  String interogare,
) {
  final q = _norm(interogare);
  if (q.isEmpty) return acte;
  // Rădăcini: „insolvență” trebuie să prindă și „insolvenței”.
  final cuvinte = radaciniCautare(interogare);
  int scor(ActNormativ a) {
    final t = _norm(a.titlu);
    var s = 0;
    if (t.contains(q)) s += 20;
    if (cuvinte.length > 1 && cuvinte.every(t.contains)) s += 15;
    if (cuvinte.isNotEmpty && t.startsWith(cuvinte.first)) s += 3;
    for (final c in cuvinte) {
      if (t.contains(c)) s += 4;
    }
    if (t.contains('modificarea') ||
        t.contains('completarea') ||
        t.contains('rectificare'))
      s -= 3;
    if (t.contains('abrogarea')) s -= 3;
    if (a.tipAct.startsWith('LEGE') || a.tipAct.startsWith('ORDONANTA')) s += 1;
    return s;
  }

  final indexate = acte.indexed.toList()
    ..sort((x, y) {
      final d = scor(y.$2).compareTo(scor(x.$2));
      return d != 0 ? d : x.$1.compareTo(y.$1);
    });
  return indexate.map((e) => e.$2).toList();
}

/// Potrivirea exactă dintr-o pagină de rezultate (pentru deschidere directă).
ActNormativ? potrivireExacta(
  List<ActNormativ> acte,
  CerereLegislatie c,
  String? tip,
) {
  for (final a in acte) {
    if (tip != null && !_potrivesteTip(a, tip)) continue;
    if (c.numar.isNotEmpty) {
      if (a.numar.trim() != c.numar.trim()) continue;
      if (c.an != null && a.an != c.an) continue;
      return a;
    }
    if (tip == 'CONSTITUTIE') return a;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Acte salvate (favorite)

class ActSalvat {
  final String tipAct;
  final String numar;
  final int? an;
  final String titlu;
  final String denumire;

  const ActSalvat({
    required this.tipAct,
    required this.numar,
    required this.an,
    required this.titlu,
    required this.denumire,
  });

  factory ActSalvat.din(ActNormativ a) => ActSalvat(
    tipAct: a.tipAct,
    numar: a.numar,
    an: a.an,
    titlu: a.titlu,
    denumire: a.denumireScurta,
  );

  String get cheie => '$tipAct|$numar|$an';

  CerereLegislatie get cerere => numar.trim().isEmpty || numar == '0'
      ? CerereLegislatie(titlu: titlu)
      : CerereLegislatie(numar: numar, an: an);

  String? get tip {
    for (final t in tipuriActe) {
      if (fataDiacritice(tipAct).toUpperCase().startsWith(t)) {
        if (t == 'ORDONANTA' && tipAct.contains('URGENT'))
          return 'ORDONANTA DE URGENTA';
        return t;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'tipAct': tipAct,
    'numar': numar,
    'an': an,
    'titlu': titlu,
    'denumire': denumire,
  };

  factory ActSalvat.fromJson(Map<String, dynamic> j) => ActSalvat(
    tipAct: j['tipAct'] as String? ?? '',
    numar: j['numar'] as String? ?? '',
    an: j['an'] as int?,
    titlu: j['titlu'] as String? ?? '',
    denumire: j['denumire'] as String? ?? '',
  );
}

class ActeSalvateService extends ChangeNotifier {
  ActeSalvateService._();
  static final instance = ActeSalvateService._();

  static const _cheie = 'legislatie_acte_salvate';
  List<ActSalvat> _acte = [];
  bool _incarcat = false;

  List<ActSalvat> get acte => List.unmodifiable(_acte);

  Future<void> incarca() async {
    if (_incarcat) return;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_cheie);
      if (s != null) {
        _acte = (jsonDecode(s) as List)
            .map((e) => ActSalvat.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    _incarcat = true;
    notifyListeners();
  }

  /// Pentru teste.
  void reseteaza() {
    _acte = [];
    _incarcat = false;
  }

  bool esteSalvat(ActNormativ a) =>
      _acte.any((x) => x.cheie == ActSalvat.din(a).cheie);

  Future<bool> comuta(ActNormativ a) async {
    final s = ActSalvat.din(a);
    final salvat = esteSalvat(a);
    if (salvat) {
      _acte.removeWhere((x) => x.cheie == s.cheie);
    } else {
      _acte.insert(0, s);
    }
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _cheie,
        jsonEncode(_acte.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
    return !salvat;
  }
}

/// Titlul vine uneori cu antetul paginii lipit: „LEGE nr. 169 ... construcţiilor
/// EMITENT Parlamentul PUBLICAT ÎN Monitorul Oficial nr. 661 ...”.
String titluFaraAntet(String titlu) =>
    titlu.replaceFirst(RegExp(r'\s+EMITENT\b[\s\S]*$'), '').trim();

/// Textul începe uneori cu același antet („... EMITENT PARLAMENTUL ROMÂNIEI
/// Publicat în MONITORUL OFICIAL nr. 661 din 10 august 2026”), care e deja
/// afișat frumos deasupra; îl scoatem.
String textFaraAntet(String text) {
  final m = RegExp(
    r'^[\s\S]{0,700}?\bEMITENT\b[\s\S]{0,300}?MONITORUL OFICIAL\s+(?:nr\.\s*)?\d+\s+din\s+\d{1,2}\s+\S+\s+\d{4}\s*',
    caseSensitive: false,
  ).firstMatch(text);
  return m == null ? text : text.substring(m.end).trim();
}

/// Legile care aprobă un cod („Legea 169/2026 privind Codul amenajării
/// teritoriului...”) au codul ca anexă, publicată pe portal ca act separat;
/// textul legii are doar câteva rânduri. Întoarce numele codului.
String? numeCodAnexat(ActNormativ a) {
  final m = RegExp(
    r'\b(?:privind|pentru aprobarea|de aprobare a)\s+(Codul(?:ui)?\s+.+)$',
    caseSensitive: false,
  ).firstMatch(titluCurat(a.titlu));
  if (m == null) return null;
  final articole = RegExp(r'\b(?:Articolul|Art\.)\s*\d+')
      .allMatches(a.text)
      .length;
  if (articole > 5) return null;
  final nume = m[1]!
      .replaceFirst(RegExp(r'^Codului', caseSensitive: false), 'Codul')
      .replaceFirst(RegExp(r'\s*\(.*$'), '')
      .trim();
  return _majusculaInitiala(nume);
}

/// Codul anexat, din rezultatele unei căutări după numele lui.
ActNormativ? alegeCodAnexat(
  List<ActNormativ> rezultate,
  ActNormativ lege,
  String nume,
) {
  final radacini = radaciniCautare(nume);
  final potrivite = rezultate
      .where(
        (a) => a.cheie != lege.cheie && titluContineToate(a.titlu, radacini),
      )
      .toList();
  return potrivite.where((a) => _norm(a.titlu).startsWith('cod')).firstOrNull ??
      potrivite.where((a) => !_norm(a.titlu).startsWith('lege')).firstOrNull;
}

/// Titlul fără marcajele portalului („(**republicat**)” → „(republicat)”).
String titluCurat(String titlu) =>
    titlu.replaceAll(RegExp(r'\*+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Titlul arătat în cardul de rezultat, fără majusculele și fără repetarea
/// tipului și numărului (care sunt deja în eticheta colorată):
/// „LEGE nr. 7 din 13 martie 1996 a cadastrului...” devine
/// „Legea cadastrului...” cu „din 13 martie 1996” dedesubt;
/// „CODUL CIVIL din 17 iulie 2009 (**republicat**)” devine „Codul civil”
/// cu „din 17 iulie 2009 · republicat”.
({String principal, String secundar}) titluPrezentare(ActNormativ a) {
  var t = titluCurat(a.titlu);
  if (t.isEmpty) return (principal: a.denumireScurta, secundar: '');

  final note = <String>[];
  t = t.replaceAllMapped(RegExp(r'\s*\(([^)]{3,40})\)\s*$'), (m) {
    note.add(m[1]!.toLowerCase());
    return '';
  });

  String? data;
  final d = RegExp(r'\bdin (\d{1,2} [a-zA-ZăâîșțşţĂÂÎȘȚ]+ \d{4})\b')
      .firstMatch(t);
  if (d != null) {
    data = 'din ${d[1]!.toLowerCase()}';
    t = (t.substring(0, d.start) + t.substring(d.end))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Tipul și numărul de la început.
  final tip = RegExp(
    r'^(LEGEA?|ORDONAN[ȚŢT][AĂ] DE URGEN[ȚŢT][AĂ]|ORDONAN[ȚŢT][AĂ]|HOT[AĂ]R[ÂA]REA?|DECRETUL|DECRET|ORDINUL|ORDIN|DECIZIA|DECIZIE)'
    r'(\s+nr\.?\s*[\w./-]+)?\s*',
    caseSensitive: false,
  ).firstMatch(t);
  var principal = t;
  if (tip != null && tip.end < t.length) {
    var rest = t.substring(tip.end).trim();
    rest = rest.replaceFirst(RegExp(r'^a\s+', caseSensitive: false), '');
    final articulat = switch (fataDiacritice(tip[1]!).toUpperCase()) {
      final x when x.startsWith('ORDONANTA DE') => 'Ordonanța de urgență',
      final x when x.startsWith('ORDONANTA') => 'Ordonanța',
      final x when x.startsWith('HOTAR') => 'Hotărârea',
      final x when x.startsWith('DECRET') => 'Decretul',
      final x when x.startsWith('ORDIN') => 'Ordinul',
      final x when x.startsWith('DECIZI') => 'Decizia',
      _ => 'Legea',
    };
    principal = '$articulat $rest';
  } else if (t == t.toUpperCase()) {
    final mic = t.toLowerCase();
    principal = mic.isEmpty ? t : mic[0].toUpperCase() + mic.substring(1);
  }

  // Actele cunoscute își păstrează numele scurt („Codul civil”).
  for (final c in acteCunoscute) {
    if (c.numar.isNotEmpty &&
        c.numar == a.numar.trim() &&
        c.an == a.an &&
        c.nume.startsWith('Codul')) {
      principal = c.nume;
    }
  }
  if (principal.length > 1)
    principal = principal[0].toUpperCase() + principal.substring(1);

  return (principal: principal, secundar: [?data, ...note].join(' · '));
}
