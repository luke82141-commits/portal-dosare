import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/utils/instante.dart';

void main() {
  test('desparte și corectează numele instanțelor', () {
    expect(numeInstanta('JudecatoriaSECTORUL1BUCURESTI'), 'Judecătoria Sectorul 1 București');
    expect(numeInstanta('CurteadeApelTARGUMURES'), 'Curtea de Apel Târgu Mureș');
    expect(numeInstanta('TribunalulBISTRITANASAUD'), 'Tribunalul Bistrița-Năsăud');
    expect(numeInstanta('TribunalulMilitarTeritorialBUCURESTI'),
        'Tribunalul Militar Teritorial București');
    expect(numeInstanta('TribunalulpentruminoriSifamilieBRASOV'),
        'Tribunalul pentru Minori și Familie Brașov');
    expect(numeInstanta('JudecatoriaDarabani'), 'Judecătoria Darabani');
    expect(numeInstanta('CurteaMilitaradeApelBUCURESTI'), 'Curtea Militară de Apel București');
  });

  test('un cod necunoscut rămâne măcar despărțit', () {
    expect(numeInstanta('JudecatoriaORASNOU'), 'Judecătoria Orasnou');
    expect(numeInstanta(''), '');
  });

  // Lista completă a instanțelor din WSDL-ul portalului (query.asmx?WSDL).
  test('toate instanțele din portal au nume despărțit', () {
    final coduri = File('test/fixtures/instante_portal.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(coduri.length, 246);
    for (final cod in coduri) {
      final nume = numeInstanta(cod);
      expect(nume, contains(' '), reason: cod);
      expect(RegExp(r'[A-ZĂÂÎȘȚ]{2}').hasMatch(nume), isFalse, reason: '$cod -> $nume');
    }
  });

  test('tipul documentului de ședință', () {
    expect(numeDocument('incheieredesedinta'), 'Încheiere de ședință');
    expect(numeDocument('_IncheiereFinalaDezinvestire'), 'Încheiere finală (dezînvestire)');
    expect(numeDocument('Altceva'), 'Altceva');
  });
}
