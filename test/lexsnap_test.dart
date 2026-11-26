import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:legal_management_app/lexsnap/analiza_document.dart';
import 'package:legal_management_app/lexsnap/fisier_service.dart';
import 'package:legal_management_app/lexsnap/lexsnap_service.dart';
import 'package:legal_management_app/lexsnap/ocr_service.dart';
import 'package:legal_management_app/lexsnap/sugestii_aparare.dart';
import 'package:legal_management_app/lexsnap/surse_aparare.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
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

    test('somația creditorului cu ordonanță de plată: art. 1014, art. 45 după act', () {
      final a = analizeazaDocument(
        'SOMAȚIE. Potrivit art. 1350 din Codul civil, sunteți în întârziere. '
        'Vom formula cerere de emitere a ordonanței de plată, conform '
        'art. 1014 și următoarele din Codul de procedură civilă. Raportul de '
        'muncă e guvernat de Legea nr. 53/2003 – Codul muncii, art. 45.',
      );
      expect(a.tipDocument?.nume, startsWith('Somație / cerere de ordonanță de plată'));
      final cpc = a.acte.firstWhere((x) => x.cerere.numar == '134');
      expect(cpc.articole.map((x) => x.articol), contains('1014'));
      expect(cpc.articole.map((x) => x.articol), isNot(contains('712')));
      final muncii = a.acte.firstWhere((x) => x.eticheta.contains('Codul muncii'));
      expect(muncii.articole.map((x) => x.articol), contains('45'));
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
      final r = await PregatireSurse(
        service: service,
        forme: FormaConsolidataService.cuClient(
          MockClient((_) async => http.Response('', 500)),
        ),
      ).pregateste(p);
      final surse = r.surse;
      expect(r.acte[surse.first.id]?.numar, '2');
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

  test(
    'coduri: articolul luat din codul anexat, nu din legea scurtă',
    () async {
      final lege = _lege(
        'LEGE',
        '287',
        'LEGE nr. 287 din 17 iulie 2009 privind Codul civil',
        'Articolul 1 Se aprobă Codul civil.',
      );
      final cod = _lege(
        'COD',
        '0',
        'CODUL CIVIL din 17 iulie 2009 ( Legea nr. 287/2009 )',
        'Articolul 1.349\nRăspunderea delictuală\n(1) Orice persoană are '
            'îndatorirea să respecte regulile de conduită pe care legea le impune.'
            '\nArticolul 1.350\n(1) Text.',
      );
      final service = LegislatieService.cuClient(
        MockClient((r) async {
          if (r.body.contains('GetToken')) {
            return http.Response.bytes(utf8.encode(_raspunsToken), 200);
          }
          final legi = r.body.contains('nr. 287 din')
              ? [lege]
              : r.body.contains('Codul civil')
              ? [cod]
              : <String>[];
          return http.Response.bytes(utf8.encode(_raspuns(legi)), 200);
        }),
      );
      final a = analizeazaDocument(
        'răspundere conform art. 1.349 din Codul civil',
      );
      final p = await cautaPrevederi(a, service: service).toList();
      final r = await PregatireSurse(
        service: service,
        forme: FormaConsolidataService.cuClient(
          MockClient((_) async => http.Response('', 500)),
        ),
      ).pregateste(p);
      expect(r.surse.single.articol, '1349');
      expect(r.surse.single.text, contains('îndatorirea să respecte'));
      expect(r.acte['S1']?.tipAct, 'COD');
    },
  );

  group('ecranul LexSnap', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('sugestii AI: doar cele cu citat exact', (t) async {
      final furnizor = _FurnizorFals([
        const SugestieAparare('Plângerea se face în 15 zile.', [
          CitareLegala(
            sursa: 'S1',
            articol: '31',
            alineat: '1',
            citat: 'se poate face plângere în termen de 15 zile',
          ),
        ]),
        const SugestieAparare('Inventată.', [
          CitareLegala(
            sursa: 'S1',
            articol: '31',
            citat: 'termen de 90 de zile',
          ),
        ]),
      ]);
      await t.pumpWidget(
        MaterialApp(
          home: LexSnapScreen(
            ocr: _OcrFals(
              'Sancțiune conform OG 2/2001. Plângere art. 31. CNP 1850101123456',
            ),
            alegeImagine: (_) async => '/p.jpg',
            service: LegislatieService.cuClient(_client()),
            forme: FormaConsolidataService.cuClient(
              MockClient((_) async => http.Response('', 500)),
            ),
            furnizorSugestii: furnizor,
          ),
        ),
      );
      await t.tap(find.text('Fotografiază'));
      Future<void> asteapta() async {
        for (var i = 0; i < 20; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await t.pump();
        }
      }

      await asteapta();
      t.view.physicalSize = const Size(1200, 4000);
      addTearDown(t.view.reset);
      await t.pump();
      await t.ensureVisible(find.text('Generează sugestii'));
      await t.pump();
      await t.tap(find.text('Generează sugestii'));
      await t.pumpAndSettle();
      await t.tap(find.text('Trimite'));
      await asteapta();
      expect(furnizor.surse.single.articol, '31');
      expect(
        find.textContaining('Plângerea se face în 15 zile.'),
        findsOneWidget,
      );
      expect(find.textContaining('Inventată'), findsNothing);
      expect(find.textContaining('Am ascuns o sugestie'), findsOneWidget);
    });

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
  group('fișiere (PDF și imagini)', () {
    test('PDF: textul din fișier; paginile scanate cu OCR', () async {
      final ocr = _OcrPeCale({
        '/tmp/p1.png': 'Text scanat de pe pagina a doua, conform OG 2/2001.',
      });
      final pdf = _PdfFals([
        'Pagina 1: PROCES-VERBAL de constatare a contravenției, text din fișier.',
        '',
        '  ',
      ]);
      final progres = <String>[];
      final r = await CititorFisiere(
        ocr: ocr,
        deschidePdf: (_) async => pdf,
      ).citeste('/doc.PDF', progres: (p, t) => progres.add('$p/$t'));
      expect(r.pagini, 3);
      expect(r.paginiOcr, 2);
      expect(r.trunchiat, isFalse);
      expect(r.text, contains('text din fișier'));
      expect(r.text, contains('Text scanat'));
      expect(ocr.citite, ['/tmp/p1.png', '/tmp/p2.png']);
      expect(progres, ['1/3', '2/3', '3/3']);
      expect(pdf.inchis, isTrue);
      expect(analizeazaDocument(r.text).acte.single.cerere.numar, '2');
    });

    test('PDF lung: doar primele $maxPaginiPdf pagini', () async {
      final pdf = _PdfFals(
        List.filled(
          40,
          'Pagina cu destul text ca să nu fie considerată scanată.',
        ),
      );
      final r = await CititorFisiere(
        ocr: _OcrPeCale({}),
        deschidePdf: (_) async => pdf,
      ).citeste('/a.pdf');
      expect(r.pagini, maxPaginiPdf);
      expect(r.trunchiat, isTrue);
    });

    test('imagine: direct la OCR', () async {
      final ocr = _OcrPeCale({'/poza.jpeg': 'Somație de plată'});
      final r = await CititorFisiere(
        ocr: ocr,
        deschidePdf: (_) => throw StateError('nu e PDF'),
      ).citeste('/poza.jpeg');
      expect(r.text, 'Somație de plată');
    });

    testWidgets('ecranul: încarcă un PDF', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(
        MaterialApp(
          home: LexSnapScreen(
            ocr: _OcrPeCale({}),
            alegeFisier: () async => '/dosar/pv.pdf',
            deschidePdf: (_) async => _PdfFals([_procesVerbal, _procesVerbal]),
            service: LegislatieService.cuClient(_client()),
          ),
        ),
      );
      await t.tap(find.text('Încarcă fișier (PDF, JPG, PNG)'));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      expect(find.text('PDF, 2 pagini'), findsOneWidget);
      expect(find.text('Proces-verbal de contravenție'), findsOneWidget);
    });

    testWidgets('ecranul: fișier de alt tip', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(
        MaterialApp(home: LexSnapScreen(alegeFisier: () async => '/a.docx')),
      );
      await t.tap(find.text('Încarcă fișier (PDF, JPG, PNG)'));
      await t.pump();
      expect(find.textContaining('Pot citi doar PDF'), findsOneWidget);
    });
  });
}

class _OcrPeCale implements OcrService {
  final Map<String, String> texte;
  final citite = <String>[];
  _OcrPeCale(this.texte);

  @override
  Future<String> citeste(String cale) async {
    citite.add(cale);
    return texte[cale] ?? '';
  }
}

class _PdfFals implements SursaPdf {
  final List<String> pagini;
  bool inchis = false;
  _PdfFals(this.pagini);

  @override
  Future<int> get numarPagini async => pagini.length;

  @override
  Future<String> text(int i) async => pagini[i];

  @override
  Future<String> imagine(int i) async => '/tmp/p$i.png';

  @override
  Future<void> inchide() async => inchis = true;
}

class _FurnizorFals implements FurnizorSugestii {
  final List<SugestieAparare> raspuns;
  List<ArticolSursa> surse = const [];
  _FurnizorFals(this.raspuns);

  @override
  bool get disponibil => true;

  @override
  Future<List<SugestieAparare>> sugereaza(
    String textDocument,
    List<ArticolSursa> s,
  ) async {
    surse = s;
    return raspuns;
  }
}

class _OcrFals implements OcrService {
  final String text;
  _OcrFals(this.text);

  @override
  Future<String> citeste(String cale) async => text;
}
