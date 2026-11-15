import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/dosare_selectie_screen.dart';
import 'package:legal_management_app/screens/monitorizate_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar _d(String numar, {DateTime? termen, String ora = '09:00'}) => Dosar(
  numar: numar,
  data: DateTime(2026, 1, 1),
  institutie: 'TribunalulPRAHOVA',
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: [
    if (termen != null)
      Sedinta(complet: 'C1', data: termen, ora: ora, solutie: '', solutieSumar: ''),
  ],
);

DosarSalvat _s(Dosar d, {List<DateTime> modificari = const []}) => DosarSalvat(
  dosar: d,
  adaugatLa: DateTime(2026, 1, 1),
  modificari: [for (final m in modificari) Modificare(detectataLa: m, text: 'x')],
  necitite: modificari.length,
);

void main() {
  final acum = DateTime(2026, 11, 14, 15);

  test('Termenele din 7 zile, în ordinea zilei și orei', () {
    final l = dosareCuTermenInSaptamana([
      _s(_d('1/1/2026', termen: DateTime(2026, 11, 20))),
      _s(_d('2/1/2026', termen: DateTime(2026, 11, 16), ora: '11:00')),
      _s(_d('3/1/2026', termen: DateTime(2026, 11, 16), ora: '08:30')),
      _s(_d('4/1/2026', termen: DateTime(2026, 11, 21))),
      _s(_d('5/1/2026')),
    ], acum: acum);
    expect([for (final s in l) s.dosar.numar], ['3/1/2026', '2/1/2026', '1/1/2026']);
  });

  test('Actualizările noi, cea mai recentă întâi', () {
    final l = dosareCuActualizari([
      _s(_d('1/1/2026'), modificari: [DateTime(2026, 11, 10)]),
      _s(_d('2/1/2026')),
      _s(_d('3/1/2026'), modificari: [DateTime(2026, 11, 1), DateTime(2026, 11, 14)]),
    ]);
    expect([for (final s in l) s.dosar.numar], ['3/1/2026', '1/1/2026']);
  });

  testWidgets('Căsuța „actualizări noi” deschide dosarele cu actualizări', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final b = BibliotecaService.instance;
    await b.incarca();
    await b.adauga(_d('7/1/2026'));
    await b.adauga(_d('8/1/2026'));
    await b.aplicaActualizari(
      [_d('8/1/2026', termen: DateTime(2027, 1, 5))],
      numereVerificate: {'8/1/2026'},
    );

    await tester.pumpWidget(
      MaterialApp(theme: construiesteTema(), home: const MonitorizateScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('actualizar'));
    await tester.pumpAndSettle();
    expect(find.text('Actualizări noi'), findsOneWidget);
    expect(find.text('8/1/2026'), findsOneWidget);
    expect(find.text('7/1/2026'), findsNothing);
  });
}
