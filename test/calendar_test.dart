import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/calendar_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/utils/calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sedinta _s(DateTime d, String ora) =>
    Sedinta(complet: 'C3', data: d, ora: ora, solutie: '', solutieSumar: '');

Dosar _d(String numar, List<Sedinta> sedinte) => Dosar(
      numar: numar,
      data: DateTime(2026, 3, 3),
      institutie: 'JudecatoriaSECTORUL1BUCURESTI',
      obiect: 'pretenții',
      stadiuProcesual: 'Fond',
      sectie: '',
      categorie: 'Civil',
      parti: const [],
      sedinte: sedinte,
    );

void main() {
  test('ora portalului devine minutul din zi', () {
    expect(minutDinOra('09:30'), 570);
    expect(minutDinOra('9.05'), 545);
    expect(minutDinOra(''), isNull);
    expect(minutDinOra('25:00'), isNull);
  });

  test('termenele se grupează pe zile, ordonate după oră', () {
    final zi = DateTime(2026, 11, 12);
    final t = termenePeZile([
      _d('1/2/2026', [_s(zi, '11:00')]),
      _d('3/4/2026', [_s(zi, '09:00'), _s(DateTime(2026, 11, 20), '')]),
    ]);
    expect(t[zi]!.map((e) => e.dosar.numar), ['3/4/2026', '1/2/2026']);
    expect(t[DateTime(2026, 11, 20)]!.single.minut, isNull);
  });

  test('termenele suprapuse se împart pe coloane', () {
    final zi = DateTime(2026, 11, 12);
    final l = termenePeZile([
      _d('1/1/2026', [_s(zi, '09:00')]),
      _d('2/2/2026', [_s(zi, '09:30')]),
      _d('3/3/2026', [_s(zi, '12:00')]),
    ])[zi]!;
    expect(coloaneSuprapuse(l), [(0, 2), (1, 2), (0, 1)]);
  });

  test('grila lunii începe lunea', () {
    final z = zileGrilaLuna(DateTime(2026, 11));
    expect(z.first, DateTime(2026, 10, 26));
    expect(z.first.weekday, DateTime.monday);
    expect(z.length, 42);
  });

  group('ecranul', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await BibliotecaService.instance.incarca();
    });

    testWidgets('trece prin vederile lună, zi, săptămână și an', (tester) async {
      await tester.runAsync(() => BibliotecaService.instance.adauga(
            _d('468/310/2026', [_s(DateTime(2026, 11, 13), '09:00')]),
          ));
      await tester.pumpWidget(MaterialApp(
        theme: construiesteTema(),
        home: CalendarScreen(azi: DateTime(2026, 11, 11)),
      ));
      expect(find.text('Noiembrie 2026'), findsOneWidget);
      expect(find.text('468/310'), findsOneWidget);

      // Tap pe zi deschide vederea zilei.
      await tester.tap(find.text('468/310'));
      await tester.pumpAndSettle();
      expect(find.text('Vineri, 13 noiembrie'), findsOneWidget);
      expect(find.text('468/310/2026'), findsOneWidget);

      await tester.tap(find.text('Săpt.'));
      await tester.pumpAndSettle();
      expect(find.text('9 – 15 noi. 2026'), findsOneWidget);

      await tester.tap(find.text('An'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Înainte'));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);
      await tester.tap(find.text('Azi'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
    });
  });
}
