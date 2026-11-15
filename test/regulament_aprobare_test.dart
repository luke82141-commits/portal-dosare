import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';

String fixture(String nume) => utf8.decode(
  gzip.decode(
    File('test/fixtures/legislatie/regulament/$nume.gz').readAsBytesSync(),
  ),
);

void main() {
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
