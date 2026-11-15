import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';

String fixture(String nume) => utf8.decode(
  gzip.decode(
    File('test/fixtures/legislatie/regulament/$nume.gz').readAsBytesSync(),
  ),
);

void main() {
  testeVechi();
  test('regulamentele din căutare spun prin ce act au fost aprobate', () {
    final acte = [
      ...parseazaRaspunsCautare(fixture('cautare_atestare.xml')),
      ...parseazaRaspunsCautare(fixture('cautare_receptie.xml')),
    ];
    final reg = acte.where((a) => a.tipAct == 'REGULAMENT').toList();
    expect(reg, hasLength(3));
    expect(reg.map((a) => a.aprobatPrin?.denumire).toList(), [
      'Hotărârea nr. 430 din 25 iulie 2023',
      'Ordinul nr. 133 din 15 decembrie 2021',
      'Ordinul nr. 600 din 8 februarie 2023',
    ]);
    expect(reg.last.aprobatPrin!.scurta, 'Ordinul nr. 600/2023');
  });

  test(
    'ordinele care modifică un regulament „aprobat prin” nu primesc notă',
    () {
      final acte = parseazaRaspunsCautare(fixture('cautare_receptie.xml'));
      for (final a in acte.where((a) => a.tipAct != 'REGULAMENT')) {
        expect(a.aprobatPrin, isNull, reason: a.titlu);
      }
    },
  );

  test('note în alte forme', () {
    expect(
      aprobareDinText(
        'NORMĂ din 1994 Notă: Aprobată prin Hotărârea Guvernului nr. 273/1994. Art. 1',
      )?.denumire,
      'Hotărârea Guvernului nr. 273/1994',
    );
    expect(aprobareDinText('Art. 1 Textul legii, fără notă.'), isNull);
  });

  test('forma consolidată păstrează legătura către actul de aprobare', () {
    final f = formaDinHtml(fixture('consolidat_273790.html'))!;
    final nota = f.blocuri.firstWhere((b) => b.tip == TipBloc.nota);
    expect(nota.text, contains('Aprobat prin'));
    expect(nota.legaturi.first.idAct, '273789');
    expect(
      aprobareDinText(f.textSimplu)?.denumire,
      'Hotărârea nr. 430 din 25 iulie 2023',
    );
  });
}

String fixture2(String nume) => utf8.decode(
  gzip.decode(
    File('test/fixtures/legislatie/regulament_vechi/$nume.gz')
        .readAsBytesSync(),
  ),
);

void testeVechi() {
  test('regulament vechi fără notă: ordinul din aceeași zi', () {
    final acte = parseazaRaspunsCautare(fixture2('cautare_avizare.xml'));
    final reg = acte.firstWhere((a) => a.tipAct == 'REGULAMENT');
    expect(reg.aprobatPrin, isNull);
    expect(seAproba(reg), isTrue);
    expect(
      cerereAprobare(reg)!.titlu,
      'aprob* regulament* avizar* verificar* recepti* lucrar*',
    );
    final a = aprobareDinRezultate(reg, acte)!;
    expect(a.denumire, 'Ordinul nr. 108 din 29 martie 2010');
    expect(a.idAct, '117795');
  });

  test('aprobarea se caută o singură dată, în fundal', () async {
    var cereri = 0;
    final svc = LegislatieService.cuClient(
      MockClient((r) async {
        if ((r.headers['SOAPAction'] ?? '').contains('GetToken')) {
          return http.Response(
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><GetTokenResponse xmlns="http://tempuri.org/"><GetTokenResult>abc</GetTokenResult></GetTokenResponse></s:Body></s:Envelope>',
            200,
          );
        }
        cereri++;
        return http.Response.bytes(
          gzip.decode(
            File(
              'test/fixtures/legislatie/regulament_vechi/cautare_avizare.xml.gz',
            ).readAsBytesSync(),
          ),
          200,
        );
      }),
    );
    final reg = parseazaRaspunsCautare(fixture2('cautare_avizare.xml'))
        .firstWhere((a) => a.tipAct == 'REGULAMENT');
    final a = await svc.aprobareAct(reg);
    await svc.aprobareAct(reg);
    expect(a?.scurta, 'Ordinul nr. 108/2010');
    expect(cereri, 1);
  });

  test('nota veche „*) Aprobat prin LEGEA …” din forma la zi', () {
    final f = formaDinHtml(fixture2('consolidat_99351.html'))!;
    expect(
      aprobareDinText(f.textSimplu)?.denumire,
      'Legea nr. 267 din 7 noiembrie 2008',
    );
  });
}
