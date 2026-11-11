import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/widgets/dosar_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dosar = Dosar(
  numar: '468/310/2026',
  data: DateTime(2026, 3, 3),
  institutie: 'JudecatoriaSECTORUL1BUCURESTI',
  obiect: 'uzucapiune',
  stadiuProcesual: 'Fond',
  sectie: 'Secția Civilă',
  categorie: 'Civil',
  parti: const [Parte(nume: 'POPESCU ION', calitate: 'Reclamant')],
  sedinte: [
    Sedinta(
      complet: 'C3',
      data: DateTime(2026, 9, 15),
      ora: '09:00',
      solutie: 'Amână cauza',
      solutieSumar: 'pentru administrarea probelor',
    ),
    Sedinta(
      complet: 'C3',
      data: DateTime(2026, 5, 12),
      ora: '09:00',
      solutie: 'Încheiere',
      solutieSumar: 'Admite cererea de probe.',
    ),
  ],
);

Future<void> _pompeazaCard(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DosarCardWidget(dosar: _dosar)),
        ),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
  });

  testWidgets('Ecranul de căutare are câmpurile pentru număr și obiect', (tester) async {
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    expect(find.text('Număr dosar'), findsOneWidget);
    expect(find.text('Obiectul dosarului'), findsOneWidget);
    expect(find.text('Caută'), findsOneWidget);

    await tester.tap(find.text('Bibliotecă'));
    await tester.pumpAndSettle();
    expect(find.text('Niciun dosar salvat'), findsOneWidget);
  });

  testWidgets('Cardul arată instanța despărțită și ultima pronunțare', (tester) async {
    await _pompeazaCard(tester);
    expect(find.text('Judecătoria Sectorul 1 București'), findsOneWidget);
    expect(find.text('Amână cauza'), findsOneWidget);
    expect(find.text('CE S-A PRONUNȚAT'), findsOneWidget);
    // Ședința mai veche apare doar după extindere.
    expect(find.text('Admite cererea de probe.'), findsNothing);

    await tester.tap(find.textContaining('toate ședințele (2)'));
    await tester.pumpAndSettle();
    expect(find.text('CE S-A PRONUNȚAT'), findsNWidgets(2));
    expect(find.text('Admite cererea de probe.'), findsOneWidget);
    expect(find.text('POPESCU ION'), findsOneWidget);
  });

  testWidgets('Semnul de carte salvează dosarul în bibliotecă', (tester) async {
    await _pompeazaCard(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Salvează în bibliotecă'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(BibliotecaService.instance.contine(_dosar.cheie), isTrue);
    expect(find.byTooltip('Scoate din bibliotecă'), findsOneWidget);
  });
}
