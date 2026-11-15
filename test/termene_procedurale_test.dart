import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/screens/calculator_termene_screen.dart';
import 'package:legal_management_app/services/pro_service.dart';
import 'package:legal_management_app/services/termene_procedurale_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Paștele ortodox', () {
    expect(pasteOrtodox(2025), DateTime(2025, 4, 20));
    expect(pasteOrtodox(2026), DateTime(2026, 4, 12));
    expect(pasteOrtodox(2027), DateTime(2027, 5, 2));
  });

  test('Sărbătorile legale, inclusiv cele mobile', () {
    expect(motivZiNelucratoare(DateTime(2026, 4, 10)), 'Vinerea Mare');
    expect(motivZiNelucratoare(DateTime(2026, 4, 13)), 'a doua zi de Paște');
    expect(motivZiNelucratoare(DateTime(2026, 6, 1)), isNotNull);
    expect(motivZiNelucratoare(DateTime(2026, 1, 7)), 'Sfântul Ioan');
    expect(motivZiNelucratoare(DateTime(2026, 11, 14)), 'sâmbătă');
    expect(motivZiNelucratoare(DateTime(2026, 11, 17)), isNull);
  });

  test('Pe zile libere: fără ziua de pornire și fără cea a împlinirii', () {
    // Comunicat joi 1.10.2026, 30 de zile: ziua de după cele 30 e 1.11
    // (duminică), deci ultima zi e luni 2.11.
    final c = calculeazaTermen(DateTime(2026, 10, 1), 30, UnitateTermen.zile);
    expect(c.implinire, DateTime(2026, 11, 1));
    expect(c.ultimaZi, DateTime(2026, 11, 2));
    expect(c.prelungiri.single.$2, 'duminică');

    // Într-o zi obișnuită nu se prelungește nimic.
    final d = calculeazaTermen(DateTime(2026, 11, 2), 10, UnitateTermen.zile);
    expect(d.ultimaZi, DateTime(2026, 11, 13));
    expect(d.prelungiri, isEmpty);
  });

  test('Se prelungește peste weekend și sărbători legate', () {
    // 2.11 + 25 de zile → sâmbătă 28.11; apoi 29.11 duminică, 30.11 Sf. Andrei,
    // 1.12 Ziua Națională: ultima zi e miercuri 2.12.
    final c = calculeazaTermen(DateTime(2026, 11, 2), 25, UnitateTermen.zile);
    expect(c.implinire, DateTime(2026, 11, 28));
    expect(c.ultimaZi, DateTime(2026, 12, 2));
    expect(c.prelungiri, hasLength(4));
  });

  test('Pe luni: ziua corespunzătoare sau ultima zi a lunii', () {
    final c = calculeazaTermen(DateTime(2026, 3, 16), 1, UnitateTermen.luni);
    expect(c.ultimaZi, DateTime(2026, 4, 16));
    // 31.01 + o lună: februarie n-are 31, deci 28.02 (sâmbătă) → luni 2.03.
    final d = calculeazaTermen(DateTime(2026, 1, 31), 1, UnitateTermen.luni);
    expect(d.implinire, DateTime(2026, 2, 28));
    expect(d.ultimaZi, DateTime(2026, 3, 2));
    final e = calculeazaTermen(DateTime(2024, 2, 29), 1, UnitateTermen.ani);
    expect(e.implinire, DateTime(2025, 2, 28));
  });

  test('Termenele salvate se păstrează, cele mai apropiate întâi', () async {
    SharedPreferences.setMockInitialValues({});
    final s = TermeneProceduraleService.instance;
    await s.incarca();
    await s.adauga(
      TermenSalvat(
        id: 'b',
        act: 'Recurs (civil)',
        numarDosar: '',
        start: DateTime(2026, 11, 1),
        ultimaZi: DateTime(2026, 12, 2),
      ),
    );
    await s.adauga(
      TermenSalvat(
        id: 'a',
        act: 'Apel (civil)',
        numarDosar: '1/105/2026',
        start: DateTime(2026, 11, 1),
        ultimaZi: DateTime(2026, 11, 18),
      ),
    );
    await s.incarca();
    expect(s.termene.map((t) => t.id), ['a', 'b']);
    expect(s.apropiate(DateTime(2026, 11, 14)).map((t) => t.id), ['a']);
    await s.sterge('a');
    expect(s.termene.map((t) => t.id), ['b']);
  });

  testWidgets('Calculatorul arată ultima zi și explicația', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ProService.instance.incarca();
    await tester.pumpWidget(
      MaterialApp(theme: construiesteTema(), home: const CalculatorTermeneScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('art. 468'), findsOneWidget);
    expect(find.text('Ultima zi'), findsNothing);

    await tester.tap(find.text('Alege data'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '10/01/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Ultima zi'), findsOneWidget);
    expect(find.text('luni, 02.11.2026'), findsOneWidget);
    expect(find.textContaining('nu e zi lucrătoare (duminică)'), findsOneWidget);
  });
}
