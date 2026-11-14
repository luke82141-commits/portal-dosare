import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/services/cautari_recente_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() {
  group('cererea SOAP', () {
    String camp(XmlDocument d, String nume) {
      final e = d.findAllElements(nume).single;
      return e.getAttribute('nil', namespace: 'http://www.w3.org/2001/XMLSchema-instance') == 'true'
          ? '<nil>'
          : e.innerText;
    }

    test('trimite numele părții, instanța și intervalul', () {
      final d = XmlDocument.parse(construiesteCerereCautare(
        parte: 'SC Exemplu & Fiii SRL',
        institutie: 'TribunalulPRAHOVA',
        dataStart: DateTime(2026, 1, 5),
        dataStop: DateTime(2026, 11, 14),
      ));
      expect(camp(d, 'numarDosar'), '<nil>');
      expect(camp(d, 'obiectDosar'), '<nil>');
      expect(camp(d, 'numeParte'), 'SC Exemplu & Fiii SRL');
      expect(camp(d, 'institutie'), 'TribunalulPRAHOVA');
      expect(camp(d, 'dataStart'), '2026-01-05T00:00:00');
      expect(camp(d, 'dataStop'), '2026-11-14T00:00:00');
    });

    test('fără filtre suplimentare, câmpurile rămân nil', () {
      final d = XmlDocument.parse(construiesteCerereCautare(numar: '14993/299/2026'));
      expect(camp(d, 'numarDosar'), '14993/299/2026');
      for (final c in ['obiectDosar', 'numeParte', 'institutie', 'dataStart', 'dataStop']) {
        expect(camp(d, c), '<nil>', reason: c);
      }
    });

    test('doar instanța nu e un criteriu suficient', () async {
      final r = await SoapService().cautaDosare(institutie: 'TribunalulPRAHOVA');
      expect(r.dosare, isEmpty);
    });
  });

  group('căutări recente', () {
    test('păstrează toate criteriile după repornire', () async {
      SharedPreferences.setMockInitialValues({});
      final s = CautariRecenteService.instance;
      final c = CautareRecenta(
        parte: 'Popescu Ion',
        institutie: 'TribunalulPRAHOVA',
        dataStart: DateTime(2026, 1, 1),
        dataStop: DateTime(2026, 6, 30),
      );
      await s.adauga(c);
      await s.incarca();
      expect(s.lista.single, c);
      expect(s.lista.single.eticheta, 'Popescu Ion · Tribunalul Prahova · 01.01.2026–30.06.2026');
    });

    test('citește și căutările salvate de versiunea veche', () async {
      SharedPreferences.setMockInitialValues({
        'cautari_recente_v1': ['14993/299/2026\u0001uzucapiune'],
      });
      final s = CautariRecenteService.instance;
      await s.incarca();
      expect(s.lista.single, const CautareRecenta(numar: '14993/299/2026', obiect: 'uzucapiune'));
    });
  });
}
