import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/rezultate_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/cautari_recente_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/utils/sortare_rezultate.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar _d(String numar, DateTime? data, {DateTime? modificat}) => Dosar(
  numar: numar,
  data: data,
  institutie: 'TribunalulPRAHOVA',
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: const [],
  dataModificare: modificat,
);

final _dosare = [
  _d('1/105/2024', DateTime(2024, 5, 1), modificat: DateTime(2026, 1, 1)),
  _d('2/105/2026', DateTime(2026, 2, 1), modificat: DateTime(2026, 3, 1)),
  _d('3/105/2025', DateTime(2025, 7, 1), modificat: DateTime(2026, 11, 10)),
  _d('4/105/2024', null),
];

List<String> _numere(List<Dosar> l) => [for (final d in l) d.numar];

class _SoapFals extends SoapService {
  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async => RezultatCautare(_dosare, false);
}

void main() {
  test('Ordonare după data modificării și după data dosarului', () {
    expect(_numere(ordoneazaRezultate(_dosare, SortareRezultate.portal)), [
      '1/105/2024',
      '2/105/2026',
      '3/105/2025',
      '4/105/2024',
    ]);
    expect(_numere(ordoneazaRezultate(_dosare, SortareRezultate.modificateRecent)), [
      '3/105/2025',
      '2/105/2026',
      '1/105/2024',
      '4/105/2024',
    ]);
    expect(_numere(ordoneazaRezultate(_dosare, SortareRezultate.celeMaiNoi)), [
      '2/105/2026',
      '3/105/2025',
      '1/105/2024',
      '4/105/2024',
    ]);
    expect(_numere(ordoneazaRezultate(_dosare, SortareRezultate.celeMaiVechi)), [
      '1/105/2024',
      '3/105/2025',
      '2/105/2026',
      '4/105/2024',
    ]);
  });

  test('Filtrul pe an', () {
    expect(aniRezultate(_dosare), [2026, 2025, 2024]);
    expect(_numere(ordoneazaRezultate(_dosare, SortareRezultate.portal, an: 2024)), ['1/105/2024']);
  });

  testWidgets('Rezultatele au bară de scroll, ordonare și filtru pe an', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(obiect: 'pretenții'),
          soap: _SoapFals(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);

    await tester.tap(find.text('Ordinea portalului'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data dosarului: cele mai noi').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('2/105/2026')).dy,
      lessThan(tester.getTopLeft(find.text('3/105/2025')).dy),
    );

    await tester.tap(find.text('Toți anii'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    expect(find.text('Anul 2025'), findsOneWidget);
    expect(find.text('Un dosar găsit'), findsOneWidget);
    expect(find.text('2/105/2026'), findsNothing);
  });
}
