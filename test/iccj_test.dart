import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/iccj_service.dart';
import 'package:legal_management_app/services/monitorizare_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/widgets/dosar_iccj.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raspuns = '''
[{"numar":"1234/1/2026","numarVechi":"","data":"2026-03-02T00:00:00",
  "departament":"Secția I civilă","stadiuProcesual":"Recurs","obiect":"pretenții",
  "parti":[{"nume":"ALFA SRL","calitateaProcesualaCurenta":"Recurent"}],
  "sedinte":[{"data":"2026-12-03T00:00:00","ora":"09:00","complet":"C3",
    "solutie":"","detaliiSolutie":"","tipDocument":"","numarDocument":"","dataDocument":null}],
  "caiAtac":[]}]''';

class _IccjFals extends IccjService {
  String json;
  bool esueaza;
  int cereri = 0;
  _IccjFals(this.json, {this.esueaza = false});

  @override
  Future<List<Dosar>> cautaDosar(String numar) async {
    cereri++;
    if (esueaza) throw const IccjException('închis');
    return parseazaDosareIccj(json);
  }
}

class _SoapGol extends SoapService {
  final numere = <String>[];
  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async {
    numere.add(numarDosar);
    return RezultatCautare(const [], false);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
  });

  test('Parserul citește câmpurile din documentația ÎCCJ', () {
    final d = parseazaDosareIccj(_raspuns).single;
    expect(d.numar, '1234/1/2026');
    expect(d.institutie, codIccj);
    expect(d.sectie, 'Secția I civilă');
    expect(d.parti.single.calitate, 'Recurent');
    expect(d.sedinte.single.data, DateTime(2026, 12, 3));
    expect(d.sedinte.single.complet, 'C3');
  });

  test('Parserul acceptă PascalCase și un obiect care conține lista', () {
    final d = parseazaDosareIccj(
      '{"Dosare":[{"Numar":"5/1/2026","Obiect":"x","Sedinte":[{"Data":"2026-12-01","Ora":"10:00"}]}]}',
    ).single;
    expect(d.numar, '5/1/2026');
    expect(d.obiect, 'x');
    expect(d.sedinte.single.ora, '10:00');
  });

  test('Fereastra de noapte e 03:30–06:30', () {
    expect(IccjService.inFereastra(DateTime(2026, 1, 1, 3, 29)), isFalse);
    expect(IccjService.inFereastra(DateTime(2026, 1, 1, 3, 30)), isTrue);
    expect(IccjService.inFereastra(DateTime(2026, 1, 1, 6, 29)), isTrue);
    expect(IccjService.inFereastra(DateTime(2026, 1, 1, 6, 30)), isFalse);
  });

  test('Ziua dosarul e pus în așteptare, noaptea se completează cu o singură veste', () async {
    final iccj = _IccjFals(_raspuns);
    final mesaj = await urmaresteDosarIccj(
      '1234/1/2026',
      iccj: iccj,
      acum: DateTime(2026, 11, 14, 15),
    );
    expect(mesaj, contains('03:30'));
    expect(iccj.cereri, 0);
    expect(esteIccjInAsteptare(BibliotecaService.instance.dosare.single.dosar), isTrue);

    final soap = _SoapGol();
    final monitor = MonitorizareService.instance;
    expect(
      await monitor.verificaToate(soap: soap, iccj: iccj, acum: DateTime(2026, 11, 14, 16)),
      isEmpty,
    );
    expect(iccj.cereri, 0);
    expect(soap.numere, isNot(contains('1234/1/2026')));

    final r = await monitor.verificaToate(soap: soap, iccj: iccj, acum: DateTime(2026, 11, 15, 4));
    expect(r.single.schimbari, ['Datele dosarului au fost aduse de la ÎCCJ (1 termen)']);
    final salvat = BibliotecaService.instance.dosare.single.dosar;
    expect(esteIccjInAsteptare(salvat), isFalse);
    expect(salvat.stadiuProcesual, 'Recurs');
  });

  test('Noaptea dosarul e adus imediat; dacă ÎCCJ nu răspunde, rămâne în așteptare', () async {
    await urmaresteDosarIccj(
      '1234/1/2026',
      iccj: _IccjFals(_raspuns),
      acum: DateTime(2026, 11, 15, 4),
    );
    expect(BibliotecaService.instance.dosare.single.dosar.obiect, 'pretenții');

    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await urmaresteDosarIccj(
      '9/1/2026',
      iccj: _IccjFals(_raspuns, esueaza: true),
      acum: DateTime(2026, 11, 15, 4),
    );
    expect(esteIccjInAsteptare(BibliotecaService.instance.dosare.single.dosar), isTrue);
  });
}
