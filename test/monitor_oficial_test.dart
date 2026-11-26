import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legal_management_app/screens/monitor_oficial_screen.dart';
import 'package:legal_management_app/services/legislatie_service.dart';
import 'package:legal_management_app/services/monitor_oficial_service.dart';
import 'package:legal_management_app/services/sursa_legislatie_mo.dart';

ActPublicat _act(
  String tip,
  String titlu, {
  String numar = '1',
  String emitent = '',
  DateTime? zi,
  String monitor = '1050',
}) => ActPublicat(
  tip: tip,
  numar: numar,
  titlu: titlu,
  emitent: emitent,
  monitor: monitor,
  dataPublicarii: zi ?? DateTime(2026, 11, 24),
  link: 'https://legislatie.just.ro/Public/DetaliiDocument/${titlu.hashCode}',
);

DomeniuInteres _predefinit(String id) => domeniiPredefinite.firstWhere((d) => d.id == id);

class _SursaFalsa implements SursaMonitorOficial {
  final Map<DateTime, List<ActPublicat>> zile;
  final cereri = <DateTime>[];
  _SursaFalsa(this.zile);

  @override
  String get nume => 'test';

  @override
  Future<List<ActPublicat>> actePublicate(DateTime zi) async {
    cereri.add(zi);
    return zile[zi] ?? const [];
  }
}

void main() {
  group('potrivirea pe domenii', () {
    test('cuvintele prind începuturi de cuvânt, fără diacritice', () {
      final fiscal = _predefinit('fiscal');
      expect(
        fiscal.potriveste(_act('LEGE', 'pentru modificarea Legii nr. 227/2015 privind Codul fiscal')),
        isTrue,
      );
      expect(fiscal.potriveste(_act('ORDIN', 'privind impozitarea veniturilor din chirii')), isTrue);
      expect(fiscal.potriveste(_act('ORDIN', 'privind impozitul pe clădiri')), isTrue);
      expect(fiscal.potriveste(_act('ORDIN', 'privind taxele locale')), isTrue);
      expect(fiscal.potriveste(_act('HOTARARE', 'privind organizarea concursului de admitere')), isFalse);
    });

    test('cuvintele scurte (TVA) trebuie să fie întregi', () {
      final d = const DomeniuInteres(id: 'x', nume: 'x', cuvinte: ['TVA']);
      expect(d.potriveste(_act('ORDIN', 'privind cotele de TVA')), isTrue);
      expect(d.potriveste(_act('ORDIN', 'privind activitatea tvarului')), isFalse);
    });

    test('emitentul ajunge la domeniile predefinite', () {
      final fiscal = _predefinit('fiscal');
      final a = _act(
        'ORDIN',
        'pentru aprobarea modelului formularului 212',
        emitent: 'Agenția Națională de Administrare Fiscală',
      );
      expect(fiscal.motivPotrivire(a), 'Agenția Națională de Administrare Fiscală');
    });

    test('deciziile CCR după emitent', () {
      final ccr = _predefinit('ccr');
      expect(
        ccr.potriveste(_act('DECIZIE', 'referitoare la excepția de neconstituționalitate',
            emitent: 'Curtea Constituțională')),
        isTrue,
      );
      expect(ccr.potriveste(_act('DECIZIE', 'privind ceva', emitent: 'Guvernul României')), isFalse);
    });

    test('domeniul propriu: cuvinte ȘI emitent, tip, excluse', () {
      final d = DomeniuInteres(
        id: 'p',
        nume: 'Executare',
        cuvinte: cuvinteDinText('executare silită, poprir'),
        emitenti: ['Ministerul Justiției'],
        tipuri: {'ORDIN'},
        excluse: ['rectificare'],
      );
      final bun = _act('ORDIN', 'privind popririle asupra conturilor',
          emitent: 'Ministerul Justiției');
      expect(d.potriveste(bun), isTrue);
      // Alt emitent: nu (combinare „toate”).
      expect(
        d.potriveste(_act('ORDIN', 'privind executarea silită', emitent: 'Ministerul Finanțelor')),
        isFalse,
      );
      // Alt tip: nu.
      expect(
        d.potriveste(_act('LEGE', 'privind executarea silită', emitent: 'Ministerul Justiției')),
        isFalse,
      );
      // Cuvânt exclus: nu.
      expect(
        d.potriveste(_act('ORDIN', 'rectificare la ordinul privind poprirea',
            emitent: 'Ministerul Justiției')),
        isFalse,
      );
      expect(d.copyWith(combinare: Combinare.oricare).potriveste(
          _act('ORDIN', 'privind executarea silită', emitent: 'Ministerul Finanțelor')), isTrue);
    });

    test('un domeniu gol nu prinde nimic', () {
      const d = DomeniuInteres(id: 'g', nume: 'gol');
      expect(d.gol, isTrue);
      expect(d.potriveste(_act('LEGE', 'orice')), isFalse);
    });

    test('un act prins de mai multe domenii apare o dată, cu toate', () {
      final a = _act('LEGE', 'pentru modificarea Codului de procedură civilă și a Codului fiscal');
      final g = potriveste([a, a], [_predefinit('fiscal'), _predefinit('civil'), _predefinit('legi')]);
      expect(g, hasLength(1));
      expect(g.single.domenii, [
        'Fiscal și contabilitate',
        'Drept civil și procedură civilă',
        'Toate legile și ordonanțele',
      ]);
    });

    test('ordinea: legile înaintea ordinelor', () {
      final g = potriveste([
        _act('ORDIN', 'privind Codul fiscal', monitor: '1049'),
        _act('LEGE', 'pentru modificarea Codului fiscal', monitor: '1051'),
      ], [_predefinit('fiscal')]);
      expect(g.map((x) => x.act.tip), ['LEGE', 'ORDIN']);
    });

    test('domeniile se salvează și se citesc', () {
      final d = DomeniuInteres(
        id: 'p',
        nume: 'N',
        cuvinte: ['a b'],
        emitenti: ['E'],
        tipuri: {'LEGE'},
        excluse: ['x'],
        combinare: Combinare.oricare,
      );
      final c = DomeniuInteres.fromJson(d.toJson());
      expect(c.toJson(), d.toJson());
    });
  });

  group('raportul de dimineață', () {
    test('acoperă ieri; lunea și weekendul', () {
      expect(zileRaport(DateTime(2026, 11, 25, 8), ultimulRaport: DateTime(2026, 11, 24, 8)),
          [DateTime(2026, 11, 24)]);
      // Luni, ultimul raport vineri: vineri, sâmbătă, duminică.
      expect(zileRaport(DateTime(2026, 11, 30, 8), ultimulRaport: DateTime(2026, 11, 27, 8)), [
        DateTime(2026, 11, 27),
        DateTime(2026, 11, 28),
        DateTime(2026, 11, 29),
      ]);
      // Prima dată: doar ieri. După o vacanță: cel mult 4 zile.
      expect(zileRaport(DateTime(2026, 11, 25, 8)), [DateTime(2026, 11, 24)]);
      expect(zileRaport(DateTime(2026, 11, 25, 8), ultimulRaport: DateTime(2026, 11, 1)), hasLength(4));
    });

    test('textul notificării', () {
      final g = potriveste([_act('LEGE', 'privind Codul fiscal', numar: '312')], [_predefinit('fiscal')]);
      final t = textRaportMO(g, [DateTime(2026, 11, 24)]);
      expect(t.titlu, 'Monitorul Oficial · 1 act');
      expect(t.sumar, 'Pe domeniile tale, 24 noiembrie 2026');
      expect(t.linii.single, '• Lege nr. 312 privind Codul fiscal');
      expect(textRaportMO(const [], [DateTime(2026, 11, 24)]).sumar,
          'Nimic nou pe domeniile tale (24 noiembrie 2026)');
    });

    test('ora raportului, o dată pe zi', () async {
      SharedPreferences.setMockInitialValues({});
      final mo = MonitorOficialService.instance;
      await mo.incarca();
      mo
        ..predefiniteAlese = {}
        ..proprii = []
        ..ultimulRaport = null
        ..ora = 8
        ..minut = 0
        ..raportActiv = true;
      // Fără domenii, fără raport.
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 25, 9)), isFalse);
      mo.predefiniteAlese = {'fiscal'};
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 25, 7, 59)), isFalse);
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 25, 9)), isTrue);
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 25, 14)), isFalse);
      await mo.marcheazaRaport(DateTime(2026, 11, 25, 9), const []);
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 25, 10)), isFalse);
      expect(mo.eTimpulRaportului(DateTime(2026, 11, 26, 8, 5)), isTrue);
    });

    test('raportul și alertele cu o sursă falsă', () async {
      SharedPreferences.setMockInitialValues({});
      final mo = MonitorOficialService.instance;
      await mo.incarca();
      final ieri = DateTime(2026, 11, 24);
      final azi = DateTime(2026, 11, 25);
      final sursa = _SursaFalsa({
        ieri: [
          _act('LEGE', 'privind Codul fiscal', numar: '312'),
          _act('HOTARARE', 'privind aprobarea bugetului', numar: '900'),
        ],
        azi: [_act('ORDIN', 'privind impozitul pe venit', numar: '44', zi: azi)],
      });
      mo
        ..sursa = sursa
        ..predefiniteAlese = {'fiscal'}
        ..proprii = []
        ..anuntate = {}
        ..ultimulRaport = DateTime(2026, 11, 24, 8);

      final r = await mo.raport(DateTime(2026, 11, 25, 8, 10));
      expect(r!.zile, [ieri]);
      expect(r.gasite.map((g) => g.act.numar), ['312']);
      await mo.marcheazaRaport(DateTime(2026, 11, 25, 8, 10), r.gasite);

      final noi = await mo.noiAzi(DateTime(2026, 11, 25, 12));
      expect(noi.map((g) => g.act.numar), ['44']);
      // A doua oară nu mai e nou, iar sursa nu e întrebată din nou prea curând.
      final cereri = sursa.cereri.length;
      expect(await mo.noiAzi(DateTime(2026, 11, 25, 13)), isEmpty);
      expect(sursa.cereri.length, cereri);
      // Peste 3 ore, da.
      await mo.noiAzi(DateTime(2026, 11, 25, 15, 30));
      expect(sursa.cereri.length, cereri + 1);
    });
  });

  group('sursa Portalul Legislativ', () {
    test('Monitorul din câmpul Publicatie', () {
      final m = monitorDinPublicatie('MONITORUL OFICIAL nr. 1.050 bis din 24 noiembrie 2026');
      expect(m!.monitor, '1050 bis');
      expect(m.zi, DateTime(2026, 11, 24));
      expect(monitorDinPublicatie('MONITORUL OFICIAL nr. 223 din 9 aprilie 2010')!.zi,
          DateTime(2010, 4, 9));
      expect(frazaZi(DateTime(2026, 11, 4)), 'din 4 noiembrie 2026');
    });

    test('păstrează doar actele publicate în ziua cerută', () {
      ActNormativ a(String titlu, String publicatie) => ActNormativ(
        tipAct: 'LEGE',
        numar: '312',
        titlu: titlu,
        emitent: 'Parlamentul',
        publicatie: publicatie,
        linkHtml: 'https://legislatie.just.ro/Public/DetaliiDocument/1',
        text: '',
      );
      final zi = DateTime(2026, 11, 24);
      final bun = actPublicatDin(
        a('LEGE nr. 312 din 20 noiembrie 2026 privind Codul fiscal',
            'MONITORUL OFICIAL nr. 1050 din 24 noiembrie 2026'),
        zi,
      );
      expect(bun!.titlu, 'privind Codul fiscal');
      expect(bun.monitor, '1050');
      // Emis pe 24, publicat pe 26: nu e al zilei.
      expect(
        actPublicatDin(
          a('LEGE nr. 313 din 24 noiembrie 2026 privind ceva',
              'MONITORUL OFICIAL nr. 1060 din 26 noiembrie 2026'),
          zi,
        ),
        isNull,
      );
    });
  });

  testWidgets('ecranul arată actele de ieri pe domeniile alese', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mo = MonitorOficialService.instance;
    await mo.incarca();
    final ieri = DateTime(2026, 11, 24);
    mo
      ..sursa = _SursaFalsa({
        ieri: [
          _act('LEGE', 'privind Codul fiscal', numar: '312'),
          _act('HOTARARE', 'privind aprobarea bugetului', numar: '900'),
        ],
      })
      ..predefiniteAlese = {'fiscal'}
      ..proprii = [];
    await mo.salveaza();

    await tester.pumpWidget(
      MaterialApp(home: MonitorOficialScreen(acum: DateTime(2026, 11, 25, 9))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ieri, 24 noiembrie 2026'), findsOneWidget);
    expect(find.text('Lege nr. 312'), findsOneWidget);
    expect(find.text('Hotărâre nr. 900'), findsNothing);

    await tester.tap(find.text('Toate actele'));
    await tester.pumpAndSettle();
    expect(find.text('Hotărâre nr. 900'), findsOneWidget);
  });

  test('Publicatie fără număr: Monitorul se ia din antetul titlului', () {
    // Forma reală a răspunsului (26.11.2026): Publicatie e doar „Monitorul Oficial”.
    const xml = '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<SearchResponse xmlns="http://tempuri.org/"><SearchResult '
        'xmlns:a="http://schemas.datacontract.org/2004/07/FreeWebService"><a:Legi>'
        '<a:DataVigoare>2026-11-25</a:DataVigoare><a:Emitent>Curtea Constitutionala</a:Emitent>'
        '<a:LinkHtml>http://legislatie.just.ro/Public/DetaliiDocument/316590</a:LinkHtml>'
        '<a:Numar>398</a:Numar><a:Publicatie>Monitorul Oficial</a:Publicatie>'
        '<a:Text> DECIZIA nr. 398 din 30 aprilie 2026 </a:Text><a:TipAct>DECIZIE</a:TipAct>'
        '<a:Titlu> DECIZIA nr. 398 din 30 aprilie 2026  referitoare la excepția de '
        'neconstituționalitate      EMITENT      Curtea Constituțională       PUBLICAT ÎN \n'
        '\t\t\t  Monitorul Oficial nr. 979 din 25 noiembrie 2026     </a:Titlu>'
        '</a:Legi></SearchResult></SearchResponse></s:Body></s:Envelope>';
    final acte = parseazaRaspunsCautare(xml);
    expect(acte.single.publicatie, 'Monitorul Oficial nr. 979 din 25 noiembrie 2026');
    final p = actPublicatDin(acte.single, DateTime(2026, 11, 25));
    expect(p, isNotNull);
    expect(p!.monitor, '979');
    expect(p.dataPublicarii, DateTime(2026, 11, 25));
  });
}
