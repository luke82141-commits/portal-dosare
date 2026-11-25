import 'dart:convert';

import '../services/act_export.dart' show structureazaInFundal;
import '../services/act_structura.dart';
import 'lexsnap_service.dart';

/// LexSnap, pasul 3 (NU e activ încă): sugestii de apărare scrise de un
/// model AI, prin proxy-ul de pe serverul OVH (cheia Gemini/Groq stă acolo,
/// nu în aplicație).
///
/// Reguli, ca modelul să nu poată inventa lege:
/// - îi dăm DOAR articolele găsite la pasul 2 ([ArticolSursa]), fiecare cu
///   un id („S1”, „S2”); nu are voie să folosească altceva (RAG);
/// - fiecare sugestie citează sursa, articolul, eventual alineatul, și un
///   citat EXACT din textul articolului;
/// - aplicația aruncă orice sugestie a cărei citare nu e printre surse sau
///   al cărei citat nu apare cuvânt cu cuvânt în articol
///   ([pastreazaDoarVerificate]);
/// - fără nicio sugestie rămasă: [mesajFaraPrevedere];
/// - mereu cu [avertismentLexSnap].

const avertismentLexSnap =
    'LexSnap nu oferă consultanță juridică. Rezultatele sunt orientative și '
    'pot fi incomplete sau greșite; verifică textul legii și discută cu un '
    'avocat înainte de a lua o decizie.';

const mesajFaraPrevedere = 'Nu am găsit o prevedere aplicabilă.';

/// Un articol găsit la pasul 2, singurul material din care modelul are voie
/// să argumenteze.
class ArticolSursa {
  /// „S1”, „S2”: cum îl citează modelul.
  final String id;

  /// „Ordonanță nr. 2/2001”.
  final String act;

  /// Cheia actului în Legislație ([ActNormativ.cheie]), pentru deschidere.
  final String cheieAct;

  /// „31”, „5^1”.
  final String articol;

  /// Textul articolului, câte un alineat / o literă pe rând („(1) ...”).
  final String text;

  const ArticolSursa({
    required this.id,
    required this.act,
    required this.cheieAct,
    required this.articol,
    required this.text,
  });
}

class CitareLegala {
  /// Id-ul sursei („S1”).
  final String sursa;
  final String articol;
  final String? alineat;

  /// Citatul exact din articol.
  final String citat;

  const CitareLegala({
    required this.sursa,
    required this.articol,
    this.alineat,
    required this.citat,
  });

  factory CitareLegala.fromJson(Map<String, dynamic> j) => CitareLegala(
    sursa: '${j['sursa'] ?? ''}'.trim(),
    articol: '${j['articol'] ?? ''}'.trim(),
    alineat: j['alineat'] == null || '${j['alineat']}'.trim().isEmpty
        ? null
        : '${j['alineat']}'.replaceAll(RegExp(r'[()\s]'), ''),
    citat: '${j['citat'] ?? ''}',
  );
}

class SugestieAparare {
  /// Argumentul, pe scurt.
  final String text;
  final List<CitareLegala> citari;

  const SugestieAparare(this.text, this.citari);

  factory SugestieAparare.fromJson(Map<String, dynamic> j) =>
      SugestieAparare('${j['text'] ?? ''}'.trim(), [
        for (final c in (j['citari'] as List? ?? const []))
          if (c is Map<String, dynamic>) CitareLegala.fromJson(c),
      ]);
}

/// Cine scrie sugestiile. Implementarea reală va trimite [construiestePrompt]
/// la proxy și va parsa răspunsul cu [parseazaSugestii].
abstract class FurnizorSugestii {
  bool get disponibil;

  Future<List<SugestieAparare>> sugereaza(
    String textDocument,
    List<ArticolSursa> surse,
  );
}

/// Până la proxy-ul de pe OVH: nu există sugestii.
class FurnizorNeconfigurat implements FurnizorSugestii {
  const FurnizorNeconfigurat();

  @override
  bool get disponibil => false;

  @override
  Future<List<SugestieAparare>> sugereaza(
    String textDocument,
    List<ArticolSursa> surse,
  ) async => const [];
}

// ---------------------------------------------------------------------------
// Verificarea citărilor

/// Spațiile strânse, ş/ţ cu sedilă → ș/ț, ghilimele unificate. Literele și
/// punctuația rămân exact cum sunt: citatul trebuie să fie identic.
String _normCitat(String s) => s
    .replaceAll('ş', 'ș')
    .replaceAll('Ş', 'Ș')
    .replaceAll('ţ', 'ț')
    .replaceAll('Ţ', 'Ț')
    .replaceAll(RegExp(r'[“”„«»"]'), '"')
    .replaceAll(RegExp(r'[‘’`]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _normArticol(String s) => nrArticol(
  s.replaceFirst(
    RegExp(r'^\s*(?:art\.?|articolul)\s*', caseSensitive: false),
    '',
  ),
).toUpperCase();

/// Textul alineatului [alineat] din articol: rândul care începe cu „(n)” și
/// literele de sub el, până la alineatul următor.
String? textAlineat(String textArticol, String alineat) {
  final randuri = textArticol.split('\n');
  final i = randuri.indexWhere((r) => r.trimLeft().startsWith('($alineat)'));
  if (i < 0) return null;
  var j = i + 1;
  while (j < randuri.length &&
      !RegExp(r'^\s*\(\d+(?:\^\d+)?\)').hasMatch(randuri[j])) {
    j++;
  }
  return randuri.sublist(i, j).join('\n');
}

/// O citare e bună dacă sursa există, articolul e al ei și citatul (de cel
/// puțin 3 cuvinte) apare cuvânt cu cuvânt în articol (sau în alineatul
/// numit).
bool citareVerificata(CitareLegala c, Map<String, ArticolSursa> surse) {
  final s = surse[c.sursa];
  if (s == null) return false;
  if (_normArticol(c.articol) != _normArticol(s.articol)) return false;
  final citat = _normCitat(c.citat);
  if (citat.split(' ').length < 3) return false;
  final unde = c.alineat == null ? s.text : textAlineat(s.text, c.alineat!);
  if (unde == null) return false;
  return _normCitat(unde).contains(citat);
}

/// Păstrează doar sugestiile cu cel puțin o citare și cu TOATE citările
/// verificate. O sugestie cu o citare inventată e aruncată întreagă.
List<SugestieAparare> pastreazaDoarVerificate(
  List<SugestieAparare> sugestii,
  List<ArticolSursa> surse,
) {
  final dupaId = {for (final s in surse) s.id: s};
  return [
    for (final s in sugestii)
      if (s.text.isNotEmpty &&
          s.citari.isNotEmpty &&
          s.citari.every((c) => citareVerificata(c, dupaId)))
        s,
  ];
}

// ---------------------------------------------------------------------------
// Ce trimitem modelului și ce așteptăm înapoi

/// Promptul pentru proxy. Documentul e trunchiat; sursele sunt complete.
String construiestePrompt(String textDocument, List<ArticolSursa> surse) {
  final doc = textDocument.length > 6000
      ? '${textDocument.substring(0, 6000)} […]'
      : textDocument;
  final b = StringBuffer()
    ..writeln(
      'Ești un asistent juridic pentru dreptul românesc. Primești un document '
      'și o listă de articole de lege (SURSE). Propune argumente pe care '
      'destinatarul documentului le-ar putea folosi în apărarea sa.',
    )
    ..writeln()
    ..writeln('REGULI OBLIGATORII:')
    ..writeln(
      '1. Folosește DOAR SURSELE de mai jos. Nu cita alte legi, '
      'articole sau jurisprudență.',
    )
    ..writeln(
      '2. Fiecare argument are cel puțin o citare: id-ul sursei, '
      'articolul, alineatul (dacă e cazul) și un citat copiat EXACT, '
      'cuvânt cu cuvânt, din textul sursei (minimum 3 cuvinte).',
    )
    ..writeln('3. Dacă nicio sursă nu se aplică, întoarce "sugestii": [].')
    ..writeln('4. Răspunde DOAR cu JSON, fără alt text:')
    ..writeln(
      '{"sugestii":[{"text":"...","citari":[{"sursa":"S1",'
      '"articol":"31","alineat":"1","citat":"..."}]}]}',
    )
    ..writeln()
    ..writeln('SURSE:');
  for (final s in surse) {
    b
      ..writeln('[${s.id}] ${s.act}, art. ${s.articol}')
      ..writeln(s.text)
      ..writeln();
  }
  b
    ..writeln('DOCUMENT:')
    ..writeln(doc);
  return b.toString();
}

/// Răspunsul modelului: JSON-ul `{"sugestii": [...]}`, chiar dacă e
/// înconjurat de text sau de ```json```. Orice altceva → listă goală.
List<SugestieAparare> parseazaSugestii(String raspuns) {
  final start = raspuns.indexOf('{');
  final end = raspuns.lastIndexOf('}');
  if (start < 0 || end <= start) return const [];
  try {
    final j = jsonDecode(raspuns.substring(start, end + 1));
    final lista = j is Map<String, dynamic> ? j['sugestii'] : null;
    if (lista is! List) return const [];
    return [
      for (final s in lista)
        if (s is Map<String, dynamic>) SugestieAparare.fromJson(s),
    ];
  } on FormatException {
    return const [];
  }
}

/// Textul articolelor găsite la pasul 2, ca surse numerotate. Articolele pe
/// care nu le găsim în textul actului (ex. codurile, publicate ca act
/// separat de legea care le aprobă) lipsesc: pasul 3 va trebui să încarce
/// și codul anexat.
Future<List<ArticolSursa>> surseDin(List<PrevedereGasita> prevederi) async {
  final surse = <ArticolSursa>[];
  for (final p in prevederi) {
    if (p.cautare.articole.isEmpty) continue;
    for (final act in p.acte) {
      if (act.text.isEmpty) continue;
      final blocuri = await structureazaInFundal(act.text);
      for (final a in p.cautare.articole) {
        if (surse.any(
          (s) => s.cheieAct == act.cheie && s.articol == a.articol,
        )) {
          continue;
        }
        final i = indiceArticol(blocuri, a.articol);
        if (i == null) continue;
        final linii = [
          for (final x in blocuriArticol(blocuri, i).skip(1))
            if (x.tip != TipBloc.nota)
              [x.eticheta, x.text].where((s) => s.isNotEmpty).join(' '),
        ];
        surse.add(
          ArticolSursa(
            id: 'S${surse.length + 1}',
            act: act.denumireScurta,
            cheieAct: act.cheie,
            articol: a.articol,
            text: linii.join('\n'),
          ),
        );
      }
    }
  }
  return surse;
}
