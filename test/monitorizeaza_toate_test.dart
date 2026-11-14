import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/rezultate_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/cautari_recente_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar _dosar(String numar) => Dosar(
  numar: numar,
  data: DateTime(2026, 11, 1),
  institutie: 'TribunalulPRAHOVA',
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [Parte(nume: 'ALFA SRL', calitate: 'Pârât')],
  sedinte: const [],
);

class _SoapFals extends SoapService {
  final List<Dosar> dosare;
  _SoapFals(this.dosare);

  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async => RezultatCautare(dosare, false);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
  });

  testWidgets('„Monitorizează toate” pune în bibliotecă toate rezultatele', (tester) async {
    final dosare = [_dosar('1/105/2026'), _dosar('2/105/2026'), _dosar('3/105/2026')];
    await BibliotecaService.instance.adauga(dosare[1]);

    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(parte: 'Alfa SRL'),
          soap: _SoapFals(dosare),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();

    final b = BibliotecaService.instance;
    expect(b.dosare.length, 3);
    expect(b.dosare.first.dosar.numar, '1/105/2026');
    expect(find.text('2 dosare adăugate la monitorizate (1 erau deja).'), findsOneWidget);
    expect(find.text('Toate monitorizate'), findsOneWidget);
  });

  testWidgets('Peste 20 de rezultate cere confirmare', (tester) async {
    final dosare = [for (var i = 1; i <= 25; i++) _dosar('$i/105/2026')];
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(obiect: 'pretenții'),
          soap: _SoapFals(dosare),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();
    expect(find.text('Monitorizezi 25 de dosare?'), findsOneWidget);
    await tester.tap(find.text('Renunță'));
    await tester.pumpAndSettle();
    expect(BibliotecaService.instance.dosare, isEmpty);

    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Monitorizează'));
    await tester.pumpAndSettle();
    expect(BibliotecaService.instance.dosare.length, 25);
    expect(find.text('25 de dosare adăugate la monitorizate.'), findsOneWidget);
  });

  testWidgets('„Anulează” scoate doar dosarele tocmai adăugate', (tester) async {
    final dosare = [_dosar('1/105/2026'), _dosar('2/105/2026'), _dosar('3/105/2026')];
    await BibliotecaService.instance.adauga(dosare[1]);
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(parte: 'Alfa SRL'),
          soap: _SoapFals(dosare),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();
    expect(BibliotecaService.instance.dosare.length, 3);

    await tester.tap(find.text('Anulează'));
    await tester.pumpAndSettle();
    expect([for (final s in BibliotecaService.instance.dosare) s.dosar.numar], ['2/105/2026']);
  });

  testWidgets('Mesajul cu „Anulează” dispare singur după câteva secunde', (tester) async {
    final dosare = [_dosar('1/105/2026'), _dosar('2/105/2026')];
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(parte: 'Alfa SRL'),
          soap: _SoapFals(dosare),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();
    expect(find.text('Anulează'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Anulează'), findsNothing);
    expect(BibliotecaService.instance.dosare, hasLength(2));
  });

  testWidgets('Peste plafon avertizează că verificăm mai rar', (tester) async {
    await BibliotecaService.instance.adaugaToate([
      for (var i = 1; i <= 199; i++) _dosar('$i/1/2025'),
    ]);
    final dosare = [for (var i = 1; i <= 5; i++) _dosar('$i/105/2026')];
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: RezultateScreen(
          criterii: CautareRecenta(obiect: 'pretenții'),
          soap: _SoapFals(dosare),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monitorizează toate'));
    await tester.pumpAndSettle();
    expect(find.text('Monitorizezi 5 dosare?'), findsOneWidget);
    expect(find.textContaining('Vei urmări în total 204 dosare'), findsOneWidget);
  });
}
