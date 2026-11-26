// Fără importuri: fișierul e folosit și de aplicație, și de proxy-ul de pe
// server (tool/lexsnap_proxy), ca promptul să fie construit într-un singur
// loc.

/// Un articol găsit în Legislație, singurul material din care modelul are
/// voie să argumenteze.
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'act': act,
    'articol': articol,
    'text': text,
  };

  /// Din cererea primită de proxy (fără cheia actului, care nu-i trebuie).
  factory ArticolSursa.fromJson(Map<String, dynamic> j) => ArticolSursa(
    id: '${j['id'] ?? ''}',
    act: '${j['act'] ?? ''}',
    cheieAct: '',
    articol: '${j['articol'] ?? ''}',
    text: '${j['text'] ?? ''}',
  );
}

/// Cât din document trimitem modelului.
const maxCaractereDocument = 8000;

/// Câte articole trimitem cel mult și cât text din fiecare.
const maxSurse = 12;
const maxCaractereSursa = 6000;

const instructiuniSistem =
    'Ești un asistent juridic pentru dreptul românesc. Răspunzi doar în limba '
    'română și doar cu JSON valid.';

/// Promptul: regulile, sursele numerotate și documentul (trunchiat).
String construiestePrompt(String textDocument, List<ArticolSursa> surse) {
  final doc = textDocument.length > maxCaractereDocument
      ? '${textDocument.substring(0, maxCaractereDocument)} […]'
      : textDocument;
  final b = StringBuffer()
    ..writeln(
      'Primești un document juridic primit de o persoană și o listă de '
      'articole de lege (SURSE). Propune argumente pe care destinatarul '
      'documentului le-ar putea folosi în apărarea sa (de exemplu: termene, '
      'mențiuni obligatorii lipsă, căi de atac, nulități).',
    )
    ..writeln()
    ..writeln('REGULI OBLIGATORII:')
    ..writeln(
      '1. Folosește DOAR SURSELE de mai jos. Nu cita alte legi, articole sau '
      'jurisprudență și nu inventa conținut.',
    )
    ..writeln(
      '2. Fiecare argument are cel puțin o citare: id-ul sursei, articolul, '
      'alineatul (dacă e cazul) și un citat copiat EXACT, cuvânt cu cuvânt, '
      'din textul sursei (minimum 3 cuvinte, fără să schimbi nimic).',
    )
    ..writeln(
      '3. Argumentul spune concret cum se aplică articolul la document. '
      'Dacă documentul nu dă destule informații, spune ce trebuie verificat.',
    )
    ..writeln('4. Dacă nicio sursă nu se aplică, întoarce "sugestii": [].')
    ..writeln('5. Cel mult 5 argumente, fiecare de cel mult 3 propoziții.')
    ..writeln('6. Răspunde DOAR cu JSON, fără alt text, în forma:')
    ..writeln(
      '{"sugestii":[{"text":"...","citari":[{"sursa":"S1","articol":"31",'
      '"alineat":"1","citat":"..."}]}]}',
    )
    ..writeln()
    ..writeln('SURSE:');
  for (final s in surse.take(maxSurse)) {
    final text = s.text.length > maxCaractereSursa
        ? s.text.substring(0, maxCaractereSursa)
        : s.text;
    b
      ..writeln('[${s.id}] ${s.act}, art. ${s.articol}')
      ..writeln(text)
      ..writeln();
  }
  b
    ..writeln('DOCUMENT:')
    ..writeln(doc);
  return b.toString();
}
