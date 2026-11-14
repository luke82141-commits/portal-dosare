import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/rezultate_screen.dart';
import 'package:legal_management_app/services/cautari_recente_service.dart';
import 'package:legal_management_app/services/parti_urmarite_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar _dosar(String numar, {String institutie = 'TribunalulPRAHOVA'}) => Dosar(
  numar: numar,
  data: DateTime(2026, 11, 1),
  institutie: institutie,
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [Parte(nume: 'ALFA SRL', calitate: 'Pârât')],
  sedinte: const [],
);

/// Portalul fals: întoarce lista curentă și ține minte cererile.
class _SoapFals extends SoapService {
  List<Dosar> dosare;
  bool limita;
  final cereri = <Map<String, Object?>>[];
  bool esueaza = false;

  _SoapFals(this.dosare, {this.limita = false});

  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async {
    if (esueaza) throw SoapException('fără rețea');
    cereri.add({'parte': numeParte, 'institutie': institutie, 'dataStart': dataStart});
    return RezultatCautare(dosare, limita);
  }
}

void main() {
  final service = PartiUrmariteService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await service.incarca();
  });

  test('Dosarele existente la adăugare nu sunt anunțate ca noi', () async {
    final soap = _SoapFals([_dosar('1/105/2026'), _dosar('2/105/2026')]);
    final limita = await service.adauga(
      ' Alfa SRL ',
      institutie: 'TribunalulPRAHOVA',
      soap: soap,
      acum: DateTime(2026, 11, 14),
    );

    expect(limita, isFalse);
    expect(service.urmareste('ALFA SRL', 'TribunalulPRAHOVA'), isTrue);
    expect(soap.cereri.single['parte'], 'Alfa SRL');
    expect(soap.cereri.single['institutie'], 'TribunalulPRAHOVA');
    expect(soap.cereri.single['dataStart'], DateTime(2026, 10, 15));

    final rezultate = await service.verificaToate(soap: soap);
    expect(rezultate, isEmpty);
    expect(service.totalNecitite, 0);
  });

  test('Un dosar nou e anunțat o singură dată și rămâne salvat', () async {
    final soap = _SoapFals([_dosar('1/105/2026')]);
    await service.adauga('Alfa SRL', soap: soap);

    soap.dosare = [_dosar('1/105/2026'), _dosar('9/105/2026')];
    final r = await service.verificaToate(soap: soap);
    expect(r.single.dosareNoi.single.numar, '9/105/2026');
    expect(r.single.parte.nume, 'Alfa SRL');

    expect(await service.verificaToate(soap: soap), isEmpty);

    // Recitit de pe disc, ca la verificarea din fundal.
    await service.incarca();
    final parte = service.parti.single;
    expect(parte.dosareNoi.single.dosar.numar, '9/105/2026');
    expect(parte.necitite, 1);

    await service.marcheazaCitite(parte.cheie);
    expect(service.totalNecitite, 0);
  });

  test('Aceeași parte la aceeași instanță nu se adaugă de două ori', () async {
    final soap = _SoapFals([]);
    await service.adauga('Alfa SRL', soap: soap);
    await service.adauga('alfa srl', soap: soap);
    await service.adauga('Alfa SRL', institutie: 'TribunalulPRAHOVA', soap: soap);
    expect(service.parti.length, 2);

    await service.sterge(ParteUrmarita.cheiePentru('ALFA SRL', ''));
    expect(service.parti.single.institutie, 'TribunalulPRAHOVA');
  });

  test('Limita portalului e semnalată la adăugare', () async {
    final soap = _SoapFals([_dosar('1/105/2026')], limita: true);
    expect(await service.adauga('Popescu', soap: soap), isTrue);
  });

  test('Fără rețea, verificarea aruncă și nu schimbă nimic', () async {
    final soap = _SoapFals([]);
    await service.adauga('Alfa SRL', soap: soap);
    soap.esueaza = true;
    await expectLater(service.verificaToate(soap: soap), throwsA(isA<SoapException>()));
    expect(service.parti.single.dosareNoi, isEmpty);
  });

  testWidgets('Din rezultate se poate urmări partea căutată', (tester) async {
    final soap = _SoapFals([_dosar('1/105/2026')]);
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(parte: 'Alfa SRL'),
          soap: soap,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Urmărește partea'));
    await tester.pumpAndSettle();
    expect(service.urmareste('Alfa SRL', ''), isTrue);
    expect(find.textContaining('Vei primi o notificare'), findsOneWidget);
    expect(find.byTooltip('Nu mai urmări partea'), findsOneWidget);

    await tester.tap(find.byTooltip('Nu mai urmări partea'));
    await tester.pumpAndSettle();
    expect(service.parti, isEmpty);
  });
}
