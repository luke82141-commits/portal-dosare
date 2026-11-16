import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/trimitere.dart';

void main() {
  testeCodulCivil();
  test('nrArticol scoate punctul miilor', () {
    expect(nrArticol('2.500'), '2500');
    expect(nrArticol('1.000^1'), '1000^1');
    expect(nrArticol('5 ^ 1'), '5^1');
    expect(nrArticol('229'), '229');
  });

  test('articolele cu punct („Art. 2.500”) se găsesc după număr', () {
    final b = structureazaAct(
      'Art. 2.499. - Dispoziții finale\n(1) Text unu.\n'
      'Art. 2.500. - Intrarea în vigoare\nPrezentul cod intră în vigoare la data prevăzută în legea de punere în aplicare.\n'
      'Articolul 2.501\nAlt text.',
    );
    final arts = b.where((x) => x.tip == TipBloc.articol).toList();
    expect(arts.map((x) => x.articol).toList(), ['2499', '2500', '2501']);
    expect(arts[1].titlu, 'Intrarea în vigoare');
    for (final cautat in ['2500', '2.500', 'art. 2500', 'Art. 2.500']) {
      expect(indiceArticol(b, cautat), b.indexOf(arts[1]), reason: cautat);
    }
  });

  test('trimiteri la articole cu punct', () {
    expect(
      trimitereDin('art. 2.500 alin. (1) din Codul civil')?.eticheta,
      'Art. 2500 alin. (1)',
    );
  });
}

void testeCodulCivil() {
  String fx(String n) => utf8.decode(
    gzip.decode(
      File('test/fixtures/legislatie/cod_civil/$n.gz').readAsBytesSync(),
    ),
  );

  test(
    'Codul civil (forma la zi): denumirea în capul articolului, art. 2.500',
    () {
      final f = formaDinHtml(fx('cod_109884.html'))!;
      final b = f.blocuri;
      final i229 = indiceArticol(b, '229')!;
      expect(b[i229].titlu, 'Dovada denumirii și sediului');
      expect(b[i229 + 1].eticheta, '(1)');
      final i2500 = indiceArticol(b, '2500')!;
      expect(b[i2500].titlu, 'Obiectul prescripției extinctive');
      expect(b[i2500].eticheta, 'Art. 2.500');
      expect(
        b.where((x) => x.tip == TipBloc.articol).length,
        greaterThan(2600),
      );
    },
  );

  test('Codul civil (textul din căutare): art. 229 și art. 2.500', () {
    final acte = parseazaRaspunsCautare(fx('soap_cod.xml'));
    final b = structureazaAct(acte.single.text);
    final i229 = indiceArticol(b, '229')!;
    expect(b[i229].titlu, 'Dovada denumirii şi sediului');
    final i2500 = indiceArticol(b, '2.500')!;
    expect(b[i2500].titlu, 'Obiectul prescripţiei extinctive');
  });
}
