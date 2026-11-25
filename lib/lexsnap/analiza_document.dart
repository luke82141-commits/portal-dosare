import '../data/acte_cunoscute.dart';
import '../services/legislatie_service.dart';

/// LexSnap, pasul 2: din textul citit de pe o hârtie (OCR) scoatem ce trebuie
/// căutat în Legislație. Totul se face pe telefon; spre legislatie.just.ro
/// pleacă doar numerele actelor și câteva cuvinte cheie, nu documentul.
///
/// Trei surse, în ordinea încrederii:
/// 1. trimiterile scrise în document („art. 31 din O.G. nr. 2/2001”);
/// 2. felul documentului („proces-verbal de constatare a contravenției” →
///    OG 2/2001, art. 31 plângerea);
/// 3. termeni juridici din text („executare silită”, „clauze abuzive”),
///    căutați în titlurile actelor.

/// Un articol cerut dintr-un act: „Art. 16 alin. (1) lit. a)”.
class ArticolCerut {
  final String articol;
  final String? alineat;
  final String? litera;

  const ArticolCerut(this.articol, {this.alineat, this.litera});

  String get eticheta => [
    'Art. $articol',
    if (alineat != null) 'alin. ($alineat)',
    if (litera != null) 'lit. $litera)',
  ].join(' ');

  @override
  bool operator ==(Object other) =>
      other is ArticolCerut &&
      other.articol == articol &&
      other.alineat == alineat &&
      other.litera == litera;

  @override
  int get hashCode => Object.hash(articol, alineat, litera);

  @override
  String toString() => eticheta;
}

/// De unde știm că un act e relevant.
enum MotivPrevedere {
  /// Documentul îl citează.
  citatInDocument,

  /// Așa se contestă / se răspunde de obicei la acest fel de document.
  tipDocument,

  /// Termeni juridici din text.
  termenCheie,
}

/// Un act de căutat în Legislație.
class ActDeCautat {
  /// „OG nr. 2/2001”, „Codul civil”.
  final String eticheta;
  final CerereLegislatie cerere;

  /// Tipul actului (pentru potrivirea exactă), ca în [tipuriActe].
  final String? tip;
  final MotivPrevedere motiv;

  /// De ce: „citat în document”, „proces-verbal de contravenție”.
  final String explicatie;
  final List<ArticolCerut> articole;

  const ActDeCautat({
    required this.eticheta,
    required this.cerere,
    required this.tip,
    required this.motiv,
    required this.explicatie,
    this.articole = const [],
  });

  /// „287/2009” sau textul căutat: aceeași cheie = același act.
  String get cheie => cerere.numar.isNotEmpty
      ? '${cerere.numar.replaceAll('.', '')}/${cerere.an ?? ''}'
      : 'text:${fataDiacritice(cerere.text.toLowerCase())}';

  ActDeCautat cuArticole(List<ArticolCerut> maiMulte) => ActDeCautat(
    eticheta: eticheta,
    cerere: cerere,
    tip: tip,
    motiv: motiv,
    explicatie: explicatie,
    articole: {...articole, ...maiMulte}.toList(),
  );
}

/// Felul documentului fotografiat.
class TipDocument {
  /// „Proces-verbal de contravenție”.
  final String nume;

  /// Ce poate face omul, pe scurt (fără sfaturi: doar unde să se uite).
  final String indicatie;

  final List<ActDeCautat> acte;

  const TipDocument(this.nume, this.indicatie, this.acte);
}

class AnalizaDocument {
  final String text;
  final TipDocument? tipDocument;

  /// Actele de căutat, fără dubluri, în ordinea încrederii.
  final List<ActDeCautat> acte;

  /// Termenii juridici găsiți (pentru afișare).
  final List<String> termeni;

  const AnalizaDocument({
    required this.text,
    required this.tipDocument,
    required this.acte,
    required this.termeni,
  });

  bool get goala => acte.isEmpty;
}

// ---------------------------------------------------------------------------
// Curățarea textului OCR

/// Textul OCR, gata de analizat: cuvintele despărțite la capăt de rând
/// lipite la loc („execu-\ntare” → „executare”), ş/ţ cu sedilă → ș/ț,
/// rândurile unite, spațiile multiple strânse.
String curataTextOcr(String brut) => brut
    .replaceAll('\r', '')
    .replaceAllMapped(
      RegExp(r'([a-zăâîșşțţ])[-‐­]\s*\n\s*([a-zăâîșşțţ])'),
      (m) => '${m[1]}${m[2]}',
    )
    .replaceAll('ş', 'ș')
    .replaceAll('Ş', 'Ș')
    .replaceAll('ţ', 'ț')
    .replaceAll('Ţ', 'Ț')
    .replaceAll(RegExp(r'[“”„«»]'), '"')
    .replaceAll(RegExp(r'[ \t ]*\n[ \t ]*'), ' ')
    .replaceAll(RegExp(r'[ \t ]{2,}'), ' ')
    .trim();

/// Pentru căutări: litere mici, fără diacritice. Are aceeași lungime ca
/// textul primit, deci pozițiile se potrivesc.
String _norm(String s) => fataDiacritice(s.toLowerCase());

// ---------------------------------------------------------------------------
// 1. Trimiterile din document

/// Codurile, cu formele în care apar în acte („Codului de procedură
/// civilă”, „C.proc.civ.”, „NCPC”).
final _coduri = <(RegExp, String, String, int)>[
  for (final c in <(String, String, String, int)>[
    (
      r'c\.?\s*proc\.?\s*civ\b|cod(?:ul|ului)? de procedura civila|\bn\.?c\.?p\.?c\b|\bc\.?p\.?c\b',
      'Codul de procedură civilă',
      '134',
      2010,
    ),
    (
      r'c\.?\s*proc\.?\s*pen\b|cod(?:ul|ului)? de procedura penala|\bn\.?c\.?p\.?p\b|\bc\.?p\.?p\b',
      'Codul de procedură penală',
      '135',
      2010,
    ),
    (
      r'c\.?\s*proc\.?\s*fisc\b|cod(?:ul|ului)? de procedura fiscala',
      'Codul de procedură fiscală',
      '207',
      2015,
    ),
    (
      r'\bc\.?\s*civ\b|cod(?:ul|ului)? civil\b|\bn\.?c\.?c\b',
      'Codul civil',
      '287',
      2009,
    ),
    (
      r'\bc\.?\s*pen\b|cod(?:ul|ului)? penal\b|\bn\.?c\.?p\b',
      'Codul penal',
      '286',
      2009,
    ),
    (r'cod(?:ul|ului)? muncii|\bc\.?\s*muncii', 'Codul muncii', '53', 2003),
    (r'cod(?:ul|ului)? fiscal\b|\bc\.?\s*fisc\b', 'Codul fiscal', '227', 2015),
    (r'cod(?:ul|ului)? administrativ', 'Codul administrativ', '57', 2019),
  ])
    (RegExp(c.$1), c.$2, c.$3, c.$4),
];

/// „Legea nr. 85/2014”, „O.U.G. nr. 195 din 12 decembrie 2002”, „HG 1/2016”.
final _reAct = RegExp(
  r'\b(legea|legii|lege|l\.|o\.\s*u\.\s*g\.|oug|ordonanta de urgenta(?: a guvernului)?|ordonantei de urgenta(?: a guvernului)?|o\.\s*g\.|og|ordonanta(?: guvernului)?|ordonantei(?: guvernului)?|h\.\s*g\.|hg|hotararea(?: guvernului)?|hotararii(?: guvernului)?|decretul|decretului|decret|ordinul|ordinului)'
  r'\s*(?:nr\.?\s*)?(\d{1,3}(?:\.\d{3})+|\d{1,5})'
  r'\s*(?:/\s*((?:18|19|20)\d{2})\b|din\s+(?:\d{1,2}[\s.]+[a-z]+[\s.]+|\d{1,2}\.\d{1,2}\.)?((?:18|19|20)\d{2})\b)',
);

/// „art. 16, 17 și 19”, „art. 194 alin. (1) lit. a)”, „articolul 31”.
final _reArticol = RegExp(
  r'\b(?:art\.?|articol(?:ul|ului|ele|elor)?)\s*'
  r'(\d{1,3}(?:\.\d{3})+(?!\d)|\d{1,4}(?:\s*\^\s*\d+)?)'
  r'(?:\s*alin\.?\s*\(?\s*(\d{1,2})\s*\)?)?'
  r'(?:\s*,?\s*lit\.?\s*([a-z])\s*\))?'
  r'((?:\s*(?:,|si|și)\s*(?:\d{1,4})(?!\s*/)(?!\d))*)',
);

/// Un act găsit în text, cu poziția lui.
class _Mentiune {
  final int start;
  final int end;
  final ActDeCautat act;
  const _Mentiune(this.start, this.end, this.act);
}

ActDeCautat _actLege(String tip, String numar, int an, String explicatie) {
  final nr = numar.replaceAll('.', '');
  final cunoscut = acteCunoscute
      .where((a) => a.numar == nr && a.an == an && a.tip == tip)
      .firstOrNull;
  if (cunoscut != null) {
    return ActDeCautat(
      eticheta: '${cunoscut.nume} (${cunoscut.trimitere})',
      cerere: cerereActCunoscut(cunoscut),
      tip: cunoscut.tip,
      motiv: MotivPrevedere.citatInDocument,
      explicatie: explicatie,
    );
  }
  return ActDeCautat(
    eticheta: '${etichetaTip(tip)} nr. $nr/$an',
    cerere: CerereLegislatie(numar: nr, an: an, tip: tip),
    tip: tip,
    motiv: MotivPrevedere.citatInDocument,
    explicatie: explicatie,
  );
}

ActDeCautat _actCunoscut(
  String numar,
  int an,
  MotivPrevedere motiv,
  String explicatie, [
  List<ArticolCerut> articole = const [],
]) {
  final a = acteCunoscute.firstWhere((a) => a.numar == numar && a.an == an);
  return ActDeCautat(
    eticheta: a.nume.startsWith('Cod') || a.nume.startsWith('Legea')
        ? a.nume
        : '${a.nume} (${a.trimitere})',
    cerere: cerereActCunoscut(a),
    tip: a.tip,
    motiv: motiv,
    explicatie: explicatie,
    articole: articole,
  );
}

List<_Mentiune> _mentiuniActe(String n) {
  final rezultat = <_Mentiune>[];
  for (final m in _reAct.allMatches(n)) {
    final tip = tipDinAbreviere(m[1]!) ?? 'LEGE';
    final an = int.parse(m[3] ?? m[4]!);
    rezultat.add(
      _Mentiune(m.start, m.end, _actLege(tip, m[2]!, an, 'Citat în document')),
    );
  }
  for (final c in _coduri) {
    for (final m in c.$1.allMatches(n)) {
      // „C.proc.civ.” conține și „c.civ”: păstrăm potrivirea mai lungă.
      if (rezultat.any((r) => r.start <= m.start && r.end >= m.end)) continue;
      rezultat.add(
        _Mentiune(
          m.start,
          m.end,
          _actCunoscut(
            c.$3,
            c.$4,
            MotivPrevedere.citatInDocument,
            'Citat în document',
          ),
        ),
      );
    }
  }
  rezultat.sort((a, b) => a.start.compareTo(b.start));
  return rezultat;
}

/// Între articol și act stau doar legături: „ din ”, „ al ”, „, ”, „ din
/// Legea ...”. Mai mult de atât înseamnă că articolul nu ține de acel act.
final _reLegatura = RegExp(
  r'^[\s,]*(?:\)|alin\.?\s*\(?\d+\)?|lit\.?\s*[a-z]\)|pct\.?\s*\d+|teza\s+\S+|[\s,])*'
  r'(?:din|al|a|ale|la|cf\.?|conform|potrivit)?\s*(?:noul\s+|actualul\s+)?$',
);

/// Trimiterile la acte din document, cu articolele lor.
List<ActDeCautat> trimiteriDinDocument(String text) {
  final n = _norm(text);
  final acte = _mentiuniActe(n);
  if (acte.isEmpty) return const [];
  final articole = <String, List<ArticolCerut>>{};
  final faraAct = <ArticolCerut>[];

  for (final m in _reArticol.allMatches(n)) {
    final cerute = [
      ArticolCerut(
        m[1]!.replaceAll(RegExp(r'[\s.]'), ''),
        alineat: m[2],
        litera: m[3],
      ),
      for (final x in RegExp(r'\d{1,4}').allMatches(m[4] ?? ''))
        ArticolCerut(x[0]!),
    ];
    // Actul de după articol, legat doar prin „din”, „al”, alineate...
    final urmator = acte.where((a) => a.start >= m.end).firstOrNull;
    if (urmator != null &&
        urmator.start - m.end <= 40 &&
        _reLegatura.hasMatch(n.substring(m.end, urmator.start))) {
      articole.putIfAbsent(urmator.act.cheie, () => []).addAll(cerute);
    } else {
      faraAct.addAll(cerute);
    }
  }

  final unice = <String, ActDeCautat>{};
  for (final a in acte) {
    unice.putIfAbsent(a.act.cheie, () => a.act);
  }
  // „art. 31” fără act, într-un document care citează un singur act:
  // e din acel act.
  if (unice.length == 1 && faraAct.isNotEmpty) {
    articole.putIfAbsent(unice.keys.first, () => []).addAll(faraAct);
  }
  return [
    for (final e in unice.entries) e.value.cuArticole(articole[e.key] ?? []),
  ];
}

// ---------------------------------------------------------------------------
// 2. Felul documentului

class _Regula {
  final RegExp re;
  final TipDocument Function() tip;
  const _Regula(this.re, this.tip);
}

List<ArticolCerut> _art(List<String> nr) => [
  for (final n in nr) ArticolCerut(n),
];

/// Prevederi uzuale pentru fiecare fel de document. Articolele sunt doar
/// punctele de plecare: omul le citește și decide.
final _reguli = <_Regula>[
  _Regula(
    RegExp(
      r'proces[\s-]*verbal\w* de constatare|contraventi[ae]\w*|sanctiun\w* contraventional',
    ),
    () => TipDocument(
      'Proces-verbal de contravenție',
      'Plângerea contravențională și mențiunile obligatorii ale procesului-verbal.',
      [
        _actCunoscut(
          '2',
          2001,
          MotivPrevedere.tipDocument,
          'Regimul juridic al contravențiilor',
          _art(['16', '17', '31']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(
      r'executare\w* silit|executor\w* judecatoresc|somati[ae]\w*(?! de plata)|popri\w*|incuviintar\w* (?:a )?executar',
    ),
    () => TipDocument(
      'Act de executare silită',
      'Contestația la executare și termenul ei.',
      [
        _actCunoscut(
          '134',
          2010,
          MotivPrevedere.tipDocument,
          'Contestația la executare',
          _art(['712', '714', '715']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(r'ordonant\w* de plata|somati\w* de plata'),
    () => TipDocument(
      'Somație / cerere de ordonanță de plată',
      'Procedura ordonanței de plată din Codul de procedură civilă.',
      [
        _actCunoscut(
          '134',
          2010,
          MotivPrevedere.tipDocument,
          'Procedura ordonanței de plată',
          _art(['1014', '1015']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(
      r'cerere\w* de chemare in judecata|\bciteaz\w*|\bcitati\w*|intampinar\w*',
    ),
    () => TipDocument(
      'Citație / cerere de chemare în judecată',
      'Întâmpinarea și termenul în care se depune.',
      [
        _actCunoscut(
          '134',
          2010,
          MotivPrevedere.tipDocument,
          'Întâmpinarea',
          _art(['201', '205']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(
      r'decizi\w* de impunere|\banaf\b|administrati\w* fiscal|obligati\w* fiscal',
    ),
    () => TipDocument(
      'Act fiscal (ANAF)',
      'Contestația administrativă împotriva actului fiscal.',
      [
        _actCunoscut(
          '207',
          2015,
          MotivPrevedere.tipDocument,
          'Contestația împotriva actului administrativ fiscal',
          _art(['268', '270']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(
      r'decizi\w* de concediere|concedier\w*|desfacer\w* (?:a )?contractului (?:individual )?de munca',
    ),
    () => TipDocument(
      'Decizie de concediere',
      'Conținutul obligatoriu al deciziei și termenul de contestare.',
      [
        _actCunoscut(
          '53',
          2003,
          MotivPrevedere.tipDocument,
          'Concedierea',
          _art(['76', '268']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(r'ordonant\w* de clasare|clasar\w*|renunt\w* la urmarire'),
    () => TipDocument(
      'Soluție a procurorului',
      'Plângerea împotriva soluției procurorului.',
      [
        _actCunoscut(
          '135',
          2010,
          MotivPrevedere.tipDocument,
          'Plângerea împotriva soluțiilor procurorului',
          _art(['339', '340']),
        ),
      ],
    ),
  ),
  _Regula(
    RegExp(
      r'\bsentint\w*|hotarar\w* judecatoreasc|\bdispozitiv\w*|\bpronuntat\w*',
    ),
    () =>
        TipDocument('Hotărâre judecătorească', 'Apelul și termenul de apel.', [
          _actCunoscut(
            '134',
            2010,
            MotivPrevedere.tipDocument,
            'Apelul',
            _art(['466', '468']),
          ),
        ]),
  ),
];

/// Primul fel de document care se potrivește (ordinea regulilor contează:
/// un proces-verbal pomenește și „executare”).
TipDocument? tipDocumentDin(String text) {
  final n = _norm(text);
  for (final r in _reguli) {
    if (r.re.hasMatch(n)) return r.tip();
  }
  return null;
}

// ---------------------------------------------------------------------------
// 3. Termeni juridici

/// Termeni care apar des în hârtiile oamenilor, cu ce căutăm în titlurile
/// actelor. Fără diacritice; potrivire după rădăcină.
const _termeni = <(String, String)>[
  (r'clauz\w* abuziv', 'clauze abuzive'),
  (r'protecti\w* consumator', 'protecția consumatorilor'),
  (
    r'credit\w* (?:pentru )?consum|contract\w* de credit',
    'contracte de credit pentru consumatori',
  ),
  (r'asociati\w* de proprietari', 'asociațiile de proprietari'),
  (r'contract\w* de inchiriere|\bchiri\w*|\bevacuar\w*', 'locuinței'),
  (r'pensi\w* de intretinere|\bpartaj\w*|\bdivort\w*', 'Codul civil'),
  (r'insolvent\w*|faliment\w*', 'insolvenței'),
  (r'contencios\w* administrativ', 'contenciosul administrativ'),
  (r'fond\w* funciar|titlu\w* de proprietate', 'fondului funciar'),
  (
    r'autorizati\w* de construire',
    'autorizarea executării lucrărilor de construcții',
  ),
  (r'violent\w* domestic|ordin\w* de protectie', 'violenței domestice'),
  (
    r'date\w* cu caracter personal|\bgdpr\b',
    'protecția persoanelor fizice în ceea ce privește prelucrarea datelor cu caracter personal',
  ),
  (
    r'impozit\w* pe cladir|impozit\w* local|taxe\w* local',
    'impozitele și taxele locale',
  ),
  (
    r'permis\w* de conducere|circulati\w* pe drumuri',
    'circulația pe drumurile publice',
  ),
  (r'ajutor\w* public judiciar', 'ajutorul public judiciar'),
  (r'cazier\w* judiciar', 'cazierul judiciar'),
];

/// Termenii juridici din text și ce căutăm pentru ei (fără dubluri).
List<(String gasit, String cautare)> termeniDin(String text) {
  final n = _norm(text);
  final rezultat = <(String, String)>[];
  final vazute = <String>{};
  for (final t in _termeni) {
    final m = RegExp(t.$1).firstMatch(n);
    if (m == null || !vazute.add(t.$2)) continue;
    // Forma din document, cu diacritice.
    rezultat.add((text.substring(m.start, m.end), t.$2));
  }
  return rezultat;
}

// ---------------------------------------------------------------------------

/// Cât trimitem cel mult serviciului (fiecare act = câteva cereri, ≥1 s
/// între ele; Codul civil are 6 MB).
const maxActeDeCautat = 6;

/// Analiza completă: ce acte căutăm și de ce.
AnalizaDocument analizeazaDocument(String textOcr) {
  final text = curataTextOcr(textOcr);
  final acte = <String, ActDeCautat>{};

  void adauga(ActDeCautat a) {
    final existent = acte[a.cheie];
    acte[a.cheie] = existent == null ? a : existent.cuArticole(a.articole);
  }

  trimiteriDinDocument(text).forEach(adauga);
  final tip = tipDocumentDin(text);
  tip?.acte.forEach(adauga);

  final termeni = termeniDin(text);
  for (final (_, cautare) in termeni) {
    // „Codul civil” e deja un act cunoscut, nu o căutare în titluri.
    final cunoscut = acteCunoscute.where((a) => a.nume == cautare).firstOrNull;
    if (cunoscut != null) {
      adauga(
        _actCunoscut(
          cunoscut.numar,
          cunoscut.an,
          MotivPrevedere.termenCheie,
          'Termen din document',
        ),
      );
      continue;
    }
    adauga(
      ActDeCautat(
        eticheta: '„$cautare”',
        cerere: CerereLegislatie(text: cautare),
        tip: null,
        motiv: MotivPrevedere.termenCheie,
        explicatie: 'Termen din document',
      ),
    );
  }

  return AnalizaDocument(
    text: text,
    tipDocument: tip,
    acte: acte.values.take(maxActeDeCautat).toList(),
    termeni: [for (final t in termeni) t.$1],
  );
}
