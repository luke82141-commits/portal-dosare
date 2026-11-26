import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';

void main() {
  test('Legea 53/2003: pagina e doar trimiterea către Codul muncii', () {
    final html = utf8.decode(
      gzip.decode(File('test/fixtures/legislatie/lege53_ciot.html.gz').readAsBytesSync()),
    );
    final f = formaDinHtml(html)!;
    expect(idActDinCiot(f.blocuri, idPropriu: '128646'), '309240');
  });

  test('titluCurat scoate trimiterile la note („*)”) fără paranteză în plus', () {
    expect(
      titluCurat('LEGE nr. 287 din 17 iulie 2009*) (*republicată*) privind Codul civil'),
      'LEGE nr. 287 din 17 iulie 2009 (republicată) privind Codul civil',
    );
    expect(
      titluCurat('LEGE nr. 53 din 24 ianuarie 2003 (*republicată*) Codul muncii*)'),
      'LEGE nr. 53 din 24 ianuarie 2003 (republicată) Codul muncii',
    );
    expect(titluCurat('CODUL CIVIL din 17 iulie 2009 (**republicat**)'),
        'CODUL CIVIL din 17 iulie 2009 (republicat)');
    expect(titluCurat('CODUL CIVIL din 17 iulie 2009 (**republicat**) (Legea nr. 287/2009*)'),
        'CODUL CIVIL din 17 iulie 2009 (republicat) (Legea nr. 287/2009)');
  });

  test('codul deschis după id se numește „Codul civil”, nu „Cod”', () {
    const a = ActNormativ(
      tipAct: 'COD',
      numar: '',
      titlu: 'CODUL CIVIL din 17 iulie 2009 (republicat) (Legea nr. 287/2009)',
      emitent: '',
      publicatie: '',
      linkHtml: '',
      text: '',
    );
    expect(a.denumireScurta, 'Codul civil');
  });

  test('un act cu articole nu e ciot', () {
    const blocuri = [
      BlocAct(TipBloc.articol, eticheta: 'Art. 1', articol: '1'),
      BlocAct(TipBloc.text, text: 'vezi Legea 1', legaturi: [Legatura(5, 12, '99')]),
    ];
    expect(idActDinCiot(blocuri), isNull);
  });
}
