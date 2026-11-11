import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
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
        theme: construiesteTema(),
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
    expect(find.text('Caută dosar'), findsOneWidget);

    await tester.tap(find.text('Monitorizate'));
    await tester.pumpAndSettle();
    expect(find.text('Niciun dosar monitorizat'), findsOneWidget);

    await tester.tap(find.text('Notificări'));
    await tester.pumpAndSettle();
    expect(find.text('Nicio notificare'), findsOneWidget);
  });

  testWidgets('Cardul e compact: instanța, obiectul și ultima soluție', (tester) async {
    await _pompeazaCard(tester);
    expect(find.text('468/310/2026'), findsOneWidget);
    expect(find.text('Judecătoria Sectorul 1 București · Secția Civilă'), findsOneWidget);
    expect(find.text('uzucapiune'), findsOneWidget);
    expect(find.text('Ultima soluție: Amână cauza'), findsOneWidget);
    // Părțile și ședințele apar doar în detaliu.
    expect(find.text('POPESCU ION'), findsNothing);
  });

  testWidgets('Tap pe card deschide detaliul cu părți și ședințe', (tester) async {
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();
    expect(find.text('Detaliu dosar'), findsOneWidget);
    expect(find.text('POPESCU ION'), findsOneWidget);
    expect(find.text('Amână cauza'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Admite cererea de probe.'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Admite cererea de probe.'), findsOneWidget);
  });

  testWidgets('Butonul din detaliu pornește monitorizarea', (tester) async {
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Monitorizează dosarul'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(BibliotecaService.instance.contine(_dosar.cheie), isTrue);
    expect(find.byTooltip('Oprește monitorizarea'), findsOneWidget);
    expect(find.text('Monitorizare activă'), findsOneWidget);
  });
}
