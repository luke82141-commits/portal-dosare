import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sugestii_aparare.dart';

/// Adresa proxy-ului LexSnap AI de pe serverul OVH (fără „/” la final) și
/// tokenul aplicației. Se pot schimba la build:
/// `flutter build apk --dart-define=LEXSNAP_AI_URL=https://...`.
///
/// Tokenul nu e secret (stă în aplicație); doar oprește cererile
/// întâmplătoare. Cheia Groq / Gemini stă DOAR pe server.
const urlProxyAi = String.fromEnvironment(
  'LEXSNAP_AI_URL',
  defaultValue: 'https://57-129-169-40.sslip.io/lexsnap',
);
const tokenProxyAi = String.fromEnvironment(
  'LEXSNAP_AI_TOKEN',
  defaultValue: 'lexsnap-app-v1',
);

/// Furnizorul folosit de ecran: proxy-ul, dacă are adresă.
FurnizorSugestii furnizorImplicit() => urlProxyAi.isEmpty
    ? const FurnizorNeconfigurat()
    : FurnizorProxy(Uri.parse(urlProxyAi));

class EroareSugestii implements Exception {
  final String mesaj;
  EroareSugestii(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Trimite documentul (fără date de identificare) și sursele la proxy;
/// întoarce sugestiile, NEFILTRATE (filtrarea e în [pastreazaDoarVerificate]).
class FurnizorProxy implements FurnizorSugestii {
  final Uri baza;
  final http.Client _client;

  FurnizorProxy(this.baza, {http.Client? client})
    : _client = client ?? http.Client();

  @override
  bool get disponibil => true;

  @override
  Future<List<SugestieAparare>> sugereaza(
    String textDocument,
    List<ArticolSursa> surse,
  ) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            baza.resolve(
              '${baza.path.endsWith('/') ? '' : '${baza.path}/'}sugestii',
            ),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'X-LexSnap-Token': tokenProxyAi,
            },
            body: jsonEncode({
              'document': anonimizeaza(textDocument),
              'surse': [for (final s in surse) s.toJson()],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw EroareSugestii(
        'Serviciul AI nu a răspuns la timp. Încearcă din nou.',
      );
    } catch (_) {
      throw EroareSugestii(
        'Nu am putut contacta serviciul AI. Verifică internetul.',
      );
    }
    if (r.statusCode == 429) {
      throw EroareSugestii(
        'Prea multe cereri către serviciul AI. Încearcă peste un minut.',
      );
    }
    if (r.statusCode != 200) {
      throw EroareSugestii(
        'Serviciul AI a răspuns cu eroarea ${r.statusCode}.',
      );
    }
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return const [];
    }
    final raspuns = j is Map<String, dynamic> ? j['raspuns'] : null;
    return raspuns is String ? parseazaSugestii(raspuns) : const [];
  }
}

// ---------------------------------------------------------------------------
// Datele de identificare nu pleacă de pe telefon

final _anonimizari = <(RegExp, String)>[
  // CNP: 13 cifre, prima 1-9.
  (RegExp(r'(?<!\d)[1-9]\d{12}(?!\d)'), '[CNP]'),
  // IBAN românesc, cu sau fără spații.
  (
    RegExp(
      r'\bRO\s?\d{2}(?:\s?[A-Z0-9]{4}){4}(?:\s?[A-Z0-9]{0,4})',
      caseSensitive: false,
    ),
    '[IBAN]',
  ),
  (RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+'), '[EMAIL]'),
  // Telefon: 07xx xxx xxx, +40 7xx..., 02x/03x fix.
  (
    RegExp(
      r'(?<![\d/])(?:\+?40|0040|0)\s?[237]\d{1,2}[\s.-]?\d{3}[\s.-]?\d{3,4}(?![\d/])',
    ),
    '[TELEFON]',
  ),
  // Buletin: „seria RX nr. 123456”, „CI seria XB 123456”.
  (
    RegExp(
      r'\bseria\s+[A-Z]{2}\s*(?:,?\s*nr\.?)?\s*\d{6}\b',
      caseSensitive: false,
    ),
    'seria [ACT IDENTITATE]',
  ),
  // Număr de înmatriculare: „B 123 ABC”, „PH-07-XYZ”.
  (
    RegExp(r'\b(?:B|[A-Z]{2})[\s-]?\d{2,3}[\s-]?(?!DIN\b)[A-Z]{3}\b'),
    '[NR. AUTO]',
  ),
];

// Nume: doar după formulele care anunță o persoană („contravenientul”,
// „domnul”, „numele și prenumele:”), ca să nu ștergem numele instituțiilor
// sau ale actelor normative.
const _litereMari = 'A-ZĂÂÎȘŞȚŢ';
const _litereMici = 'a-zăâîșşțţ';
const _cuvantNume =
    '(?:[$_litereMari][$_litereMici]+|[$_litereMari]{2,}|[$_litereMari]\\.)'
    '(?:-(?:[$_litereMari][$_litereMici]+|[$_litereMari]{2,}))?';

String _formula(String cuvinte) => cuvinte
    .split('|')
    .map((c) => '[${c[0].toUpperCase()}${c[0].toLowerCase()}]${c.substring(1)}')
    .join('|');

final _formuleNume = _formula(
  'domnul|doamna|domnului|doamnei|dl\\.|d-l|d-na|dna\\.|numitul|numita|'
  'numitului|numitei|subsemnatul|subsemnata|contravenientul|contravenienta|'
  'contravenientului|contravenientei|contravenient|petentul|petenta|petent|'
  'reclamantul|reclamanta|reclamant|pârâtul|pârâta|pârât|debitorul|'
  'debitoarea|debitor|creditorul|creditoarea|creditor|intimatul|intimata|'
  'inculpatul|inculpata|martorul|martora|agentul constatator|'
  'agent constatator|executorul judecătoresc|executor judecătoresc|'
  'avocatul|avocat|av\\.|fiul lui|fiica lui|nume și prenume|'
  'numele și prenumele|numele|prenumele|nume|prenume',
);

final _nume = RegExp(
  '(?<![$_litereMici$_litereMari])($_formuleNume)(\\s*:?\\s*)'
  '$_cuvantNume(?:[ \\t]+$_cuvantNume){0,3}',
);

// Adrese: strada și ce urmează (număr, bloc, scară, etaj, apartament).
// Localitatea și județul rămân (pot conta pentru competență).
final _adresa = RegExp(
  '(?<![$_litereMici$_litereMari])'
  '(?:${_formula('strada|str\\.|bulevardul|bd\\.|b-dul|calea|aleea|'
  'șoseaua|șos\\.|soseaua|piața|intrarea|intr\\.|splaiul')})'
  '\\s+[^,;\\n]{1,40}'
  '(?:,?\\s*(?:nr|bl|sc|et|ap|bloc|scara|etaj|apartament)\\.?\\s*[\\w/-]+)*',
);

/// Textul fără date de identificare: CNP, IBAN, email, telefon, seria
/// buletinului, număr de înmatriculare, adresa (strada și numărul) și
/// numele care urmează după formule ca „contravenientul”, „domnul”,
/// „subsemnatul”. Un nume scris fără o asemenea formulă poate rămâne.
String anonimizeaza(String text) {
  var t = text;
  for (final (re, inlocuire) in _anonimizari) {
    t = t.replaceAll(re, inlocuire);
  }
  t = t.replaceAllMapped(_adresa, (_) => '[ADRESĂ]');
  t = t.replaceAllMapped(_nume, (m) => '${m[1]}${m[2]}[NUME]');
  return t;
}
