import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/services/cautari_recente_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _raspuns(List<(String, String)> dosare) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>'
    '<CautareDosareResponse xmlns="portalquery.just.ro"><CautareDosareResult>'
    '${[for (final (n, i) in dosare) '<Dosar><numar>$n</numar><institutie>$i</institutie></Dosar>'].join()}'
    '</CautareDosareResult></CautareDosareResponse></soap:Body></soap:Envelope>';

void main() {
  setUp(() {
    SoapService.reseteazaLimita();
    SoapService.pauzaIntreCereri = Duration.zero;
  });

  test('Mai multe instanțe: câte o cerere pe instanță, rezultate unite fără dubluri', () async {
    final cerute = <String>[];
    final client = MockClient((r) async {
      final inst = RegExp(r'<institutie>(\w+)</institutie>').firstMatch(r.body)?.group(1) ?? '';
      cerute.add(inst);
      return http.Response(
        _raspuns([
          ('1/$inst/2026', inst),
          if (inst == 'TribunalulPRAHOVA') ('2/2026', 'TribunalulPRAHOVA'),
          if (inst == 'JudecatoriaSINAIA') ('2/2026', 'TribunalulPRAHOVA'),
        ]),
        200,
      );
    });
    final r = await SoapService(client: client).cautaDosareLaInstante(
      numeParte: 'Popescu',
      institutii: ['TribunalulPRAHOVA', 'JudecatoriaSINAIA'],
    );
    expect(cerute, ['TribunalulPRAHOVA', 'JudecatoriaSINAIA']);
    expect(
      [for (final d in r.dosare) d.numar],
      ['1/TribunalulPRAHOVA/2026', '2/2026', '1/JudecatoriaSINAIA/2026'],
    );
  });

  test('Căutarea recentă ține minte toate instanțele', () {
    const c = CautareRecenta(parte: 'Popescu', institutie: 'TribunalulPRAHOVA,JudecatoriaSINAIA');
    expect(c.institutii, ['TribunalulPRAHOVA', 'JudecatoriaSINAIA']);
    expect(c.numeInstante, 'Tribunalul Prahova și Judecătoria Sinaia');
    expect(
      descrieInstante(['TribunalulPRAHOVA', 'JudecatoriaSINAIA', 'JudecatoriaMIZIL']),
      'Tribunalul Prahova și încă 2 instanțe',
    );
    expect(const CautareRecenta(parte: 'x').institutii, isEmpty);
  });

  testWidgets('Tot județul se bifează deodată', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mai multe criterii'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toate instanțele'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Caută instanța sau județul'), 'prahova');
    await tester.pumpAndSettle();
    final bifeaza = find.textContaining('Bifează toate cele');
    expect(bifeaza, findsOneWidget);
    await tester.tap(bifeaza);
    await tester.pumpAndSettle();
    final gata = find.textContaining('Gata (');
    final n = int.parse(RegExp(r'\d+').firstMatch(tester.widget<Text>(gata).data!)!.group(0)!);
    expect(n, greaterThanOrEqualTo(7));
    await tester.tap(gata);
    await tester.pumpAndSettle();

    expect(find.text('Instanțele'), findsOneWidget);
    expect(find.textContaining('și încă ${n - 1} instanțe'), findsOneWidget);
  });
}
