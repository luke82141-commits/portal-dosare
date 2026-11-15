import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/data/acte_cunoscute.dart';
import 'package:legal_management_app/screens/act_normativ_screen.dart';
import 'package:legal_management_app/screens/legislatie_screen.dart';
import 'package:legal_management_app/services/act_export.dart';
import 'package:legal_management_app/services/act_structura.dart';
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
  String id = '155854',
  String text = 'TITLUL I\nArt. 1\nScopul legii\nArt. 2\nInsolvența debitorului &lt;b&gt;x&lt;/b&gt;',
}) =>
    '<a:Legi><a:DataVigoare>$data</a:DataVigoare><a:Emitent>$emitent</a:Emitent>'
    '<a:LinkHtml>http://legislatie.just.ro/Public/DetaliiDocument/$id$tip$numar</a:LinkHtml>'
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
      final x = cerereCautare(
        const CerereLegislatie(text: 'a & b'),
        token: 'T',
        pagina: 2,
      );
      expect(x, contains('<d:NumarPagina>2</d:NumarPagina>'));
      expect(x, contains('<d:RezultatePagina>10</d:RezultatePagina>'));
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
    test(
      'se citesc actele, linkul trece pe https, HTML-ul din text dispare',
      () {
        final acte = parseazaRaspunsCautare(_raspunsCautare([_lege()]));
        expect(acte, hasLength(1));
        final a = acte.single;
        expect(a.tipAct, 'LEGE');
        expect(a.numar, '85');
        expect(a.an, 2014);
        expect(a.denumireScurta, 'Lege nr. 85/2014');
        expect(a.dataVigoare, DateTime(2014, 6, 28));
        expect(
          a.linkHtml,
          'https://legislatie.just.ro/Public/DetaliiDocument/155854LEGE85',
        );
        expect(a.text, isNot(contains('<b>')));
        expect(a.text, contains('Insolvența debitorului x'));
      },
    );

    test('tokenul', () => expect(parseazaToken(_raspunsToken), 'abc-123'));

    test('eroarea SOAP devine mesaj', () {
      const fault =
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
          '<faultcode>s:Client</faultcode><faultstring>Token invalid</faultstring></s:Fault></s:Body></s:Envelope>';
      expect(
        () => parseazaRaspunsCautare(fault),
        throwsA(isA<LegislatieException>()),
      );
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
      expect(
        CerereLegislatie.dinText('oug 195/2002').tip,
        'ORDONANTA DE URGENTA',
      );
      expect(
        CerereLegislatie.dinText('O.U.G. 195/2002').tip,
        'ORDONANTA DE URGENTA',
      );
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
      final r = aplicaFiltre(
        acte,
        const FiltreLegislatie(tipuri: {'ORDONANTA'}),
      );
      expect(r.map((a) => a.numar), ['2']);
      final oug = aplicaFiltre(
        acte,
        const FiltreLegislatie(tipuri: {'ORDONANTA DE URGENTA'}),
      );
      expect(oug.map((a) => a.numar), ['195']);
    });

    test('emitent fără diacritice', () {
      final r = aplicaFiltre(
        acte,
        const FiltreLegislatie(emitent: 'guvernul romaniei'),
      );
      expect(r, hasLength(2));
    });

    test('interval de ani și ordine', () {
      final r = aplicaFiltre(
        acte,
        const FiltreLegislatie(
          anDe: 2002,
          ordine: OrdineLegislatie.celeMaiVechi,
        ),
      );
      expect(r.map((a) => a.numar), ['195', '85']);
      final noi = aplicaFiltre(
        acte,
        const FiltreLegislatie(ordine: OrdineLegislatie.celeMaiNoi),
      );
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
      final t = trimiteriDinObiect(
        'contestaţie la executare (art. 712 C.proc.civ.) OUG 195/2002',
      );
      expect(t.map((x) => x.eticheta), [
        'OUG 195/2002',
        'Codul de procedură civilă',
      ]);
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

  group('structura actului', () {
    const text =
        'TITLUL PRELIMINAR\nDespre legea civilă\nCAPITOLUL I\nDispoziții generale\n'
        'Art. 1. - Izvoarele dreptului civil\n(1) Sunt izvoare ale dreptului civil legea, uzanțele.\n'
        '(2) În cazurile neprevăzute de lege se aplică uzanțele.\n'
        '(la 01-10-2011 Art. 1 a fost modificat de Legea nr. 71/2011)\n'
        'Articolul 2\nObiectul și conținutul Codului civil\n'
        'Dispozițiile prezentului cod reglementează raporturile patrimoniale.\n'
        'a) persoanele fizice;\nb) persoanele juridice.\n'
        'Art. 5^1\nAplicarea prioritară\nPartea interesată trebuie să facă dovada.';
    final b = structureazaAct(text);

    test('titluri, capitole, articole, alineate, litere și note', () {
      expect(b.map((x) => x.tip).toList(), [
        TipBloc.structura,
        TipBloc.structura,
        TipBloc.articol,
        TipBloc.alineat,
        TipBloc.alineat,
        TipBloc.nota,
        TipBloc.articol,
        TipBloc.text,
        TipBloc.litera,
        TipBloc.litera,
        TipBloc.articol,
        TipBloc.text,
      ]);
      expect(b[0].eticheta, 'TITLUL PRELIMINAR');
      expect(b[0].titlu, 'Despre legea civilă');
      expect(b[1].eticheta, 'CAPITOLUL I');
      expect(b[2].eticheta, 'Art. 1');
      expect(b[2].titlu, 'Izvoarele dreptului civil');
      expect(b[3].eticheta, '(1)');
      expect(b[6].titlu, 'Obiectul și conținutul Codului civil');
      expect(b[8].eticheta, 'a)');
      expect(b[10].articol, '5^1');
      // „Partea interesată...” nu e titlu de structură.
      expect(b[11].tip, TipBloc.text);
    });

    test('textul real de pe portal: „+”, denumiri și alineate lipite', () {
      const real =
          'Aplicarea legii penale în timp\n+\nArticolul 3 Activitatea legii penale Legea penală se '
          'aplică infracţiunilor săvârșite în timpul cât ea se află în vigoare. ...\n+\n'
          'Articolul 4 Aplicarea legii penale de dezincriminare Legea penală nu se aplică '
          'faptelor săvârșite sub legea veche, dacă nu mai sunt prevăzute de legea nouă. În acest '
          'caz, executarea pedepselor, a măsurilor educative și a măsurilor de siguranţă, '
          'pronunţate în baza legii vechi, precum și toate consecinţele penale ale hotărârilor '
          'judecătorești privitoare la aceste fapte încetează prin intrarea în vigoare a legii noi.\n+\n'
          'Articolul 5 Aplicarea legii penale mai favorabile până la judecarea definitivă a cauzei '
          '(1) În cazul în care au intervenit una sau mai multe legi penale, se aplică legea mai '
          'favorabilă. ... (2) Dispoziţiile alin. (1) se aplică și actelor normative următoare: '
          'a) declarate neconstituţionale; b) aprobate cu modificări.\n+\n'
          'Articolul 6 Prezenta lege intră în vigoare la data publicării în Monitorul Oficial.';
      final r = structureazaAct(real);
      expect(r.where((x) => x.textComplet == '+'), isEmpty);
      expect(r.where((x) => x.text.contains('...')), isEmpty);
      final art = r.where((x) => x.tip == TipBloc.articol).toList();
      expect(art.map((x) => x.eticheta), [
        'Art. 3',
        'Art. 4',
        'Art. 5',
        'Art. 6',
      ]);
      expect(art[0].titlu, 'Activitatea legii penale');
      expect(art[1].titlu, 'Aplicarea legii penale de dezincriminare');
      expect(
        art[2].titlu,
        'Aplicarea legii penale mai favorabile până la judecarea definitivă a cauzei',
      );
      expect(art[3].titlu, isEmpty);
      final i5 = indiceArticol(r, '5')!;
      final b5 = blocuriArticol(r, i5);
      expect(b5.map((x) => x.eticheta), ['Art. 5', '(1)', '(2)', 'a)', 'b)']);
      expect(b5[2].text, startsWith('Dispoziţiile alin. (1) se aplică'));
      expect(
        r[indiceArticol(r, '4')! + 1].text,
        startsWith('Legea penală nu se aplică'),
      );
    });

    test('textul real al portalului: blocuri „+”, spații, „...” și note', () {
      const real =
          ' LEGE nr. 287 din 17 iulie 2009  privind Codul civil     EMITENT     PARLAMENTUL       '
          'Publicat în \n\t\t\t  MONITORUL OFICIAL nr. 511 din 24 iulie 2009     Parlamentul '
          'României adoptă prezenta lege.   \n\t\t\t\t + \n\t\t\t  Titlul PRELIMINAR   Despre '
          'legea civilă    \n\t\t\t\t + \n\t\t\t  Capitolul I   Dispoziţii generale    \n\t\t\t\t + '
          '\n\t\t\t  Articolul 1     Obiectul Codului civil  Dispoziţiile prezentului cod '
          'reglementează raporturile patrimoniale.     \n\t\t\t\t + \n\t\t\t  Articolul 3     '
          'Aplicarea generală a Codului civil      (1) Dispoziţiile prezentului cod se aplică şi '
          'raporturilor dintre profesionişti.   ...        (2) Sunt consideraţi profesionişti '
          'toţi cei care exploatează o întreprindere.   ...       \n\t\t\t\t + \n\t\t\t  '
          'Articolul 4     Prezenta lege intră în vigoare la data publicării.     \n\t\t\t\t + '
          '\n\t\t\t  Articolul 5      Obiectul de reglementare    (1)     Obiectivele '
          'generale sunt:  a)    satisfacerea nevoilor;    ...     b)    utilizarea '
          'rațională a teritoriului;    ...       (2)    Termenii sunt în  anexa nr. 1 .       ';
      final text = textFaraAntet(real);
      expect(text, startsWith('Parlamentul României'));
      final b = structureazaAct(text);
      expect(
        b.where((x) => x.text.contains('...') || x.textComplet.trim() == '+'),
        isEmpty,
      );
      final art = b.where((x) => x.tip == TipBloc.articol).toList();
      expect(art.map((x) => x.eticheta), [
        'Art. 1',
        'Art. 3',
        'Art. 4',
        'Art. 5',
      ]);
      expect(art.map((x) => x.titlu), [
        'Obiectul Codului civil',
        'Aplicarea generală a Codului civil',
        '',
        'Obiectul de reglementare',
      ]);
      final s = b.where((x) => x.tip == TipBloc.structura).toList();
      expect(s.first.eticheta, 'TITLUL PRELIMINAR');
      expect(s.first.titlu, 'Despre legea civilă');
      expect(s[1].titlu, 'Dispoziţii generale');
      final a5 = blocuriArticol(b, indiceArticol(b, '5')!);
      expect(a5.map((x) => x.eticheta), ['Art. 5', '(1)', 'a)', 'b)', '(2)']);
      expect(a5[1].text, 'Obiectivele generale sunt:');
      expect(a5[2].text, 'satisfacerea nevoilor;');
      final a3 = blocuriArticol(b, indiceArticol(b, '3')!);
      expect(a3.map((x) => x.eticheta), ['Art. 3', '(1)', '(2)']);
      expect(
        b[indiceArticol(b, '4')! + 1].text,
        'Prezenta lege intră în vigoare la data publicării.',
      );
    });

    test('puncte cu cifre romane și litere după „:”', () {
      const t =
          'x\n\t\t\t\t + \n\t\t\t  Articolul 45     Constituie contravenţii următoarele fapte şi se '
          'sancţionează după cum urmează: I. cu amendă de la 500 lei la 1.000 lei:  a)    '
          'nerespectarea obligaţiilor;    ...     b)    neasigurarea mijloacelor;    ...    '
          'II. cu amendă de la 1.000 lei la 2.500 lei: a) neîntocmirea planului; b) altceva.   ...   ';
      final b = structureazaAct(t);
      final a = blocuriArticol(b, indiceArticol(b, '45')!);
      expect(a.map((x) => x.eticheta), [
        'Art. 45',
        '',
        'I.',
        'a)',
        'b)',
        'II.',
        'a)',
        'b)',
      ]);
      expect(
        a[1].text,
        'Constituie contravenţii următoarele fapte şi se sancţionează după cum urmează:',
      );
      expect(a[2].text, 'cu amendă de la 500 lei la 1.000 lei:');
      expect(a[2].tip, TipBloc.alineat);
    });

    test('„legea 307 incendii”: tip, număr și cuvinte din titlu', () {
      final d = CerereLegislatie.dinText('legea 307 incendii');
      expect(d.cerere.numar, '307');
      expect(d.cerere.an, isNull);
      expect(d.cerere.cuvinte, 'incendii');
      expect(d.tip, 'LEGE');
      final e = CerereLegislatie.dinText('Legea nr. 307/2006 incendii');
      expect(e.cerere.an, 2006);
      final acte = parseazaRaspunsCautare(
        _raspunsCautare([
          _lege(
            numar: '307',
            id: '1',
            titlu: 'LEGE nr. 307 din 5 decembrie 2024 privind un centru',
          ),
          _lege(
            numar: '307',
            id: '2',
            titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea împotriva incendiilor',
          ),
        ]),
      );
      expect(potrivireExacta(acte, d.cerere, d.tip)?.an, 2006);
      expect(sugestii('legea 307 incendii').first.deschideDirect, isTrue);
    });

    test('ordine liberă: numărul, tipul și anul oriunde în frază', () {
      final a = CerereLegislatie.dinText('incendii legea 307');
      expect(
        (a.cerere.numar, a.tip, a.cerere.cuvinte),
        ('307', 'LEGE', 'incendii'),
      );
      final b = CerereLegislatie.dinText(
        'apararea impotriva incendiilor 307 2006',
      );
      expect((b.cerere.numar, b.cerere.an, b.tip), ('307', 2006, null));
      expect(b.cerere.cuvinte, 'apararea impotriva incendiilor');
      final c = CerereLegislatie.dinText('ordonanta de urgenta 195 circulatia');
      expect((c.cerere.numar, c.tip), ('195', 'ORDONANTA DE URGENTA'));
      final d = CerereLegislatie.dinText('hg 1 2020');
      expect((d.cerere.numar, d.cerere.an, d.tip), ('1', 2020, 'HOTARARE'));
      expect(
        CerereLegislatie.dinText('codul fiscal 2015').cerere.text,
        'codul fiscal 2015',
      );
      expect(
        CerereLegislatie.dinText('codul civil art. 1357 alin 2').cerere.numar,
        isEmpty,
      );
    });

    test('cuvinte în orice ordine găsesc legea după titlu', () async {
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken')) {
          return http.Response(_raspunsToken, 200);
        }
        if (r.body.contains(
          '<d:SearchTitlu>incendi* aparare*</d:SearchTitlu>',
        )) {
          return http.Response.bytes(
            _utf8(
              _raspunsCautare([
                _lege(
                  numar: '1',
                  id: '1',
                  titlu: 'ORDIN nr. 1 din 2 mai 2010 privind incendiilor ceva',
                ),
                _lege(
                  numar: '307',
                  id: '2',
                  titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea împotriva incendiilor',
                ),
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
      });
      final p = await LegislatieService.cuClient(client)
          .cauta(const CerereLegislatie(text: 'incendiilor apararea'));
      expect(p.acte.first.numar, '307');
      expect(
        ordoneazaDupaRelevanta(p.acte, 'incendiilor apararea').first.numar,
        '307',
      );
    });

    test('emitent cu „?” și titlu cu antet', () {
      expect(emitentReparat('Pre?edintele României'), 'Președintele României');
      expect(
        emitentReparat('Înalta Curte de Casa?ie ?i Justi?ie'),
        'Înalta Curte de Casație și Justiție',
      );
      expect(
        emitentReparat('Curtea Constitu?ională'),
        'Curtea Constituțională',
      );
      expect(
        titluFaraAntet(
          "﻿  DECIZIE nr. 578 privind domnul G\\'f6nczi  EMITENT: GUVERNUL PUBLICAT ÎN: X",
        ),
        'DECIZIE nr. 578 privind domnul Gönczi',
      );
      expect(etichetaTip('HOTĂRÂRE'), 'Hotărâre');
      expect(etichetaTip('ORDONANȚĂ DE URGENȚĂ'), 'OUG');
      expect(titluPentruNumar('1212', 'DECRET'), 'DECRET nr. 1.212 din');
      expect(titluPentruNumar('307', 'LEGE'), 'LEGE nr. 307 din');
      expect(titluPentruNumar('12345', null), 'nr. 12.345 din');
    });

    test('mergi la articol, inclusiv „5^1”', () {
      expect(indiceArticol(b, '2'), 6);
      expect(indiceArticol(b, 'art. 5^1'), 10);
      expect(indiceArticol(b, '99'), isNull);
    });

    test('textul articolului de copiat are sursa și fără note', () {
      final t = textArticol(b, 2, 'Lege nr. 287/2009');
      expect(
        t,
        startsWith('Art. 1 - Izvoarele dreptului civil\n(1) Sunt izvoare'),
      );
      expect(t, isNot(contains('modificat')));
      expect(t, endsWith('(art. 1 din Lege nr. 287/2009)'));
    });

    test('cuprinsul are titlurile și articolele, pe niveluri', () {
      final c = cuprins(b);
      expect(c.first.text, 'TITLUL PRELIMINAR · Despre legea civilă');
      expect(c.where((e) => e.eArticol), hasLength(3));
      expect(c[1].nivel, greaterThan(c[0].nivel));
    });

    test('căutarea în act ignoră diacriticele', () {
      expect(potriviri(b, 'uzante'), [3, 4]);
      expect(pozitii('Uzanțele și uzanțe', 'uzante'), [(0, 6), (12, 18)]);
    });

    test('text fără rânduri noi e despărțit pe articole', () {
      final lung = List.generate(
        30,
        (i) =>
            'Art. ${i + 1}. - Denumire $i (1) Primul alineat al articolului cu text destul de lung.',
      ).join(' ');
      final s = structureazaAct(lung);
      expect(s.where((x) => x.tip == TipBloc.articol), hasLength(30));
      expect(s.where((x) => x.tip == TipBloc.alineat), hasLength(30));
    });
  });

  group('fragmentul din rezultat', () {
    const text =
        'CARTEA a III-a\nDespre bunuri\nArt. 930. - Uzucapiunea extratabulară\n'
        '(1) Dreptul de proprietate asupra unui imobil se poate înscrie în cartea funciară, '
        'în temeiul uzucapiunii, în folosul celui care l-a posedat timp de 10 ani.\n'
        'Art. 931. - Alte cazuri\n(1) Drepturile asupra unui imobil se dobândesc prin uzucapiune.';

    test(
      'termenul în titlul articolului: arată articolul și primul alineat',
      () {
        final f = fragmentDinAct(text, 'uzucapiune')!;
        expect(f.articol, 'Art. 930 · Uzucapiunea extratabulară');
        expect(f.text, startsWith('Dreptul de proprietate'));
        expect(f.inceputTaiat, isFalse);
      },
    );

    test('termenul în corp: fără „(1)”, tăiat la cuvinte întregi', () {
      final f = fragmentDinAct(text, 'posedat', latime: 20)!;
      expect(f.articol, 'Art. 930 · Uzucapiunea extratabulară');
      expect(f.text, isNot(startsWith('(1)')));
      expect(f.text, contains('posedat'));
      expect(f.inceputTaiat, isTrue);
      expect(f.text.split(' ').first, isNot(isEmpty));
    });

    test(
      'fără potrivire',
      () => expect(fragmentDinAct(text, 'divorț'), isNull),
    );
  });

  group('titlul din card', () {
    ActNormativ act(String tip, String nr, String titlu) =>
        parseazaRaspunsCautare(
          _raspunsCautare([_lege(tip: tip, numar: nr, titlu: titlu)]),
        ).single;

    test('codul: nume scurt, data și „republicat” dedesubt', () {
      final t = titluPrezentare(
        act('LEGE', '287', 'CODUL CIVIL din 17 iulie 2009 (**republicat**)'),
      );
      expect(t.principal, 'Codul civil');
      expect(t.secundar, 'din 17 iulie 2009 · republicat');
    });

    test('legea: fără tip și număr repetate', () {
      final t = titluPrezentare(
        act(
          'LEGE',
          '7',
          'LEGE nr. 7 din 13 martie 1996 a cadastrului și a publicității imobiliare',
        ),
      );
      expect(t.principal, 'Legea cadastrului și a publicității imobiliare');
      expect(t.secundar, 'din 13 martie 1996');
    });

    test('OUG și hotărâre', () {
      expect(
        titluPrezentare(
          act(
            'ORDONANTA DE URGENTA',
            '195',
            'ORDONANȚĂ DE URGENȚĂ nr. 195 din 12 decembrie 2002 privind circulația pe drumurile publice',
          ),
        ).principal,
        'Codul rutier',
      );
      expect(
        titluPrezentare(
          act(
            'HOTARARE',
            '700',
            'HOTĂRÂRE nr. 700 din 4 iulie 2012 pentru modificarea normelor',
          ),
        ).principal,
        'Hotărârea pentru modificarea normelor',
      );
    });
  });

  group('sugestii', () {
    test('„codul civ” propune Codul civil primul, apoi procedura civilă', () {
      final s = sugestii('codul civ');
      expect(s.first.titlu, 'Codul civil');
      expect(s.first.cerere.numar, '287');
      expect(s.first.deschideDirect, isTrue);
      expect(s.map((x) => x.titlu), contains('Codul de procedură civilă'));
      expect(s.where((x) => x.fel == FelSugestie.text), hasLength(1));
    });

    test('abrevieri: „ncpc”, „c.pen”', () {
      expect(sugestii('ncpc').first.cerere.numar, '134');
      expect(sugestii('c.pen').first.titlu, 'Codul penal');
    });

    test('„codul civil art. 1357” duce la articol', () {
      final s = sugestii('codul civil art. 1357');
      expect(s.first.titlu, 'Codul civil · art. 1357');
      expect(s.first.articol, '1357');
      expect(extrageArticol('Legea 85/2014, art 5^1').articol, '5^1');
    });

    test('număr și an', () {
      final s = sugestii('oug 195/2002');
      expect(s.first.fel, FelSugestie.numar);
      expect(s.first.tip, 'ORDONANTA DE URGENTA');
    });

    test('relevanța pune actul de bază înaintea celor care îl modifică', () {
      final acte = parseazaRaspunsCautare(
        _raspunsCautare([
          _lege(numar: '1', titlu: 'LEGE pentru modificarea Legii insolvenței'),
          _lege(numar: '2', titlu: 'HOTĂRÂRE privind registrul agricol'),
          _lege(),
        ]),
      );
      final r = ordoneazaDupaRelevanta(acte, 'insolvență');
      expect(r.first.numar, '85');
      expect(r.last.numar, '2');
    });

    test(
      'căutarea din mai multe cuvinte alege un cuvânt rar pentru titluri',
      () {
        expect(cuvinteCheie('codul urbanismului'), ['urbanismului']);
        expect(cuvinteCheie('Codul amenajării teritoriului'), [
          'teritoriului',
          'amenajării',
        ]);
        expect(cuvinteCheie('insolvență'), ['insolvență']);
        expect(cuvinteCheie('legea de la'), isEmpty);
        expect(
          titluContineToate(
            'CODUL amenajării teritoriului, urbanismului şi construcţiilor',
            radaciniCautare('codul urbanismului'),
          ),
          isTrue,
        );
        expect(acteCunoscutePotrivite('codul urbanismului').first.numar, '169');
      },
    );

    test('legea care aprobă un cod: antet scos și codul găsit separat', () {
      const titlu =
          'LEGE nr. 169 din 5 august 2026 privind Codul amenajării teritoriului, '
          'urbanismului și construcţiilor EMITENT Parlamentul PUBLICAT ÎN Monitorul Oficial '
          'nr. 661 din 10 august 2026';
      final lege = parseazaRaspunsCautare(
        _raspunsCautare([
          _lege(
            numar: '169',
            titlu: titlu,
            text:
                'LEGE nr. 169 din 5 august 2026 privind Codul amenajării teritoriului, '
                'urbanismului și construcțiilor EMITENT PARLAMENTUL ROMÂNIEI Publicat în '
                'MONITORUL OFICIAL nr. 661 din 10 august 2026 CODUL AMENAJĂRII TERITORIULUI, '
                'URBANISMULUI ȘI CONSTRUCȚIILOR',
          ),
        ]),
      ).single;
      expect(lege.titlu, endsWith('construcţiilor'));
      expect(
        lege.text,
        'CODUL AMENAJĂRII TERITORIULUI, URBANISMULUI ȘI CONSTRUCȚIILOR',
      );
      final nume = numeCodAnexat(lege)!;
      expect(nume, startsWith('Codul amenajării teritoriului'));
      final rezultate = parseazaRaspunsCautare(
        _raspunsCautare([
          _lege(numar: '169', titlu: titlu),
          _lege(numar: '1', titlu: 'HOTĂRÂRE privind certificatul de urbanism'),
          _lege(
            numar: '0',
            tip: 'COD',
            titlu: 'CODUL amenajării teritoriului, urbanismului şi construcţiilor din 5 august 2026',
          ),
        ]),
      );
      expect(alegeCodAnexat(rezultate, lege, nume)?.tipAct, 'COD');
      expect(numeCodAnexat(rezultate[1]), isNull);
    });

    test('„legea 307” fără an: tipul și numărul, din toți anii', () {
      final d = CerereLegislatie.dinText('legea 307');
      expect(d.cerere.numar, '307');
      expect(d.cerere.an, isNull);
      expect(d.tip, 'LEGE');
      final s = sugestii('legea 307').first;
      expect(s.titlu, 'Lege nr. 307');
      expect(s.deschideDirect, isFalse);
      expect(
        CerereLegislatie.dinText('codul civil 2').cerere.text,
        'codul civil 2',
      );
    });

    test('„legea 307 2006” și „legea 307 din 2006” sunt număr și an', () {
      for (final x in [
        'legea 307 2006',
        'Legea nr. 307 din 2006',
        'legea 307/2006',
      ]) {
        final d = CerereLegislatie.dinText(x);
        expect(d.cerere.numar, '307', reason: x);
        expect(d.cerere.an, 2006, reason: x);
        expect(d.tip, 'LEGE', reason: x);
      }
    });

    test('filtrul de tip se uită și la titlu', () {
      final acte = parseazaRaspunsCautare(
        _raspunsCautare([
          _lege(
            tip: 'ACT',
            numar: '307',
            titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea',
          ),
        ]),
      );
      expect(
        aplicaFiltre(acte, const FiltreLegislatie(tipuri: {'LEGE'})),
        hasLength(1),
      );
      expect(
        aplicaFiltre(acte, const FiltreLegislatie(tipuri: {'HOTARARE'})),
        isEmpty,
      );
    });

    test('potrivirea exactă', () {
      final acte = parseazaRaspunsCautare(
        _raspunsCautare([_lege(tip: 'HOTARARE'), _lege()]),
      );
      final a = potrivireExacta(
        acte,
        const CerereLegislatie(numar: '85', an: 2014),
        'LEGE',
      );
      expect(a?.tipAct, 'LEGE');
    });
  });

  group('export', () {
    final act = parseazaRaspunsCautare(_raspunsCautare([_lege()])).single;
    final b = structureazaAct(
      'TITLUL I\nDispoziții\nArt. 1. - Scopul\n(1) Text cu diacritice: ăâîșț.\na) literă',
    );

    test('Word: arhivă cu documentul și articolele', () {
      final date = actDocx(act, b);
      final arhiva = ZipDecoder().decodeBytes(date);
      final doc = utf8.decode(
        arhiva.findFile('word/document.xml')!.content as List<int>,
      );
      expect(doc, contains('Art. 1'));
      expect(doc, contains('ăâîșț'));
      expect(numeFisierAct(act, 'docx'), 'Lege nr 85 2014.docx');
    });

    test('PDF cu fonturile aplicației', () async {
      Uint8List f(String n) =>
          File('assets/fonts/LiberationSerif-$n.ttf').readAsBytesSync();
      final date = await actPdf(
        act,
        b,
        fontNormal: f('Regular'),
        fontBold: f('Bold'),
        fontItalic: f('Italic'),
      );
      expect(String.fromCharCodes(date.take(5)), '%PDF-');
    });
  });

  group('favorite', () {
    test('se salvează și se scot', () async {
      SharedPreferences.setMockInitialValues({});
      final f = ActeSalvateService.instance..reseteaza();
      await f.incarca();
      final act = parseazaRaspunsCautare(_raspunsCautare([_lege()])).single;
      expect(await f.comuta(act), isTrue);
      expect(f.esteSalvat(act), isTrue);
      expect(f.acte.single.cerere.numar, '85');
      expect(f.acte.single.tip, 'LEGE');
      f.reseteaza();
      await f.incarca();
      expect(f.esteSalvat(act), isTrue);
      expect(await f.comuta(act), isFalse);
      expect(f.acte, isEmpty);
    });
  });

  group('serviciul', () {
    test('rădăcini cu „*” pentru căutarea în orice formă', () {
      expect(interogarePrefixe('regulament receptii'), 'regulament* recept*');
      expect(interogarePrefixe('codul urbanismului'), 'cod* urbanism*');
      expect(
        interogarePrefixe('legea apararea impotriva incendiilor'),
        'aparare* impotriv* incendi*',
      );
      expect(interogarePrefixe('ordinea publica AND or'), 'ordine* public*');
      expect(interogarePrefixe('de la'), '');
      expect(varianteFaraUnCuvant('regulament* recept*'), [
        'regulament*',
        'recept*',
      ]);
    });

    test('„regulament receptii” găsește Regulamentul de recepție', () async {
      final cereri = <String>[];
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken'))
          return http.Response(_raspunsToken, 200);
        cereri.add(r.body);
        if (r.body.contains(
          '<d:SearchTitlu>regulament* recept*</d:SearchTitlu>',
        )) {
          return http.Response.bytes(
            _utf8(
              _raspunsCautare([
                _lege(
                  numar: '1323',
                  id: '1',
                  titlu: 'ORDIN nr. 1.323 din 2026 pentru aprobarea Regulamentului de recepţie şi înscriere în cadastru',
                ),
                _lege(
                  numar: '273',
                  id: '2',
                  titlu: 'HOTĂRÂRE nr. 273 din 14 iunie 1994 privind aprobarea Regulamentului de recepţie a lucrărilor de construcţii',
                ),
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
      });
      final p = await LegislatieService.cuClient(client)
          .cauta(const CerereLegislatie(text: 'regulament receptii'));
      expect(p.acte.map((a) => a.numar).toSet(), {'1323', '273'});
    });

    test('fără titluri cu toate cuvintele, încearcă fără câte unul', () async {
      final titluri = <String>[];
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken'))
          return http.Response(_raspunsToken, 200);
        final m = RegExp(r'<d:SearchTitlu>(.*?)</d:SearchTitlu>')
            .firstMatch(r.body);
        if (m != null) titluri.add(m.group(1)!);
        if (m?.group(1) == 'incend*') {
          return http.Response.bytes(
            _utf8(
              _raspunsCautare([
                _lege(numar: '307', titlu: 'LEGE nr. 307 privind incendiilor'),
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
      });
      final p = await LegislatieService.cuClient(client)
          .cauta(const CerereLegislatie(text: 'incendii xyzw'));
      expect(p.acte.single.numar, '307');
      expect(titluri.first, 'incend* xyzw*');
    });

    test(
      'cere token o dată, apoi caută; cererea identică vine din memorie',
      () async {
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
        expect(actiuni.where((a) => a.contains('Search')), hasLength(1));
      },
    );

    test('„codul urbanismului” găsește codul prin titluri', () async {
      final cereri = <String>[];
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken'))
          return http.Response(_raspunsToken, 200);
        cereri.add(r.body);
        if (r.body.contains('<d:SearchTitlu>cod* urbanism*</d:SearchTitlu>')) {
          return http.Response.bytes(
            _utf8(
              _raspunsCautare([
                _lege(
                  numar: '169',
                  titlu: 'CODUL amenajării teritoriului, urbanismului şi construcţiilor',
                ),
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
      });
      final s = LegislatieService.cuClient(client);
      final p = await s.cauta(
        const CerereLegislatie(titlu: 'codul urbanismului'),
      );
      expect(p.acte.map((a) => a.numar), ['169']);
      expect(cereri.length, inInclusiveRange(2, 4));
    });

    test('Codul civil: după titlu, republicat întâi', () async {
      final cereri = <String>[];
      final client = MockClient((r) async {
        if (r.headers['SOAPAction']!.contains('GetToken')) {
          return http.Response(_raspunsToken, 200);
        }
        cereri.add(r.body);
        if (r.body.contains(
              '<d:SearchTitlu>LEGE nr. 287 din</d:SearchTitlu>',
            ) &&
            r.body.contains('<d:SearchAn>2009</d:SearchAn>')) {
          return http.Response.bytes(
            _utf8(
              _raspunsCautare([
                _lege(
                  numar: '287',
                  data: '2011-10-01T00:00:00',
                  titlu: '﻿   LEGE nr. 287 din 17 iulie 2009 privind Codul civil EMITENT: PARLAMENTUL',
                ),
                _lege(
                  numar: '287',
                  data: '2011-10-01T00:00:00',
                  id: '130142',
                  titlu: 'LEGE nr. 287 din 17 iulie 2009*) (*republicată*) privind Codul civil',
                ),
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
      });
      final s = LegislatieService.cuClient(client);
      final civil = acteCunoscute.firstWhere((a) => a.nume == 'Codul civil');
      final p = await s.cauta(cerereActCunoscut(civil));
      expect(cereri, hasLength(1));
      expect(p.acte, hasLength(2));
      expect(p.acte.first.titlu, contains('republicat'));
      expect(
        p.acte.last.titlu,
        'LEGE nr. 287 din 17 iulie 2009 privind Codul civil',
      );
      expect(p.acte.first.an, 2009);
      expect(p.acte.first.denumireScurta, 'Lege nr. 287/2009');
    });

    test(
      '„legea 307/2006”: anul din titlu, nu din intrarea în vigoare',
      () async {
        final ani = <String>[];
        final client = MockClient((r) async {
          if (r.headers['SOAPAction']!.contains('GetToken')) {
            return http.Response(_raspunsToken, 200);
          }
          ani.add(
            RegExp(r'<d:SearchAn>(\d+)').firstMatch(r.body)?.group(1) ?? '-',
          );
          if (r.body.contains('<d:SearchAn>2006</d:SearchAn>')) {
            return http.Response.bytes(
              _utf8(
                _raspunsCautare([
                  _lege(
                    numar: '307',
                    id: '292080',
                    data: '2025-01-01T00:00:00',
                    titlu: 'LEGE nr. 307 din 5 decembrie 2024 privind înfiinţarea unui centru',
                  ),
                  _lege(
                    numar: '307',
                    data: '2007-01-01T00:00:00',
                    titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea împotriva incendiilor',
                  ),
                ]),
              ),
              200,
            );
          }
          return http.Response.bytes(_utf8(_raspunsCautare([])), 200);
        });
        final d = CerereLegislatie.dinText('legea 307/2006');
        final p = await LegislatieService.cuClient(client).cauta(d.cerere);
        expect(ani, ['2006']);
        expect(p.acte.first.titlu, contains('apărarea împotriva incendiilor'));
        expect(potrivireExacta(p.acte, d.cerere, d.tip)?.numar, '307');
      },
    );

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
      final p = await LegislatieService.cuClient(client)
          .cauta(const CerereLegislatie(text: 'x'));
      expect(p.acte, hasLength(1));
      expect(tokenuri, 2);
    });

    test('fără internet → mesaj clar', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      await expectLater(
        LegislatieService.cuClient(client)
            .cauta(const CerereLegislatie(text: 'x')),
        throwsA(
          isA<LegislatieException>().having(
            (e) => e.mesaj,
            'mesaj',
            contains('internet'),
          ),
        ),
      );
    });
  });

  group('ecranele', () {
    testWidgets(
      'sugestii, deschidere directă, mergi la articol și căutare în act',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        ActeSalvateService.instance.reseteaza();
        final client = MockClient((r) async {
          if (r.headers['SOAPAction']!.contains('GetToken'))
            return http.Response(_raspunsToken, 200);
          return http.Response.bytes(
            _utf8(_raspunsCautare([_lege(tip: 'HOTARARE'), _lege()])),
            200,
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: construiesteTema(),
            home: LegislatieScreen(service: LegislatieService.cuClient(client)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Coduri și legi uzuale'), findsOneWidget);

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'codul civ');
        await tester.pump();
        expect(find.byType(Card), findsWidgets);
        expect(find.text('Legea nr. 287/2009'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Legea 85/2014 art. 2');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();

        // Deschis direct actul exact (Legea, nu Hotărârea), la articolul 2.
        expect(find.byType(ActNormativScreen), findsOneWidget);
        expect(find.text('Lege nr. 85/2014'), findsOneWidget);
        expect(find.text('Art. 2'), findsOneWidget);
        expect(find.text('Cuprins'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);

        await tester.tap(find.text('Caută în act'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'insolventa');
        await tester.pumpAndSettle();
        expect(find.text('1/1'), findsOneWidget);

        await tester.tap(find.byTooltip('Adaugă la favorite'));
        await tester.pumpAndSettle();
        expect(ActeSalvateService.instance.acte, hasLength(1));
      },
    );
  });
}

List<int> _utf8(String s) => utf8.encode(s);
