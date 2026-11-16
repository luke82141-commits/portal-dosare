import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/screens/act_normativ_screen.dart';
import 'package:legal_management_app/services/forma_consolidata.dart';
import 'package:legal_management_app/services/legislatie_service.dart';

/// 196565 e o formă mai veche a Legii 307; o servim cu forma la zi.
MockClient _client() => MockClient((r) async {
  if (r.url.path.endsWith('actiuniSuferite')) {
    return http.Response('{"acte":""}', 200);
  }
  final id = RegExp(r'(\d+)$').firstMatch(r.url.path)?.group(1);
  if (id == '73657' || id == '196565') {
    return http.Response.bytes(
      gzip.decode(
        File('test/fixtures/legislatie/307_consolidat.html.gz')
            .readAsBytesSync(),
      ),
      200,
    );
  }
  return http.Response('nu', 404);
});

void main() {
  testWidgets('trimiterea deschide o fereastră cu alineatul citat', (
    tester,
  ) async {
    final fs = FormaConsolidataService.cuClient(_client());
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: ActNormativScreen(
          act: const ActNormativ(
            tipAct: 'LEGE',
            numar: '307',
            titlu: 'LEGE nr. 307 din 12 iulie 2006 privind apărarea împotriva incendiilor',
            emitent: 'PARLAMENTUL',
            publicatie: 'MONITORUL OFICIAL nr. 297 din 17 aprilie 2019',
            linkHtml: 'https://legislatie.just.ro/Public/DetaliiDocument/73657',
            text: 'Articolul 1\nText.',
          ),
          formaService: fs,
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.textContaining('ultima modificare').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    final tinta = find.textContaining('art. 30 alin.', findRichText: true);
    for (var i = 0; i < 40 && tinta.evaluate().isEmpty; i++) {
      await tester.drag(
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
        const Offset(0, -150),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    final link = find.textRange.ofSubstring('art. 30 alin.');
    expect(link, findsWidgets);
    await tester.tapOnText(link.first);
    await tester.pump(const Duration(milliseconds: 300));
    for (
      var i = 0;
      i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('Art. 30 alin. (4^1)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Deschide actul')),
      findsOneWidget,
    );
    // Alineatul (4^1) nu mai există în forma republicată: spunem asta și
    // arătăm tot articolul.
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('nu mai există în forma la zi'),
      ),
      findsOneWidget,
    );
  });
}
