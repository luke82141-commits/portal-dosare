import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/services/act_structura.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/trimitere.dart';

void main() {
  group('trimitereDin', () {
    String? t(String link, [String inainte = '']) =>
        trimitereDin(link, inainte)?.eticheta;

    test('articolul e în textul linkului', () {
      expect(t('art. 326 din Codul penal'), 'Art. 326');
      expect(t('art. 2 pct. 39 din Legea nr. 273/2006'), 'Art. 2 pct. 39');
      expect(
        t('art. 30 alin. (4^1) din Legea nr. 307/2006'),
        'Art. 30 alin. (4^1)',
      );
      expect(t('art. II din Legea nr. 28/2018'), 'Art. II');
      expect(
        t('articolului XIII din ORDONANȚA DE URGENȚĂ nr. 17'),
        'Art. XIII',
      );
      expect(t('art. VI pct. 3'), 'Art. VI pct. 3');
      expect(
        t('Punctul 3, Articolul III din ORDONANȚA DE URGENȚĂ nr. 80'),
        'Art. III pct. 3',
      );
      expect(t('art. 9 lit. i) din Legea nr. 10/1995'), 'Art. 9 lit. i)');
    });

    test('articolul e chiar înaintea linkului', () {
      expect(t('Legea nr. 10/1995', 'potrivit art. 17 din '), 'Art. 17');
      expect(
        t('Legea nr. 10/1995', 'prevăzute la art. 41 alin. (1^1) din '),
        'Art. 41 alin. (1^1)',
      );
      expect(t('3 din Hotărârea Guvernului nr. 1.025/2003', 'art. '), 'Art. 3');
    });

    test('trimiterile la tot actul nu au articol', () {
      expect(t('Legea nr. 50/1991', 'au înțelesul prevăzut în '), isNull);
      expect(t('Legea nr. 8/2010', 'art. 5 a fost aprobată prin '), isNull);
      expect(t('alin. (1)', 'metodologiei prevăzute la '), isNull);
    });
  });

  group('blocuriTrimitere', () {
    late List<BlocAct> blocuri;
    setUpAll(() {
      final html = utf8.decode(
        gzip.decode(
          File('test/fixtures/legislatie/307_consolidat.html.gz')
              .readAsBytesSync(),
        ),
      );
      blocuri = formaDinHtml(html)!.blocuri;
    });

    test('articolul întreg', () {
      final b = blocuriTrimitere(blocuri, const Trimitere('1'));
      expect(b.first.eticheta, 'Art. 1');
      expect(b.where((x) => x.tip == TipBloc.alineat), hasLength(2));
      expect(caleArticol(blocuri, b.first), 'Capitolul I');
    });

    test('doar alineatul sau litera', () {
      final a = blocuriTrimitere(blocuri, const Trimitere('1', alineat: '1'));
      expect(a.map((x) => x.eticheta).toList(), ['Art. 1', '(1)']);
      final l = blocuriTrimitere(
        blocuri,
        const Trimitere('1', alineat: '2', litera: 'b'),
      );
      expect(l.map((x) => x.eticheta).toList(), ['Art. 1', 'b)']);
    });

    test('subdiviziune care nu mai există: tot articolul, marcat', () {
      const t = Trimitere('30', alineat: '4^1');
      final b = blocuriTrimitere(blocuri, t);
      expect(b.first.eticheta, 'Art. 30');
      expect(trimitereExacta(b, t), isFalse);
      expect(caleArticol(blocuri, b.first), isNot(contains('Secțiunea a 8-a')));
      const e = Trimitere('1', alineat: '2', litera: 'b');
      expect(trimitereExacta(blocuriTrimitere(blocuri, e), e), isTrue);
    });

    test('articol inexistent', () {
      expect(blocuriTrimitere(blocuri, const Trimitere('999')), isEmpty);
    });
  });
}
