import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/screens/act_normativ_screen.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';

String fixture(String nume) => utf8.decode(
  gzip.decode(File('test/fixtures/legislatie/$nume.gz').readAsBytesSync()),
);

/// Răspunsurile portalului pentru actele din fixture-uri.
MockClient clientPortal({Map<String, String> pagini = const {}}) =>
    MockClient((r) async {
      final id = RegExp(r'(\d+)$').firstMatch(r.url.path)?.group(1);
      if (r.url.path.endsWith('actiuniSuferite')) {
        final contor = r.bodyFields['contor'];
        final f = File('test/fixtures/legislatie/actiuni_$contor.json.gz');
        if (!f.existsSync()) return http.Response('{"acte":""}', 200);
        return http.Response.bytes(gzip.decode(f.readAsBytesSync()), 200);
      }
      final pagina = pagini[id];
      if (pagina == null) return http.Response('nu', 404);
      return http.Response.bytes(
        gzip.decode(File('test/fixtures/legislatie/$pagina').readAsBytesSync()),
        200,
      );
    });

void main() {
  group('forma la zi (pagina actului)', () {
    final f307 = formaDinHtml(fixture('307_consolidat.html'))!;

    test('antetul și data consolidării', () {
      expect(f307.titlu, 'LEGEA nr. 307 din 12 iulie 2006 (*republicată*)');
      expect(f307.descriere, 'privind apărarea împotriva incendiilor');
      expect(f307.emitent, 'PARLAMENTUL ROMÂNIEI');
      expect(f307.publicatie, 'MONITORUL OFICIAL nr. 297 din 17 aprilie 2019');
      expect(f307.dataConsolidare, DateTime(2026, 5, 8));
      expect(f307.numarModificari, greaterThan(150));
    });

    test('articole, alineate, litere și capitole', () {
      final b = f307.blocuri;
      expect(
        b.where((x) => x.tip == TipBloc.articol).length,
        greaterThanOrEqualTo(60),
      );
      final cap = b.firstWhere((x) => x.tip == TipBloc.structura);
      expect(cap.eticheta, 'Capitolul I');
      expect(cap.titlu, 'Dispoziții generale');
      final i = indiceArticol(b, '1')!;
      expect(b[i + 1].eticheta, '(1)');
      expect(b[i + 1].text, startsWith('Apărarea împotriva incendiilor'));
    });

    test('modificarea are data, felul, elementul și actul', () {
      final note = f307.blocuri.where((x) => x.modificare != null).toList();
      final m = note.first.modificare!;
      expect(m.data, DateTime(2021, 6, 30));
      expect(m.tip, TipModificare.modificat);
      expect(m.element, startsWith('Partea introductivă a alineatului (2)'));
      expect(m.act, contains('ORDONANȚA DE URGENȚĂ nr. 80'));
      expect(m.idAct, '243954');
      expect(
        note.map((n) => n.modificare!.tip).toSet(),
        containsAll([
          TipModificare.modificat,
          TipModificare.completat,
          TipModificare.abrogat,
        ]),
      );
    });

    test('alineatul abrogat e marcat, cu actul care l-a abrogat', () {
      final b = f307.blocuri;
      final i = indiceArticol(b, '10')!;
      final aln = b.skip(i).firstWhere((x) => x.abrogat);
      expect(aln.eticheta, '(2)');
      final nota = b[b.indexOf(aln) + 1];
      expect(nota.modificare!.tip, TipModificare.abrogat);
      expect(nota.modificare!.element, contains('Alineatul (2)'));
    });

    test('art. 45: punctele „I.”, „II.” cu literele dedesubt', () {
      final b = f307.blocuri;
      final i = indiceArticol(b, '45')!;
      expect(b[i + 1].text, startsWith('Constituie contravenții'));
      expect(b[i + 2].eticheta, 'I.');
      expect(b[i + 2].tip, TipBloc.alineat);
      expect(b[i + 3].eticheta, 'a)');
      expect(b[i + 3].tip, TipBloc.litera);
    });

    test('trimiterile către alte acte au id-ul lor', () {
      final b = f307.blocuri.firstWhere(
        (x) => x.text.startsWith('Legea nr. 28/2018'),
      );
      final l = b.legaturi.first;
      expect(b.text.substring(l.start, l.end), 'Legea nr. 28/2018');
      expect(l.idAct, '196800');
    });

    test('HG 273/1994: anexa trimite la regulament', () {
      final f = formaDinHtml(fixture('hg273_consolidat.html'))!;
      expect(f.titlu, 'HOTĂRÂRE nr. 273 din 14 iunie 1994');
      final anexa = f.blocuri.indexWhere((x) => x.eticheta == 'Anexă');
      final ref = f.blocuri[anexa + 1];
      expect(ref.text, 'REGULAMENT privind recepția construcțiilor');
      expect(ref.legaturi.single.idAct, '188977');
      expect(f.blocuri.first.modificare!.element, 'Titlul actului normativ');
    });

    test('forma veche (CPC 1865): articole, litere și note', () {
      final f = formaDinHtml(fixture('cpc1865_consolidat.html'))!;
      expect(
        f.titlu,
        startsWith('CODUL DE PROCEDURĂ CIVILĂ din 9 septembrie 1865'),
      );
      expect(f.dataConsolidare, DateTime(2013, 1, 31));
      final b = f.blocuri;
      expect(b.where((x) => x.tip == TipBloc.articol).length, greaterThan(700));
      final i = indiceArticol(b, '2')!;
      final a = b.skip(i).firstWhere((x) => x.tip == TipBloc.litera);
      expect(a.eticheta, 'a)');
      expect(a.abrogat, isTrue);
      expect(
        b.where(
          (x) => x.tip == TipBloc.nota && x.text.startsWith('Pct. 2 al art. 1'),
        ),
        isNotEmpty,
      );
      expect(b.where((x) => RegExp(r'^-{3,}$').hasMatch(x.text)), isEmpty);
    });

    test('Legea 50/1991: abrogată de Codul din 2026', () {
      final f = formaDinHtml(fixture('abrogat_1515.html'))!;
      expect(f.titlu, 'LEGE nr. 50 din 29 iulie 1991 (**republicată**)');
      final s = StareAct(actiuniDinJson(fixture('actiuni_1515.json')));
      expect(s.abrogat, isTrue);
      expect(s.abrogatDe!.idAct, '313329');
      expect(s.abrogatDe!.denumireAct, 'Codul din 05.08.2026');
      final ist = actiuniDinForma(f);
      expect(ist.first.sectiune, 'ART. 1');
      expect(
        ist.where((a) => a.operatie == 'COMPLETAT DE'),
        isNotEmpty,
        reason: '„a fost introdus” e o completare',
      );
    });

    test('pagină fără act: null', () {
      expect(formaDinHtml('<html><body>Eroare</body></html>'), isNull);
    });

    test('act deschis după id: tipul și numărul din titlu', () {
      final a = actDinForma(f307, linkAct('73657'));
      expect(a.tipAct, 'LEGE');
      expect(a.numar, '307');
      expect(a.denumireScurta, 'Lege nr. 307/2006');
    });
  });

  group('acțiuni suferite', () {
    test('Legea 307/2006 e în vigoare, cu modificări pe articole', () {
      final s = StareAct(actiuniDinJson(fixture('actiuni_73657.json')));
      expect(s.actiuni, hasLength(54));
      expect(s.abrogat, isFalse);
      final a = s.actiuni.first;
      expect(a.sectiune, 'Actul');
      expect(a.operatie, 'MODIFICAT DE');
      expect(a.denumireAct, 'Legea nr. 146/2017');
      expect(a.idAct, '190432');
      expect(a.data, DateTime(2017, 6, 26));
    });

    test('Codul de procedură civilă din 1865 e abrogat de Legea 76/2012', () {
      final s = StareAct(actiuniDinJson(fixture('actiuni_39374.json')));
      expect(s.abrogat, isTrue);
      expect(s.abrogatDe!.denumireAct, 'Legea nr. 76/2012');
      expect(s.abrogatDe!.idAct, '138484');
      expect(s.ordonate.first.peTotActul, isTrue);
    });

    test('istoricul ia și modificările noi din forma la zi', () {
      final s = StareAct(actiuniDinJson(fixture('actiuni_73657.json')));
      final f = formaDinHtml(fixture('307_consolidat.html'))!;
      final ist = istoricComplet(s, f);
      expect(ist.length, greaterThan(s.actiuni.length));
      expect(ist.first.peTotActul, isTrue);
      final nou = ist.firstWhere((a) => !a.peTotActul);
      expect(nou.data!.year, 2026);
      expect(nou.denumireAct, startsWith('OUG nr. '));
      expect(
        ist.where(
          (a) => a.sectiune == 'ART. 10' && a.operatieText == 'abrogat de',
        ),
        isNotEmpty,
      );
    });

    test('denumiri scurte', () {
      expect(
        denumireDinText(
          'Punctul 1, Articolul III din ORDONANȚA DE URGENȚĂ nr. 80 din 30 iunie 2021, publicată în MONITORUL OFICIAL',
        ),
        'OUG nr. 80/2021',
      );
      expect(
        denumireActScurta('ORD DE URGENTA        80 30/06/2021'),
        'OUG nr. 80/2021',
      );
      expect(denumireActScurta('HOTARARE   343 18/05/2017'), 'HG nr. 343/2017');
      expect(denumireActScurta('ceva'), 'ceva');
    });

    test('răspuns stricat: nicio acțiune', () {
      expect(actiuniDinJson('nu e json'), isEmpty);
    });
  });

  test('modificare din text', () {
    final m = modificareDinText(
      '(la 13-03-2026, Articolul 3 , Capitolul I a fost completat de Punctul 2. , Articolul VI din OUG nr. 17)',
      idAct: '308251',
    )!;
    expect(m.tip, TipModificare.completat);
    expect(m.element, 'Articolul 3, Capitolul I');
    expect(m.data, DateTime(2026, 3, 13));
    expect(modificareDinText('Text oarecare'), isNull);
  });

  testWidgets('ecranul actului: în vigoare, text la zi, istoric', (
    tester,
  ) async {
    final fs = FormaConsolidataService.cuClient(
      clientPortal(pagini: {'73657': '307_consolidat.html.gz'}),
    );
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: ActNormativScreen(
          act: const ActNormativ(
            tipAct: 'LEGE',
            numar: '307',
            titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea împotriva incendiilor',
            emitent: 'PARLAMENTUL',
            publicatie: 'MONITORUL OFICIAL nr. 633 din 21 iulie 2006',
            linkHtml: 'https://legislatie.just.ro/Public/DetaliiDocument/73657',
            text: 'Articolul 1\nTextul inițial.',
          ),
          formaService: fs,
        ),
      ),
    );
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 50 && find.textContaining('ultima modificare').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(find.text('În vigoare'), findsOneWidget);
    expect(find.textContaining('ultima modificare: 08.05.2026'), findsOneWidget);
    expect(find.textContaining('Istoric ('), findsOneWidget);
    // Textul legii se poate selecta și copia.
    expect(find.byType(SelectionArea), findsOneWidget);

    await tester.tap(find.text('Forma inițială'));
    await tester.pump();
    expect(find.textContaining('Afișez forma inițială'), findsWidgets);

    await tester.tap(find.textContaining('Istoric ('));
    await tester.pumpAndSettle();
    expect(find.text('Istoricul actului'), findsOneWidget);
    expect(find.textContaining('Legea nr. 146/2017'), findsWidgets);
  });

  testWidgets('act abrogat: spune prin ce', (tester) async {
    final fs = FormaConsolidataService.cuClient(clientPortal());
    await tester.pumpWidget(
      MaterialApp(
        home: ActNormativScreen(
          act: const ActNormativ(
            tipAct: 'COD',
            numar: '0',
            titlu: 'CODUL DE PROCEDURĂ CIVILĂ (*republicat*)',
            emitent: '',
            publicatie: '',
            linkHtml: 'https://legislatie.just.ro/Public/DetaliiDocument/39374',
            text: 'Articolul 1\nText.',
          ),
          formaService: fs,
        ),
      ),
    );
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 50 && find.text('Act abrogat').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(find.text('Act abrogat'), findsOneWidget);
    expect(find.textContaining('Legea nr. 76/2012'), findsWidgets);
    expect(find.text('Deschide Legea nr. 76/2012'), findsOneWidget);
  });
}
