import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:legal_management_app/lexsnap/analiza_document.dart';
import 'package:legal_management_app/lexsnap/lexsnap_service.dart';
import 'package:legal_management_app/lexsnap/ocr_service.dart';
import 'package:legal_management_app/lexsnap/sugestii_aparare.dart';
import 'package:legal_management_app/screens/lexsnap_screen.dart';
import 'package:legal_management_app/services/legislatie_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un proces-verbal de circulație, cum îl întoarce OCR-ul: rânduri rupte,
/// un cuvânt despărțit în silabe, ş/ţ cu sedilă.
const _procesVerbal = '''
PROCES-VERBAL DE CONSTATARE ŞI SANCŢIONARE
A CONTRAVENŢIEI seria PCA nr. 1234567
Încheiat astăzi 12.11.2026, subsemnatul agent de poliţie ...
am constatat că numitul POPESCU ION a condus autoturismul cu viteza
de 87 km/h în localitate, faptă prevăzută de art. 121 alin. (1) din
Regulamentul aprobat prin H.G. nr. 1391/2006 şi sancţionată de
art. 100 alin. 3 lit. b) din O.U.G. nr. 195/2002 privind circula-
ţia pe drumurile publice. Se aplică amendă conform O.G. nr. 2/2001.
Contravenientul poate formula plângere în 15 zile.
''';

const _raspunsToken =
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
    '<GetTokenResponse xmlns="http://tempuri.org/"><GetTokenResult>abc</GetTokenResult>'
    '</GetTokenResponse></s:Body></s:Envelope>';

String _lege(String tip, String numar, String titlu, String text) =>
    '<a:Legi><a:DataVigoare>2002-01-01T00:00:00</a:DataVigoare><a:Emitent>GUVERNUL</a:Emitent>'
    '<a:LinkHtml>http://legislatie.just.ro/Public/DetaliiDocument/$numar$tip</a:LinkHtml>'
    '<a:Numar>$numar</a:Numar><a:Publicatie>MONITORUL OFICIAL</a:Publicatie>'
    '<a:Text>$text</a:Text><a:TipAct>$tip</a:TipAct><a:Titlu>$titlu</a:Titlu></a:Legi>';

String _raspuns(List<String> legi) =>
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
    '<SearchResponse xmlns="http://tempuri.org/">'
    '<SearchResult xmlns:a="http://schemas.datacontract.org/2004/07/FreeWebService" '
    'xmlns:i="http://www.w3.org/2001/XMLSchema-instance">${legi.join()}</SearchResult>'
    '</SearchResponse></s:Body></s:Envelope>';

final _og2 = _lege(
  'ORDONANTA',
  '2',
  'ORDONANȚĂ nr. 2 din 12 iulie 2001 privind regimul juridic al contravențiilor',
  'Articolul 31\n(1) Împotriva procesului-verbal de constatare a contravenției '
      'și de aplicare a sancțiunii se poate face plângere în termen de 15 zile '
      'de la data înmânării sau comunicării acestuia.\n'
      '(2) Partea vătămată poate face plângere.\nArticolul 32\n(1) Plângerea...',
);
final _oug195 = _lege(
  'ORDONANTA DE URGENTA',
  '195',
  'ORDONANȚĂ DE URGENȚĂ nr. 195 din 12 decembrie 2002 privind circulația pe drumurile publice',
  'Articolul 100\n(1) ...',
);
final _hg1391 = _lege(
  'HOTARARE',
  '1391',
  'HOTĂRÂRE nr. 1.391 din 4 octombrie 2006 pentru aprobarea Regulamentului',
  'Articolul 1 ...',
);

/// Serviciul Legislație simulat: răspunde după numărul din titlul căutat.
http.Client _client({Set<String> cazute = const {}}) => MockClient((r) async {
  final corp = r.body;
  if (corp.contains('GetToken')) {
    return http.Response.bytes(utf8.encode(_raspunsToken), 200);
  }
  List<String> legi = [];
  if (corp.contains('nr. 2 din')) legi = [_og2];
  if (corp.contains('nr. 195 din')) legi = [_oug195];
  if (corp.contains('nr. 1.391 din')) legi = [_hg1391];
  if (cazute.any(corp.contains)) return http.Response('eroare', 500);
  return http.Response.bytes(utf8.encode(_raspuns(legi)), 200);
});

void main() {
  setUp(() => LegislatieService.pauzaIntreCereri = Duration.zero);

  group('textul OCR', () {
    test('lipește cuvintele despărțite și unește rândurile', () {
      expect(
        curataTextOcr('privind circula-\nţia pe drumuri\npublice'),
        'privind circulația pe drumuri publice',
      );
    });
  });

  group('trimiterile din document', () {
    test('proces-verbal: actele citate cu articolele lor', () {
      final a = analizeazaDocument(_procesVerbal);
      final chei = a.acte.map((x) => x.cheie).toList();
      expect(chei.take(3), ['1391/2006', '195/2002', '2/2001']);

      final oug = a.acte[1];
      expect(oug.eticheta, contains('Codul rutier'));
      expect(oug.motiv, MotivPrevedere.citatInDocument);
      expect(oug.articole, [
        const ArticolCerut('100', alineat: '3', litera: 'b'),
      ]);
      // „art. 121 ... din Regulamentul aprobat prin H.G.”: articolul e din
      // regulament, nu din hotărâre.
      expect(a.acte[0].articole, isEmpty);

      // Felul documentului adaugă articolele uzuale la OG 2/2001, deja citată.
      expect(a.tipDocument?.nume, 'Proces-verbal de contravenție');
      expect(
        a.acte[2].articole.map((x) => x.articol),
        containsAll(['16', '17', '31']),
      );
      expect(a.termeni, contains('circulația pe drumuri'));
    });

    test('coduri în forme diferite, articole fără act și liste', () {
      final t = trimiteriDinDocument(
        'în temeiul art. 1.350 și 1357 din Codul civil și al art. 194 '
        'C.proc.civ., precum și art. 453 NCPC',
      );
      expect(t.map((x) => x.cerere.numar), ['287', '134']);
      expect(t[0].articole.map((x) => x.articol), ['1350', '1357']);
      expect(t[1].articole.map((x) => x.articol), ['194', '453']);
      expect(t[0].cerere.anVigoare, 2011);
    });

    test('„Legii nr. 85 din 25 iunie 2014”: anul din dată', () {
      final t = trimiteriDinDocument(
        'conform art. 5 alin. (1) pct. 72 al Legii nr. 85 din 25 iunie 2014',
      );
      expect(t.single.cerere.numar, '85');
      expect(t.single.cerere.an, 2014);
      expect(t.single.eticheta, contains('Legea insolvenței'));
      expect(t.single.articole.single.articol, '5');
    });

    test('articol departe de act nu e legat de el', () {
      final t = trimiteriDinDocument(
        'potrivit art. 12 alin. (2), care reglementează altceva decât ce '
        'urmează. Conform Legii nr. 554/2004 și Legii nr. 31/1990',
      );
      expect(t.map((x) => x.cheie), ['554/2004', '31/1990']);
      expect(t.every((x) => x.articole.isEmpty), isTrue);
    });

    test('un singur act citat: „art. 31” singur ține de el', () {
      final t = trimiteriDinDocument(
        'Sancțiune aplicată conform OG 2/2001. Plângere potrivit art. 31.',
      );
      expect(t.single.articole.single.articol, '31');
    });
  });

  group('felul documentului și termenii', () {
    test('executare silită → contestația la executare', () {
      final a = analizeazaDocument(
        'BIROUL EXECUTORULUI JUDECĂTORESC ... SOMAȚIE ... executare silită '
        'în dosarul nr. 120/2026',
      );
      expect(a.tipDocument?.nume, 'Act de executare silită');
      expect(a.acte.single.cerere.numar, '134');
      expect(a.acte.single.articole.map((x) => x.articol), [
        '712',
        '714',
        '715',
      ]);
    });

    test('somație de plată nu e executare silită', () {
      expect(
        tipDocumentDin('SOMAȚIE DE PLATĂ către debitor')?.nume,
        startsWith('Somație / cerere de ordonanță de plată'),
      );
    });

    test('termeni: căutare în titluri, fără dubluri', () {
      final a = analizeazaDocument(
        'Contractul de credit conține clauze abuzive. Clauzele abuzive ...',
      );
      expect(a.acte.map((x) => x.cerere.text), [
        'clauze abuzive',
        'contracte de credit pentru consumatori',
      ]);
      expect(a.acte.first.motiv, MotivPrevedere.termenCheie);
    });

    test('text fără nimic juridic → analiză goală', () {
      expect(
        analizeazaDocument('Lista de cumpărături: lapte, pâine').goala,
        isTrue,
      );
    });
  });

  group('căutarea în Legislație', () {
    test(
      'găsește actele exacte, pe rând; o eroare nu oprește restul',
      () async {
        final a = analizeazaDocument(_procesVerbal);
        final service = LegislatieService.cuClient(
          _client(cazute: {'nr. 1.391 din', 'SearchNumar>1391'}),
        );
        final rezultate = await cautaPrevederi(a, service: service).toList();
        expect(rezultate.length, a.acte.length);
        expect(rezultate[0].gasita, isFalse);
        expect(rezultate[1].acte.single.numar, '195');
        expect(rezultate[2].acte.single.numar, '2');
      },
    );
  });

  group('sugestiile de apărare (pasul 3)', () {
    const surse = [
      ArticolSursa(
        id: 'S1',
        act: 'Ordonanță nr. 2/2001',
        cheieAct: 'og2',
        articol: '31',
        text:
            '(1) Împotriva procesului-verbal de constatare a contravenției și de '
            'aplicare a sancțiunii se poate face plângere în termen de 15 zile de '
            'la data înmânării sau comunicării acestuia.\n'
            '(2) Partea vătămată poate face plângere.',
      ),
    ];

    SugestieAparare s(String sursa, String art, String citat, [String? alin]) =>
        SugestieAparare('Fă plângere.', [
          CitareLegala(sursa: sursa, articol: art, alineat: alin, citat: citat),
        ]);

    test('păstrează doar citările exacte din surse', () {
      final bune = pastreazaDoarVerificate([
        s('S1', '31', 'se poate face plângere în termen de 15 zile', '1'),
        // Cu sedilă și spații în plus: tot exact.
        s('S1', 'art. 31', 'Partea  vătămată poate face plângere', '2'),
        // Alineat greșit.
        s('S1', '31', 'se poate face plângere în termen de 15 zile', '2'),
        // Citat modificat („30 de zile”).
        s('S1', '31', 'se poate face plângere în termen de 30 de zile'),
        // Sursă inventată.
        s('S9', '31', 'se poate face plângere în termen de 15 zile'),
        // Alt articol.
        s('S1', '32', 'se poate face plângere în termen de 15 zile'),
        // Citat prea scurt.
        s('S1', '31', 'plângere'),
        // Fără citări.
        const SugestieAparare('Fără temei.', []),
      ], surse);
      expect(bune.length, 2);
    });

    test('o citare greșită aruncă toată sugestia', () {
      final x = SugestieAparare('Două temeiuri.', const [
        CitareLegala(
          sursa: 'S1',
          articol: '31',
          citat: 'se poate face plângere în termen de 15 zile',
        ),
        CitareLegala(
          sursa: 'S2',
          articol: '17',
          citat: 'lipsa mențiunilor atrage nulitatea',
        ),
      ]);
      expect(pastreazaDoarVerificate([x], surse), isEmpty);
    });

    test('răspunsul modelului: JSON, chiar cu text în jur', () {
      final l = parseazaSugestii(
        'Iată:\n```json\n{"sugestii":[{"text":"Plângere","citari":[{"sursa":"S1",'
        '"articol":"31","alineat":"(1)","citat":"se poate face plângere"}]}]}\n```',
      );
      expect(l.single.citari.single.alineat, '1');
      expect(parseazaSugestii('nu știu'), isEmpty);
      expect(parseazaSugestii('{"sugestii": 3}'), isEmpty);
    });

    test('promptul conține regulile și sursele', () {
      final p = construiestePrompt('PROCES-VERBAL ...', surse);
      expect(p, contains('[S1] Ordonanță nr. 2/2001, art. 31'));
      expect(p, contains('EXACT'));
      expect(p, contains('"sugestii": []'));
    });

    test('sursele: textul articolelor din actele găsite', () async {
      final service = LegislatieService.cuClient(_client());
      final a = analizeazaDocument(
        'Sancțiune conform OG 2/2001, plângere art. 31.',
      );
      final p = await cautaPrevederi(a, service: service).toList();
      final surse = await surseDin(p);
      final s31 = surse.firstWhere((s) => s.articol == '31');
      expect(s31.id, startsWith('S'));
      expect(s31.text, contains('termen de 15 zile'));
      expect(
        citareVerificata(
          CitareLegala(
            sursa: s31.id,
            articol: '31',
            alineat: '1',
            citat: 'se poate face plângere în termen de 15 zile',
          ),
          {s31.id: s31},
        ),
        isTrue,
      );
    });
  });

  group('ecranul LexSnap', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('fotografie → text → prevederi, cu articolele', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: LexSnapScreen(
            ocr: _OcrFals(_procesVerbal),
            alegeImagine: (_) async => '/poza.jpg',
            service: LegislatieService.cuClient(_client()),
          ),
        ),
      );
      await t.tap(find.text('Fotografiază'));
      await t.pump();
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      expect(find.text('Proces-verbal de contravenție'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Art. 100 alin. (3) lit. b)'), 200);
      expect(find.text('Art. 100 alin. (3) lit. b)'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Sugestii de apărare'), 200);
      expect(find.text(avertismentLexSnap), findsOneWidget);
    });

    testWidgets('fără text în poză: mesaj și câmp de scris', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: LexSnapScreen(
            ocr: _OcrFals('  '),
            alegeImagine: (s) async =>
                s == ImageSource.gallery ? '/p.jpg' : null,
          ),
        ),
      );
      await t.tap(find.text('Din galerie'));
      await t.pumpAndSettle();
      expect(find.textContaining('Nu am găsit text'), findsOneWidget);
      expect(find.byKey(const Key('lexsnap_text')), findsOneWidget);
    });
  });
}

class _OcrFals implements OcrService {
  final String text;
  _OcrFals(this.text);

  @override
  Future<String> citeste(String cale) async => text;
}
