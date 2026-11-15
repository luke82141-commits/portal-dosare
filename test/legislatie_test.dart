import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/screens/act_normativ_screen.dart';
import 'package:legal_management_app/screens/legislatie_screen.dart';
import 'package:legal_management_app/services/legislatie_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raspunsToken =
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
    '<GetTokenResponse xmlns="http://tempuri.org/"><GetTokenResult>abc-123</GetTokenResult>'
    '</GetTokenResponse></s:Body></s:Envelope>';

String _lege({
  String tip = 'LEGE',
  String numar = '85',
  String titlu = 'LEGE nr. 85 din 25 iunie 2014 privind procedurile de prevenire a insolvenței și de insolvență',
  String emitent = 'PARLAMENTUL',
  String data = '2014-06-28T00:00:00',
  String text =
      'TITLUL I\nArt. 1\nScopul legii\nArt. 2\nInsolvența debitorului &lt;b&gt;x&lt;/b&gt;',
}) =>
    '<a:Legi><a:DataVigoare>$data</a:DataVigoare><a:Emitent>$emitent</a:Emitent>'
    '<a:LinkHtml>http://legislatie.just.ro/Public/DetaliiDocument/155854</a:LinkHtml>'
    '<a:Numar>$numar</a:Numar><a:Publicatie>MONITORUL OFICIAL nr. 466 din 25 iunie 2014</a:Publicatie>'
    '<a:Text>$text</a:Text><a:TipAct>$tip</a:TipAct><a:Titlu>$titlu</a:Titlu></a:Legi>';

String _raspunsCautare(List<String> legi) =>
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
    '<SearchResponse xmlns="http://tempuri.org/">'
    '<SearchResult xmlns:a="http://schemas.datacontract.org/2004/07/FreeWebService" '
    'xmlns:i="http://www.w3.org/2001/XMLSchema-instance">${legi.join()}</SearchResult>'
    '</SearchResponse></s:Body></s:Envelope>';

void main() {
  setUp(() => LegislatieService.pauzaIntreCereri = Duration.zero);

  group('cererea SOAP', () {
    test('câmpurile goale pleacă nil, în ordine alfabetică, cu tokenul', () {
      final x = cerereCautare(const CerereLegislatie(text: 'a & b'), token: 'T', pagina: 2);
      expect(x, contains('<d:NumarPagina>2</d:NumarPagina>'));
      expect(x, contains('<d:RezultatePagina>20</d:RezultatePagina>'));
      expect(x, contains('<d:SearchAn i:nil="true"/>'));
      expect(x, contains('<d:SearchText>a &amp; b</d:SearchText>'));
      expect(x, contains('<tokenKey>T</tokenKey>'));
      final ordine = [
        'NumarPagina',
        'RezultatePagina',
        'SearchAn',
        'SearchNumar',
        'SearchText',
        'SearchTitlu',
      ].map((c) => x.indexOf('<d:$c')).toList();
      expect(ordine, orderedEquals([...ordine]..sort()));
    });

    test('pagina 0 devine 1', () {
      expect(
        cerereCautare(const CerereLegislatie(text: 'x'), token: 'T', pagina: 0),
        contains('<d:NumarPagina>1<'),
      );
    });
  });

  group('răspunsul', () {
    test('se citesc actele, linkul trece pe https, HTML-ul din text dispare', () {
      final acte = parseazaRaspunsCautare(_raspunsCautare([_lege()]));
      expect(acte, hasLength(1));
      final a = acte.single;
      expect(a.tipAct, 'LEGE');
      expect(a.numar, '85');
      expect(a.an, 2014);
      expect(a.denumireScurta, 'Lege nr. 85/2014');
      expect(a.dataVigoare, DateTime(2014, 6, 28));
      expect(a.linkHtml, 'https://legislatie.just.ro/Public/DetaliiDocument/155854');
      expect(a.text, isNot(contains('<b>')));
      expect(a.text, contains('Insolvența debitorului x'));
    });

    test('tokenul', () => expect(parseazaToken(_raspunsToken), 'abc-123'));

    test('eroarea SOAP devine mesaj', () {
      const fault =
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
          '<faultcode>s:Client</faultcode><faultstring>Token invalid</faultstring></s:Fault></s:Body></s:Envelope>';
      expect(() => parseazaRaspunsCautare(fault), throwsA(isA<LegislatieException>()));
    });
  });

  group('bara de căutare', () {
    test('„Legea 85/2014” = număr + an + tip', () {
      final r = CerereLegislatie.dinText('Legea nr. 85/2014');
      expect(r.cerere.numar, '85');
      expect(r.cerere.an, 2014);
      expect(r.cerere.text, isEmpty);
      expect(r.tip, 'LEGE');
    });

    test('„oug 195/2002” și „O.U.G. 195/2002”', () {
      expect(CerereLegislatie.dinText('oug 195/2002').tip, 'ORDONANTA DE URGENTA');
      expect(CerereLegislatie.dinText('O.U.G. 195/2002').tip, 'ORDONANTA DE URGENTA');
      expect(CerereLegislatie.dinText('HG 1/2016').tip, 'HOTARARE');
    });

    test('„287/2009” fără tip', () {
      final r = CerereLegislatie.dinText('287/2009');
      expect(r.cerere.numar, '287');
      expect(r.tip, isNull);
    });

    test('altceva = text liber', () {
      final r = CerereLegislatie.dinText('protecția consumatorului');
      expect(r.cerere.text, 'protecția consumatorului');
      expect(r.cerere.numar, isEmpty);
    });
  });

  group('filtre', () {
    final acte = parseazaRaspunsCautare(
      _raspunsCautare([
        _lege(),
        _lege(
          tip: 'ORDONANTA DE URGENTA',
          numar: '195',
          titlu: 'ORDONANȚĂ DE URGENȚĂ nr. 195 din 12 decembrie 2002',
          emitent: 'GUVERNUL ROMÂNIEI',
          data: '2003-01-01T00:00:00',
        ),
        _lege(
          tip: 'ORDONANTA',
          numar: '2',
          titlu: 'ORDONANȚĂ nr. 2 din 12 iulie 2001',
          emitent: 'GUVERNUL ROMÂNIEI',
          data: '2001-08-01T00:00:00',
        ),
      ]),
    );

    test('tip: Ordonanță nu prinde și OUG', () {
      final r = aplicaFiltre(acte, const FiltreLegislatie(tipuri: {'ORDONANTA'}));
      expect(r.map((a) => a.numar), ['2']);
      final oug = aplicaFiltre(acte, const FiltreLegislatie(tipuri: {'ORDONANTA DE URGENTA'}));
      expect(oug.map((a) => a.numar), ['195']);
    });

    test('emitent fără diacritice', () {
      final r = aplicaFiltre(acte, const FiltreLegislatie(emitent: 'guvernul romaniei'));
      expect(r, hasLength(2));
    });

    test('interval de ani și ordine', () {
      final r = aplicaFiltre(
        acte,
        const FiltreLegislatie(anDe: 2002, ordine: OrdineLegislatie.celeMaiVechi),
      );
      expect(r.map((a) => a.numar), ['195', '85']);
      final noi = aplicaFiltre(acte, const FiltreLegislatie(ordine: OrdineLegislatie.celeMaiNoi));
      expect(noi.first.numar, '85');
    });

    test('emitenții, cei mai des întâlniți primii', () {
      expect(emitentiDin(acte).first, 'GUVERNUL ROMÂNIEI');
    });
  });

  group('obiectul dosarului', () {
    test('lege cu număr și an', () {
      final t = trimiteriDinObiect('anulare act - Legea nr. 10/2001');
      expect(t.single.eticheta, 'Lege 10/2001');
      expect(t.single.cerere.numar, '10');
      expect(t.single.cerere.an, 2001);
    });

    test('OUG și cod de procedură', () {
      final t = trimiteriDinObiect('contestaţie la executare (art. 712 C.proc.civ.) OUG 195/2002');
      expect(t.map((x) => x.eticheta), ['OUG 195/2002', 'Codul de procedură civilă']);
      expect(t.last.cerere.numar, '134');
    });

    test('codul penal din obiect penal', () {
      final t = trimiteriDinObiect('furt calificat (art.229 C.pen.)');
      expect(t.single.eticheta, 'Codul penal');
    });

    test('fără trimiteri → căutare după obiect', () {
      final t = trimiteriDinObiect('pretenţii');
      expect(t.single.cerere.text, 'pretenţii');
    });

    test('obiect gol', () => expect(trimiteriDinObiect(''), isEmpty));
  });

  group('textul actului', () {
    final p = paragrafeAct(
      'TITLUL I\nArt. 1\nScopul\nAlineat\nArt. 2\nInsolvența\nArt. 3\nAltceva',
    );

    test('„art. 2” arată doar articolul', () {
      final s = selecteazaParagrafe(p, 'art. 2');
      expect(s.articol, '2');
      expect(s.paragrafe, ['Art. 2', 'Insolvența']);
      expect(selecteazaParagrafe(p, '1').paragrafe, ['Art. 1', 'Scopul', 'Alineat']);
    });

    test('cuvânt fără diacritice', () {
      expect(selecteazaParagrafe(p, 'insolventa').paragrafe, ['Insolvența']);
    });

    test('articol inexistent', () {
      expect(selecteazaParagrafe(p, 'art. 99').paragrafe, isEmpty);
    });

    test('evidențierea păstrează textul', () {
      final b = evidentieri('Insolvența și insolvență', 'insolventa');
      expect(b.map((s) => s.text).join(), 'Insolvența și insolvență');
      expect(b.where((s) => s.style != null), hasLength(2));
    });
  });

  group('serviciul', () {
    test('cere token o dată, apoi caută; cererea identică vine din memorie', () async {
      final actiuni = <String>[];
      final client = MockClient((r) async {
        final a = r.headers['SOAPAction']!;
        actiuni.add(a);
        if (a.contains('GetToken')) return http.Response(_raspunsToken, 200);
        expect(r.body, contains('<tokenKey>abc-123</tokenKey>'));
        return http.Response.bytes(_utf8(_raspunsCautare([_lege()])), 200);
      });
      final s = LegislatieService.cuClient(client);
      final p = await s.cauta(const CerereLegislatie(numar: '85', an: 2014));
      expect(p.acte.single.numar, '85');
      expect(p.maiSunt, isFalse);
      await s.cauta(const CerereLegislatie(numar: '85', an: 2014));
      await s.cauta(const CerereLegislatie(numar: '85', an: 2014), pagina: 2);
      expect(actiuni.where((a) => a.contains('GetToken')), hasLength(1));
      expect(actiuni.where((a) => a.contains('Search')), hasLength(2));
    });

    test('la eroare reîncearcă o dată cu token nou', () async {
      var cautari = 0;
      var tokenuri = 0;
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken')) {
          tokenuri++;
          return http.Response(_raspunsToken, 200);
        }
        cautari++;
        if (cautari == 1) return http.Response('', 500);
        return http.Response.bytes(_utf8(_raspunsCautare([_lege()])), 200);
      });
      final p = await LegislatieService.cuClient(client).cauta(const CerereLegislatie(text: 'x'));
      expect(p.acte, hasLength(1));
      expect(tokenuri, 2);
    });

    test('fără internet → mesaj clar', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      await expectLater(
        LegislatieService.cuClient(client).cauta(const CerereLegislatie(text: 'x')),
        throwsA(isA<LegislatieException>().having((e) => e.mesaj, 'mesaj', contains('internet'))),
      );
    });
  });

  group('ecranele', () {
    testWidgets('căutarea afișează actul și se deschide', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken')) return http.Response(_raspunsToken, 200);
        return http.Response.bytes(_utf8(_raspunsCautare([_lege()])), 200);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: construiesteTema(),
          home: LegislatieScreen(service: LegislatieService.cuClient(client)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coduri și legi des folosite'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Legea 85/2014');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      expect(find.text('1 act'), findsOneWidget);
      expect(find.text('Lege'), findsOneWidget); // filtrul de tip a fost pus automat
      await tester.tap(find.textContaining('privind procedurile de prevenire'));
      await tester.pumpAndSettle();
      expect(find.byType(ActNormativScreen), findsOneWidget);
      expect(find.text('Forma de pe portal'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'art. 2');
      await tester.pump();
      expect(find.text('Articolul 2'), findsOneWidget);
    });
  });
}

List<int> _utf8(String s) => utf8.encode(s);
