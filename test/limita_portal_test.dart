import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/services/monitorizare_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gol =
    '<?xml version="1.0" encoding="utf-8"?>'
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>'
    '<CautareDosareResponse xmlns="portalquery.just.ro"><CautareDosareResult/>'
    '</CautareDosareResponse></soap:Body></soap:Envelope>';

void main() {
  setUp(() {
    SoapService.reseteazaLimita();
    SoapService.pauzaIntreCereri = const Duration(milliseconds: 50);
  });

  test('La 429 portalul e lăsat în pace până expiră pauza cerută', () async {
    var cereri = 0;
    final client = MockClient((_) async {
      cereri++;
      return http.Response('', 429, headers: {'retry-after': '120'});
    });
    final soap = SoapService(client: client);
    await expectLater(
      soap.cautaDosare(numarDosar: '1/105/2026'),
      throwsA(isA<PortalOcupatException>()),
    );
    // A doua cerere nu mai pleacă deloc.
    await expectLater(
      soap.cautaDosare(numarDosar: '2/105/2026'),
      throwsA(isA<PortalOcupatException>()),
    );
    expect(cereri, 1);
  });

  test('Cererile pleacă una câte una, cu pauză între ele', () async {
    final momente = <DateTime>[];
    final client = MockClient((_) async {
      momente.add(DateTime.now());
      return http.Response(_gol, 200);
    });
    final soap = SoapService(client: client);
    await Future.wait([
      for (var i = 1; i <= 3; i++) soap.cautaDosare(numarDosar: '$i/105/2026'),
    ]);
    expect(momente, hasLength(3));
    for (var i = 1; i < momente.length; i++) {
      expect(
        momente[i].difference(momente[i - 1]).inMilliseconds,
        greaterThanOrEqualTo(45),
      );
    }
  });

  test(
    'La deschiderea aplicației verificăm cel mult o dată la 15 minute',
    () async {
      SharedPreferences.setMockInitialValues({
        'ultima_verificare_completa': DateTime(
          2026,
          11,
          14,
          15,
        ).toIso8601String(),
      });
      final m = MonitorizareService.instance;
      expect(
        await m.eTimpulPentruVerificare(acum: DateTime(2026, 11, 14, 15, 10)),
        isFalse,
      );
      expect(
        await m.eTimpulPentruVerificare(acum: DateTime(2026, 11, 14, 15, 16)),
        isTrue,
      );
      SharedPreferences.setMockInitialValues({});
      expect(await m.eTimpulPentruVerificare(), isTrue);
    },
  );
}
