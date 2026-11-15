import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/culori_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/widgets/dosar_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar _d(String numar, List<DateTime> zile) => Dosar(
      numar: numar,
      data: DateTime(2026, 1, 1),
      institutie: 'TribunalulBUCURESTI',
      obiect: 'x',
      stadiuProcesual: 'Fond',
      sectie: '',
      categorie: '',
      parti: const [],
      sedinte: [
        for (final z in zile) Sedinta(complet: 'C1', data: z, ora: '09:00', solutie: '', solutieSumar: ''),
      ],
    );

void main() {
  final zi = DateTime(2026, 11, 13);

  test('dosarele din aceeași zi primesc culori diferite', () {
    final dosare = [for (var i = 0; i < 10; i++) _d('$i/3/2026', [zi])];
    final c = culoriAutomate(dosare);
    expect(c.values.toSet().length, 10);
  });

  test('culoarea aleasă se păstrează, iar cele automate o ocolesc', () {
    final a = _d('1/3/2026', [zi]), b = _d('2/3/2026', [zi]);
    final auto = culoriAutomate([a, b]);
    final c = culoriAutomate([a, b], alese: {b.cheie: auto[a.cheie]!});
    expect(c[b.cheie], auto[a.cheie]);
    expect(c[a.cheie], isNot(c[b.cheie]));
  });

  test('un dosar nou nu schimbă culorile celor existente', () {
    final a = _d('1/3/2026', [zi]), b = _d('2/3/2026', [zi]);
    final inainte = culoriAutomate([a, b]);
    final dupa = culoriAutomate([a, b, _d('3/3/2026', [zi])]);
    expect(dupa[a.cheie], inainte[a.cheie]);
    expect(dupa[b.cheie], inainte[b.cheie]);
  });

  testWidgets('din card se alege culoarea și se poate reveni la automat', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final d = _d('5/3/2026', [zi]);
    await tester.runAsync(() async {
      await BibliotecaService.instance.incarca();
      await CuloriDosareService.instance.incarca();
      await BibliotecaService.instance.adauga(d);
    });
    final salvat = BibliotecaService.instance.dosare.single;
    await tester.pumpWidget(MaterialApp(
      theme: construiesteTema(),
      home: Scaffold(body: DosarCardWidget(dosar: d, salvat: salvat)),
    ));
    await tester.tap(find.byTooltip('Schimbă culoarea'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mov'));
    await tester.pumpAndSettle();
    expect(CuloriDosareService.instance.aleasa(d.cheie), const Color(0xFF8E24AA));
    expect(CuloriDosareService.instance.culoare(d), const Color(0xFF8E24AA));

    await tester.tap(find.byTooltip('Schimbă culoarea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revino la culoarea automată'));
    await tester.pumpAndSettle();
    expect(CuloriDosareService.instance.aleasa(d.cheie), isNull);
  });
}
