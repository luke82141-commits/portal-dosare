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
    final dinTitlu = RegExp(
      r'\bdin\s+\d{1,2}\s+[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+\s+((?:18|19|20)\d{2})',
    ).firstMatch(titlu);
    if (dinTitlu != null) return int.parse(dinTitlu.group(1)!);
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

  /// Actul prin care a fost aprobat (la regulamente, norme, anexe):
  /// nota „Aprobat prin ORDINUL nr. 600 din 8 februarie 2023” din antet.
  AprobareAct? get aprobatPrin => aprobareDinText(text);

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

/// Actul care a aprobat un regulament / o normă / o anexă.
class AprobareAct {
  /// „Ordinul”, „Hotărârea Guvernului”, „Decizia”.
  final String tip;
  final String numar;

  /// „8 februarie 2023”, sau null când nota dă doar anul („nr. 273/1994”).
  final String? data;
  final int? an;

  /// Id-ul actului pe portal, când îl știm (din căutare).
  final String? idAct;

  const AprobareAct({
    required this.tip,
    required this.numar,
    this.data,
    this.an,
    this.idAct,
  });

  /// „Ordinul nr. 600 din 8 februarie 2023”.
  String get denumire => data != null
      ? '$tip nr. $numar din $data'
      : (an != null ? '$tip nr. $numar/$an' : '$tip nr. $numar');

  /// „Ordinul nr. 600/2023”.
  String get scurta => an != null ? '$tip nr. $numar/$an' : '$tip nr. $numar';
}

final _reAprobare = RegExp(
  r'aprobat[ăe]?\s+prin\s+([A-Za-zĂÂÎȘŞȚŢăâîșşțţ][A-Za-zĂÂÎȘŞȚŢăâîșşțţ\s.,-]{1,120}?)\s+'
  r'nr\.\s*([\d.]+(?:\s*/\s*[\w.]+)?)'
  r'(?:\s+din\s+(\d{1,2}\s+[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+\s+(?:18|19|20)\d{2}))?',
  caseSensitive: false,
);

/// Nota de aprobare din primele rânduri ale textului (după antet). Ignoră
/// trimiterile din titlu („…, aprobat prin Ordinul nr. 133/2021 EMITENT”),
/// care țin de actul modificat, nu de cel citit.
AprobareAct? aprobareDinText(String text) {
  if (text.isEmpty) return null;
  final cap = text.length > 3000 ? text.substring(0, 3000) : text;
  // Doar nota de sub antet („Notă: Aprobat prin …”) sau un text care începe
  // chiar cu „Aprobat prin”; în titluri și în corp, „aprobat prin” e o
  // trimitere la alt act.
  final m = _reAprobare.allMatches(cap).where((m) {
    final inainte = cap.substring(m.start < 40 ? 0 : m.start - 40, m.start);
    return m.start < 15 ||
        RegExp(
          r'Not[ăa]\W*$',
          caseSensitive: false,
        ).hasMatch(inainte.trimRight());
  }).firstOrNull;
  if (m == null) return null;
  var tip = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  tip = tip.replaceAll(RegExp(r'[,.]+$'), '');
  tip = tip
      .split(' ')
      .map(
        (w) => w == w.toUpperCase() && w.length > 1 ? _majusculaInitiala(w) : w,
      )
      .join(' ');
  var numar = m.group(2)!.replaceAll(' ', '');
  int? an;
  final slash = RegExp(r'^([\d.]+)/((?:18|19|20)\d{2})$').firstMatch(numar);
  if (slash != null) {
    numar = slash.group(1)!;
    an = int.parse(slash.group(2)!);
  }
  numar = numar.replaceAll(RegExp(r'\.$'), '');
  final data = m.group(3)?.replaceAll(RegExp(r'\s+'), ' ');
  if (data != null) an = int.tryParse(data.split(' ').last);
  return AprobareAct(tip: tip, numar: numar, data: data, an: an);
}

/// Tipurile de acte care nu se emit singure, ci se aprobă prin alt act.
bool seAproba(ActNormativ a) {
  final t = a.tipAct.toUpperCase();
  return RegExp(
    r'^(REGULAMENT|NORM|METODOLOGI|ANEX|INSTRUC|NORMATIV|PROCEDUR|STATUT|GHID|PRECIZ|PLAN|PROGRAM|STRATEGI|CONDI|CRITERI|NOMENCLATOR|LIST)',
  ).hasMatch(t);
}

final _reDataTitlu = RegExp(
  r'\bdin\s+(\d{1,2})\s+([a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+)\s+((?:18|19|20)\d{2})',
);

String? _dataDinTitlu(String titlu) {
  final m = _reDataTitlu.firstMatch(titlu);
  if (m == null) return null;
  return '${int.parse(m.group(1)!)} ${m.group(2)!.toLowerCase()} ${m.group(3)}';
}

/// „MONITORUL OFICIAL nr. 223 din 9 aprilie 2010” → „223|9 aprilie 2010”.
String? _monitor(String publicatie) {
  final m = RegExp(
    r'nr\.\s*([\d.]+)\s*(?:bis\s*)?din\s+(\d{1,2})\s+([a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+)\s+(\d{4})',
    caseSensitive: false,
  ).firstMatch(publicatie);
  if (m == null) return null;
  return '${m.group(1)!.replaceAll('.', '')}|${int.parse(m.group(2)!)} ${m.group(3)!.toLowerCase()} ${m.group(4)}';
}

/// Căutarea actului de aprobare: „aprob*” + primele cuvinte din denumirea
/// regulamentului („regulament* avizare* verificare* recept*”).
CerereLegislatie? cerereAprobare(ActNormativ act) {
  final titlu = titluCurat(act.titlu);
  final m = _reDataTitlu.firstMatch(titlu);
  final descriere = m == null ? titlu : titlu.substring(m.end);
  final tip = act.tipAct.split(' ').first.toLowerCase();
  final termeni = interogarePrefixe(descriere)
      .split(' ')
      .where((t) => t.isNotEmpty)
      .take(4)
      .toList();
  if (termeni.isEmpty) return null;
  final cap = tip.length > 4 ? '${radacinaCuvant(tip)}*' : '$tip*';
  return CerereLegislatie(
    titlu: ['aprob*', if (!termeni.contains(cap)) cap, ...termeni].join(' '),
  );
}

/// Actul de aprobare dintre rezultate: altul decât [act], „…aprobarea…”
/// în titlu, din aceeași zi sau publicat în același Monitor Oficial.
AprobareAct? aprobareDinRezultate(ActNormativ act, List<ActNormativ> acte) {
  final zi = _dataDinTitlu(titluCurat(act.titlu));
  final mo = _monitor(act.publicatie);
  for (final b in acte) {
    if (b.cheie == act.cheie || seAproba(b)) continue;
    final t = titluCurat(b.titlu);
    if (!RegExp(r'aprob', caseSensitive: false).hasMatch(t)) continue;
    final ziB = _dataDinTitlu(t);
    final moB = _monitor(b.publicatie);
    final aceeasiZi = zi != null && ziB == zi;
    final acelasiMo = mo != null && moB == mo;
    if (!aceeasiZi && !acelasiMo) continue;
    final nr = b.numar.trim();
    if (nr.isEmpty || nr == '0') continue;
    return AprobareAct(
      tip: articulat(b.tipAct),
      numar: numarCuPunct(nr),
      data: ziB,
      an: b.an,
      idAct: RegExp(r'(\d+)$').firstMatch(b.linkHtml)?.group(1),
    );
  }
  return null;
}

/// „ORDIN” → „Ordinul”, „HOTĂRÂRE” → „Hotărârea”.
String articulat(String tipAct) {
  final t = tipAct.toUpperCase().trim();
  const m = {
    'ORDIN': 'Ordinul',
    'HOTĂRÂRE': 'Hotărârea',
    'LEGE': 'Legea',
    'DECIZIE': 'Decizia',
    'DECRET': 'Decretul',
    'ORDONANȚĂ': 'Ordonanța',
    'ORDONANȚĂ DE URGENȚĂ': 'Ordonanța de urgență',
    'DISPOZIȚIE': 'Dispoziția',
    'INSTRUCȚIUNE': 'Instrucțiunea',
  };
  return m[t] ?? etichetaTip(tipAct);
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

  /// Tipul actului căutat după număr („LEGE”), ca să-l găsim după titlu.
  final String? tip;

  /// Anul intrării în vigoare, când diferă de anul actului (Codul civil
  /// 287/2009 a intrat în vigoare în 2011); serviciul filtrează după el.
  final int? anVigoare;

  /// Cuvintele de după număr („legea 307 incendii” → „incendii”): actele
  /// cu numărul cerut care le au în titlu vin primele.
  final String cuvinte;

  const CerereLegislatie({
    this.text = '',
    this.titlu = '',
    this.numar = '',
    this.an,
    this.tip,
    this.anVigoare,
    this.cuvinte = '',
  });

  bool get goala =>
      text.trim().isEmpty && titlu.trim().isEmpty && numar.trim().isEmpty;

  /// Interpretează ce scrie omul în bara de căutare:
  /// „legea 85/2014”, „oug 195/2002”, „85/2014” → număr + an (+ tip);
  /// orice altceva → text liber.
  static ({CerereLegislatie cerere, String? tip}) dinText(String intrare) {
    final s = intrare.trim();
    final m = RegExp(
      r'^(?:(?<tip>[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ\. ]+?)\s*(?:nr\.?\s*)?)?(?<nr>\d{1,5})'
      r'(?:\s*/\s*|\s+din\s+|\s+)(?<an>(?:18|19|20)\d{2})$',
      caseSensitive: false,
    ).firstMatch(s);
    final tipBrut = m?.namedGroup('tip')?.trim() ?? '';
    if (m != null && tipBrut.isNotEmpty && tipDinAbreviere(tipBrut) == null) {
      // „apararea impotriva incendiilor 307 2006”: cuvintele nu sunt un tip.
      final libera = _dinCuvinte(s);
      if (libera != null) return libera;
    }
    if (m != null) {
      final tip = tipDinAbreviere(m.namedGroup('tip') ?? '');
      return (
        cerere: CerereLegislatie(
          numar: m.namedGroup('nr')!,
          an: int.parse(m.namedGroup('an')!),
          tip: tip,
        ),
        tip: tip,
      );
    }
    // „legea 307”, „oug nr. 195”: tipul și numărul, din toți anii.
    final f = RegExp(
      r'^(?<tip>[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ\. ]+?)\s*(?:nr\.?\s*)?(?<nr>\d{1,5})$',
      caseSensitive: false,
    ).firstMatch(s);
    final tipFaraAn = f == null ? null : tipDinAbreviere(f.namedGroup('tip')!);
    if (tipFaraAn != null) {
      return (
        cerere: CerereLegislatie(numar: f!.namedGroup('nr')!, tip: tipFaraAn),
        tip: tipFaraAn,
      );
    }
    // „legea 307 incendii”, „legea 307/2006 incendii”: tip, număr, poate an,
    // apoi cuvinte din titlu.
    final g = RegExp(
      r'^(?<tip>[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ\. ]+?)\s*(?:nr\.?\s*)?(?<nr>\d{1,5})'
      r'(?:\s*/\s*(?<an>(?:18|19|20)\d{2})|\s+din\s+(?<an2>(?:18|19|20)\d{2}))?'
      r'\s+(?<rest>[^\d\s][\s\S]*)$',
      caseSensitive: false,
    ).firstMatch(s);
    final tipCuvinte = g == null ? null : tipDinAbreviere(g.namedGroup('tip')!);
    if (tipCuvinte != null) {
      final an = g!.namedGroup('an') ?? g.namedGroup('an2');
      return (
        cerere: CerereLegislatie(
          numar: g.namedGroup('nr')!,
          an: an == null ? null : int.parse(an),
          tip: tipCuvinte,
          cuvinte: g.namedGroup('rest')!.trim(),
        ),
        tip: tipCuvinte,
      );
    }
    final libera = _dinCuvinte(s);
    if (libera != null) return libera;
    return (cerere: CerereLegislatie(text: s), tip: null);
  }

  /// Ordine liberă: „incendii legea 307”, „307 2006 incendii”, „hg 1 2020”.
  /// Caută un număr de act oriunde în frază (nu după „art.”/„alin.”), tipul
  /// și anul, dacă apar; restul cuvintelor ordonează rezultatele.
  static ({CerereLegislatie cerere, String? tip})? _dinCuvinte(String s) {
    var t = fataDiacritice(s.toLowerCase());
    String? tip;
    final oug = RegExp(r'\bordonant[ae]i? de urgenta\b|\bo\.?u\.?g\.?(?=\s|$)');
    if (oug.hasMatch(t)) {
      tip = 'ORDONANTA DE URGENTA';
      t = t.replaceAll(oug, ' ');
    }
    final cuvinte = t
        .split(RegExp(r'[\s,;]+'))
        .where((c) => c.isNotEmpty)
        .toList();
    final reNumar = RegExp(
      r'^(?:nr\.?)?(\d{1,5})(?:/((?:18|19|20)\d{2}))?\.?$',
    );
    final reAn = RegExp(r'^(18|19|20)\d{2}$');
    final numere = [
      for (var i = 0; i < cuvinte.length; i++)
        if (reNumar.hasMatch(cuvinte[i]) &&
            !RegExp(r'^(art|alin|lit|pct|articolul|alineatul)\.?$')
                .hasMatch(i > 0 ? cuvinte[i - 1] : ''))
          i,
    ];
    if (numere.isEmpty) return null;
    // Un an singur („codul fiscal 2015”) nu e număr de act.
    final iNumar = numere.firstWhere(
      (i) =>
          !reAn.hasMatch(reNumar.firstMatch(cuvinte[i])![1]!) ||
          reNumar.firstMatch(cuvinte[i])![2] != null,
      orElse: () => numere.length > 1 ? numere.first : -1,
    );
    if (iNumar < 0) return null;
    // „codul civil 2”: fără tip și fără an, un număr scurt e prea vag.
    final faraAn =
        reNumar.firstMatch(cuvinte[iNumar])![2] == null &&
        !cuvinte.any(reAn.hasMatch);
    if (tip == null &&
        faraAn &&
        reNumar.firstMatch(cuvinte[iNumar])![1]!.length < 3 &&
        !cuvinte.any(
          (c) => tipDinAbreviere(c) != null && tipDinAbreviere(c) != 'COD',
        )) {
      return null;
    }
    final m = reNumar.firstMatch(cuvinte[iNumar])!;
    final numar = m[1]!;
    int? an = m[2] == null ? null : int.parse(m[2]!);
    final rest = <String>[];
    for (var i = 0; i < cuvinte.length; i++) {
      if (i == iNumar) continue;
      final c = cuvinte[i];
      if (an == null && reAn.hasMatch(c)) {
        an = int.parse(c);
        continue;
      }
      if (c == 'nr' || c == 'nr.' || c == 'din') continue;
      final tipCuvant = tipDinAbreviere(c);
      if (tip == null && tipCuvant != null && tipCuvant != 'COD') {
        tip = tipCuvant;
        continue;
      }
      if (!_cuvinteComune.contains(c)) rest.add(c);
    }
    return (
      cerere: CerereLegislatie(
        numar: numar,
        an: an,
        tip: tip,
        cuvinte: rest.join(' '),
      ),
      tip: tip,
    );
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
  'COD',
  'REGULAMENT',
  'NORMA',
  'CONSTITUTIE',
];

/// Eticheta afișată pentru un tip de act.
String etichetaTip(String tip) =>
    switch (fataDiacritice(tip).toUpperCase().trim()) {
      'LEGE' => 'Lege',
      'COD' || 'CODUL CIVIL' => 'Cod',
      'CODUL DE ETICA' => 'Cod de etică',
      'INSTRUCTIUNI' => 'Instrucțiuni',
      'PROCEDURA' => 'Procedură',
      'RECTIFICARE' => 'Rectificare',
      'COMUNICAT' => 'Comunicat',
      'STATUT' => 'Statut',
      'ORDONANTA DE URGENTA' => 'OUG',
      'ORDONANTA' => 'Ordonanță',
      'HOTARARE' => 'Hotărâre',
      'DECRET' => 'Decret',
      'ORDIN' => 'Ordin',
      'DECIZIE' => 'Decizie',
      'REGULAMENT' => 'Regulament',
      'NORMA' => 'Normă',
      'CONSTITUTIE' => 'Constituție',
      final t => _majusculaInitiala(t),
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
  if (t == 'COD' || t == 'CODUL') return 'COD';
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

  /// Serviciul întoarce cel mult 10 acte pe pagină, oricât i-am cere.
  static const int rezultatePePagina = 10;

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
  /// Serviciul are câteva ciudățenii (verificate pe 15.11.2026):
  /// - întoarce cel mult 10 acte pe pagină, în ordinea datei intrării în
  ///   vigoare, de la cele vechi spre cele noi;
  /// - „anul” filtrează după data intrării în vigoare, nu după anul actului
  ///   (Codul civil, Legea 287/2009, are 2011);
  /// - titlul se caută ca expresie exactă: „codul urbanismului” nu găsește
  ///   „Codul amenajării teritoriului, urbanismului și construcțiilor”.
  /// De aceea actele cu număr le căutăm după titlu („LEGE nr. 307 din”), iar
  /// căutările din mai multe cuvinte le completăm cu titlurile care au
  /// cuvintele cele mai rare, păstrându-le pe cele care le au pe toate.
  ///
  /// Cu [simplu] se face doar cererea dată, fără completări.
  Future<PaginaLegislatie> cauta(
    CerereLegislatie cerere, {
    int pagina = 1,
    bool simplu = false,
  }) async {
    if (cerere.goala) return const PaginaLegislatie([], false);
    if (simplu) return _cautaPagina(cerere, pagina);
    if (cerere.numar.trim().isNotEmpty) {
      if (pagina > 1) return const PaginaLegislatie([], false);
      return _cautaDupaNumar(cerere);
    }
    final expresie = cerere.text.isNotEmpty ? cerere.text : cerere.titlu;
    final prefixe = cerere.an == null ? interogarePrefixe(expresie) : '';
    if (prefixe.isEmpty) return _cautaPagina(cerere, pagina);

    // Serviciul caută fraza exactă, cuvânt întreg: „regulament receptii” nu
    // găsește „Regulamentul de recepție”. Cu „regulament* recept*” însă
    // caută fiecare rădăcină separat, în orice ordine (verificat 15.11.2026).
    // Titlurile cu toate rădăcinile vin primele; fraza exactă completează.
    final dinTitluri = <ActNormativ>[];
    var maiSunt = false;
    Object? eroare;
    try {
      final paginiPrefix = pagina <= 1 ? [1, 2] : [pagina + 1];
      for (final p in paginiPrefix) {
        final r = await _cautaPagina(CerereLegislatie(titlu: prefixe), p);
        dinTitluri.addAll(r.acte);
        maiSunt = r.maiSunt;
        if (!r.maiSunt) break;
      }
      // Niciun titlu cu toate cuvintele: încercăm fără câte unul.
      if (pagina <= 1 && dinTitluri.isEmpty) {
        for (final varianta in varianteFaraUnCuvant(prefixe)) {
          final r = await _cautaPagina(CerereLegislatie(titlu: varianta), 1);
          dinTitluri.addAll(r.acte);
          if (dinTitluri.length >= 10) break;
        }
      }
    } catch (e) {
      eroare = e;
    }
    PaginaLegislatie? principala;
    if (pagina <= 1) {
      try {
        principala = await _cautaPagina(cerere, 1);
      } catch (e) {
        eroare ??= e;
      }
    }
    if (dinTitluri.isEmpty && principala == null) throw eroare!;
    final vazute = <String>{};
    final acte = [
      ...dinTitluri,
      ...?principala?.acte,
    ].where((a) => vazute.add(a.cheie)).toList();
    return PaginaLegislatie(
      ordoneazaDupaRelevanta(acte, expresie),
      maiSunt || (principala?.maiSunt ?? false),
    );
  }

  /// „Legea 307/2006”, „legea 307”: întâi după titlu („LEGE nr. 307 din”),
  /// an cu an de la anul actului (serviciul filtrează după anul intrării în
  /// vigoare); dacă nu iese nimic, după număr. Actele potrivite vin primele.
  Future<PaginaLegislatie> _cautaDupaNumar(CerereLegislatie c) async {
    final n = c.numar.replaceAll('.', '').trim();
    final titlu = titluPentruNumar(n, c.tip);
    bool potrivit(ActNormativ a) =>
        a.numar.replaceAll('.', '').trim() == n &&
        (c.an == null || a.an == c.an) &&
        (c.tip == null || _potrivesteTip(a, c.tip!));

    final toate = <ActNormativ>[];
    final vazute = <String>{};
    void adauga(List<ActNormativ> acte) =>
        toate.addAll(acte.where((a) => vazute.add(a.cheie)));
    bool gasit() => toate.any(potrivit);

    final radacini = radaciniCautare(c.cuvinte);
    int cuCuvinte(ActNormativ a) =>
        radacini.isNotEmpty && titluContineToate(a.titlu, radacini) ? 1 : 0;
    bool gasitCuCuvinte() => toate.any((a) => potrivit(a) && cuCuvinte(a) == 1);

    // „1045 artificii”: numărul și cuvintele în aceeași căutare pe titlu
    // („nr. 1.045 din artific*”), ca să nu răsfoim toate actele cu nr. 1045.
    final prefixe = interogarePrefixe(c.cuvinte)
        .split(' ')
        .where((t) => t.endsWith('*'))
        .join(' ');
    if (prefixe.isNotEmpty) {
      final cuPunct = numarCuPunct(n);
      final variante = <String>{
        '$titlu $prefixe',
        '$cuPunct $prefixe',
        '$n $prefixe',
      };
      for (final v in variante) {
        try {
          final r = await _cautaPagina(CerereLegislatie(titlu: v, an: c.an), 1);
          adauga(r.acte);
        } catch (_) {}
        if (gasitCuCuvinte()) break;
      }
    }

    // La căutarea după titlu, anul e o limită de jos pentru data intrării în
    // vigoare (care nu e niciodată înaintea actului), iar ordinea e
    // amestecată: răsfoim câteva pagini până dăm de act.
    for (
      var p = 1;
      p <= 5 && !(c.an != null && gasit()) && !gasitCuCuvinte();
      p++
    ) {
      final r = await _cautaPagina(CerereLegislatie(titlu: titlu, an: c.an), p);
      adauga(r.acte);
      if (!r.maiSunt) break;
    }
    // Rezervă: după număr, cum cere serviciul.
    for (var p = 1; p <= 2 && !gasit() && !gasitCuCuvinte(); p++) {
      final r = await _cautaPagina(CerereLegislatie(numar: n, an: c.an), p);
      adauga(r.acte);
      if (!r.maiSunt) break;
    }

    final potrivite = toate.where(potrivit).toList()
      ..sort((x, y) {
        final w = cuCuvinte(y).compareTo(cuCuvinte(x));
        if (w != 0) return w;
        // Cele mai noi întâi; la același act, forma republicată.
        final a = (y.an ?? 0).compareTo(x.an ?? 0);
        if (a != 0) return a;
        final r = _eRepublicat(y).compareTo(_eRepublicat(x));
        if (r != 0) return r;
        return (y.dataVigoare ?? DateTime(0)).compareTo(
          x.dataVigoare ?? DateTime(0),
        );
      });
    // Concis: când actul cu numărul și cuvintele căutate există, doar el
    // (și formele lui) apar, fără celelalte acte cu același număr.
    if (gasitCuCuvinte()) {
      return PaginaLegislatie(
        potrivite.where((a) => cuCuvinte(a) == 1).toList(),
        false,
      );
    }
    final restul = toate.where((a) => !potrivit(a));
    return PaginaLegislatie([...potrivite, ...restul], false);
  }

  final _aprobari = <String, Future<AprobareAct?>>{};

  /// Prin ce act a fost aprobat un regulament / o normă. Întâi nota din
  /// text; la actele mai vechi, fără notă, căutăm ordinul / hotărârea „pentru
  /// aprobarea Regulamentului …” din aceeași zi și același Monitor Oficial.
  Future<AprobareAct?> aprobareAct(ActNormativ act) {
    final din = act.aprobatPrin;
    if (din != null) return Future.value(din);
    if (!seAproba(act)) return Future.value(null);
    return _aprobari.putIfAbsent(act.cheie, () async {
      try {
        final cerere = cerereAprobare(act);
        if (cerere == null) return null;
        final r = await _cautaPagina(cerere, 1);
        return aprobareDinRezultate(act, r.acte);
      } catch (_) {
        _aprobari.remove(act.cheie);
        return null;
      }
    });
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
      tipAct: fataDiacritice(text(e, 'TipAct')).toUpperCase().trim(),
      numar: text(e, 'Numar'),
      dataVigoare: _data(text(e, 'DataVigoare')),
      titlu: titluFaraAntet(text(e, 'Titlu')),
      emitent: emitentReparat(text(e, 'Emitent')),
      publicatie: publicatieCompleta(
        text(e, 'Publicatie'),
        text(e, 'Titlu'),
        text(e, 'Text'),
      ),
      linkHtml: link,
      text: textFaraAntet(curataText(text(e, 'Text'))),
    );
  }).toList();
}

final _reMonitorInAntet = RegExp(
  r'Monitorul\s+Oficial\b.{0,40}?nr\.\s*[\d.]+(?:\s*bis)?\s*din\s+\d{1,2}\s+'
  r'[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+\s+\d{4}',
  caseSensitive: false,
  dotAll: true,
);

/// Câmpul Publicatie vine adesea doar ca „Monitorul Oficial” (verificat
/// 26.11.2026); numărul și ziua sunt în antetul titlului („PUBLICAT ÎN
/// Monitorul Oficial nr. 979 din 25 noiembrie 2026”) sau al textului.
/// Le luăm de acolo, înainte ca antetul să fie scos.
String publicatieCompleta(String publicatie, String titluBrut, String textBrut) {
  if (RegExp(r'nr\.\s*[\d.]+', caseSensitive: false).hasMatch(publicatie)) {
    return publicatie;
  }
  for (final sursa in [titluBrut, textBrut]) {
    final m = _reMonitorInAntet.firstMatch(sursa);
    if (m != null) return m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  return publicatie;
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
  bool potriveste(String s) {
    final t = fataDiacritice(s).toUpperCase().trim();
    if (tip == 'ORDONANTA') {
      return t.startsWith('ORDONANTA') && !t.startsWith('ORDONANTA DE URGENTA');
    }
    if (tip == 'ORDONANTA DE URGENTA')
      return t.startsWith(tip) || t.startsWith('OUG');
    return t.startsWith(tip);
  }

  // Tipul trimis de serviciu nu e mereu cel așteptat; titlul („LEGE nr. 307
  // din 2006 ...”) spune sigur ce act e.
  final tipCunoscut = tipuriActe.any(
    (k) => fataDiacritice(a.tipAct).toUpperCase().trim().startsWith(k),
  );
  return tipCunoscut ? potriveste(a.tipAct) : potriveste(a.titlu);
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
    // Anul scoate Constituția din 1923 (anul e limita de jos a intrării în vigoare).
    ? const CerereLegislatie(titlu: 'CONSTITUȚIA ROMÂNIEI', an: 1991)
    : CerereLegislatie(
        numar: a.numar,
        an: a.an,
        tip: a.tip,
        anVigoare: a.anVigoare,
      );

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
        '${tip == null ? 'Actul' : etichetaTip(tip)} nr. ${nr.cerere.numar}'
        '${nr.cerere.an == null ? '' : '/${nr.cerere.an}'}'
        '${nr.cerere.cuvinte.isEmpty ? '' : ' · ${nr.cerere.cuvinte}'}$faraArt',
        nr.cerere.an == null
            ? 'Toate actele cu acest număr, din toți anii'
            : 'Caută actul exact',
        nr.cerere,
        tip: tip,
        articol: articol,
        deschideDirect:
            tip != null &&
            (nr.cerere.an != null || nr.cerere.cuvinte.isNotEmpty),
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

/// Cuvinte care, scrise singure, strică interogarea serviciului (Solr).
const _cuvinteDeLegatura = {
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
  'privire',
  'unor',
  'prin',
  'sau',
  'care',
};
const _tipuriScrise = {
  'lege',
  'legea',
  'legii',
  'legi',
  'l',
  'hg',
  'og',
  'oug',
  'hotarare',
  'hotararea',
  'hotararii',
  'hotarire',
  'hotarirea',
  'ordonanta',
  'ordonantei',
  'decret',
  'decretul',
  'ordin',
  'ordinul',
  'decizie',
  'decizia',
};
const _operatori = {'and', 'or', 'not', 'near', 'to'};

/// „regulament receptii” → „regulament* recept*”: rădăcina fiecărui cuvânt
/// care contează, cu „*” la final, ca serviciul să găsească orice formă,
/// în orice ordine. Numerele rămân întregi. Gol când nu e nimic de căutat.
String interogarePrefixe(String interogare) {
  final termeni = <String>[];
  for (final c in _norm(interogare).replaceAll('/', ' ').split(' ')) {
    if (c.isEmpty || _operatori.contains(c)) continue;
    if (RegExp(r'^\d+$').hasMatch(c)) {
      if (!termeni.contains(c)) termeni.add(c);
      continue;
    }
    if (c.length < 3 || _cuvinteDeLegatura.contains(c)) continue;
    // Tipul actului e scris altfel în titlu („LEGE”, „HOTĂRÂRE”).
    if (_tipuriScrise.contains(c)) continue;
    final r = c.startsWith('cod') ? 'cod*' : '${radacinaCuvant(c)}*';
    if (!termeni.contains(r)) termeni.add(r);
  }
  return termeni.take(6).join(' ');
}

/// „a* b* c*” → „b* c*”, „a* c*”, „a* b*”: întâi fără cuvântul cel mai scurt,
/// care e de obicei cel mai puțin specific.
List<String> varianteFaraUnCuvant(String prefixe) {
  final t = prefixe.split(' ');
  if (t.length < 2) return const [];
  final ordine = List.generate(t.length, (i) => i)
    ..sort((x, y) => t[x].length.compareTo(t[y].length));
  return [
    for (final i in ordine) [...t.sublist(0, i), ...t.sublist(i + 1)].join(' '),
  ];
}

/// Cuvintele căutate separat în titluri când căutarea are mai multe cuvinte:
/// cele mai lungi două cuvinte necomune, așa cum au fost scrise (serviciul
/// nu ține cont de diacritice și majuscule). Gol când nu e cazul.
List<String> cuvinteCheie(String interogare) {
  final rare =
      interogare
          .toLowerCase()
          .split(RegExp(r'[^a-zăâîșşțţ0-9]+'))
          .where(
            (c) => c.length >= 4 && !_cuvinteComune.contains(fataDiacritice(c)),
          )
          .toSet()
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  return rare.take(3).toList();
}

/// Titlul după care căutăm un act cu număr: „LEGE nr. 307 din”. La tipurile
/// scrise în mai multe feluri („HOTĂRÎRE”, „ORDINUL”, „DECIZIA”) doar
/// „nr. 307 din”, iar tipul îl verificăm în aplicație.
String titluPentruNumar(String numar, String? tip) {
  final prefix = switch (tip) {
    'LEGE' => 'LEGE ',
    'ORDONANTA DE URGENTA' => 'URGENTA ',
    'ORDONANTA' => 'ORDONANTA ',
    'DECRET' => 'DECRET ',
    _ => '',
  };
  // Titlurile scriu numerele mari cu punct: „DECRET nr. 1.212 din”.
  final cuPunct = numarCuPunct(numar);
  return '${prefix}nr. $cuPunct din';
}

/// „1045” → „1.045”, cum apar numerele mari în titluri.
String numarCuPunct(String numar) =>
    numar.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');

int _eRepublicat(ActNormativ a) =>
    fataDiacritice(a.titlu.toLowerCase()).contains('republicat') ? 1 : 0;

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
    if (t.contains('promulgarea') ||
        t.contains('exceptia de neconstitutionalitate'))
      s -= 4;
    if (a.tipAct == 'RECTIFICARE' || a.tipAct == 'COMUNICAT') s -= 3;
    if (q.startsWith('cod') && a.tipAct.startsWith('COD')) s += 6;
    if (t.startsWith('cod') && q.startsWith('cod')) s += 3;
    s -= t.length ~/ 120;
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
      if (a.numar.replaceAll('.', '').trim() !=
          c.numar.replaceAll('.', '').trim())
        continue;
      if (c.an != null && a.an != c.an) continue;
      if (c.cuvinte.isNotEmpty &&
          !titluContineToate(a.titlu, radaciniCautare(c.cuvinte))) {
        continue;
      }
      return a;
    }
  }
  if (tip == 'CONSTITUTIE') {
    // Forma cea mai nouă (republicată în 2003).
    final c = acte.where((a) => _potrivesteTip(a, tip!)).toList()
      ..sort(
        (x, y) => (y.dataVigoare ?? DateTime(0)).compareTo(
          x.dataVigoare ?? DateTime(0),
        ),
      );
    return c.firstOrNull;
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
String titluFaraAntet(String titlu) => titlu
    .replaceAll('\uFEFF', '')
    // Scăpări RTF: „G\\'f6nczi” → „Gönczi”.
    .replaceAllMapped(
      RegExp(r"\\'([0-9a-fA-F]{2})"),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    )
    .replaceFirst(RegExp(r'\s+EMITENT\b[\s\S]*$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Serviciul strică „ș” și „ț” din emitent în „?” („Pre?edintele României”,
/// „Curtea Constitu?ională”). Le refacem după cum arată cuvântul.
String emitentReparat(String e) {
  if (!e.contains('?')) return e.trim();
  return e
      .replaceAllMapped(RegExp(r'(^|\s)\?i(?=\s|$)'), (m) => '${m[1]}și')
      .replaceAll('Pre?edinte', 'Președinte')
      .replaceAll('?coal', 'școal')
      .replaceAll('?tiin', 'științ')
      .replaceAll('Mini?tri', 'Miniștri')
      .replaceAll('?', 'ț')
      .trim();
}

/// Textul începe uneori cu același antet („... EMITENT PARLAMENTUL ROMÂNIEI
/// Publicat în MONITORUL OFICIAL nr. 661 din 10 august 2026”), care e deja
/// afișat frumos deasupra; îl scoatem.
String textFaraAntet(String text) {
  final m = RegExp(
    r'^[\s\S]{0,900}?\bEMITENT\b[\s\S]{0,300}?MONITORUL OFICIAL(?:\s+al\s+Rom\S*)?,?(?:\s+Partea)?(?:\s+I)?\s+(?:nr\.\s*)?\d+\s+din\s+\d{1,2}\s+\S+\s+\d{4}[ \t\u00a0]*',
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
  return potrivite
      .where(
        (a) => a.tipAct.startsWith('COD') || _norm(a.titlu).startsWith('cod'),
      )
      .firstOrNull;
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
