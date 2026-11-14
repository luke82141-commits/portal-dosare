import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/dosar_detaliu_screen.dart';
import 'package:legal_management_app/screens/rezultate_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/widgets/dosar_card.dart';
import 'package:legal_management_app/widgets/parcurs_dosar.dart';
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

class _SoapFals extends SoapService {
  final List<Dosar> dosare;
  _SoapFals([List<Dosar>? dosare]) : dosare = dosare ?? [_dosar];

  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async =>
      RezultatCautare(dosare, false);
}

final _apel = Dosar(
  numar: '468/310/2026',
  data: DateTime(2026, 10, 1),
  institutie: 'TribunalulPRAHOVA',
  obiect: 'uzucapiune',
  stadiuProcesual: 'Apel',
  sectie: 'Secția I Civilă',
  categorie: 'Civil',
  parti: const [],
  sedinte: [
    Sedinta(
      complet: 'A2',
      data: DateTime(2026, 10, 20),
      ora: '10:30',
      solutie: 'Respinge apelul',
      solutieSumar: 'Respinge apelul ca nefondat. Definitivă.',
    ),
  ],
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    ParcursDosar.golesteCache();
    ParcursDosar.soap = _SoapFals.new;
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

  testWidgets('Calendarele și dialogurile sistemului sunt în română', (tester) async {
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    final l = MaterialLocalizations.of(tester.element(find.text('Caută dosar')));
    expect(l.firstDayOfWeekIndex, 1); // săptămâna începe luni
    expect(l.formatMonthYear(DateTime(2026, 11)).toLowerCase(), contains('noiembrie'));
  });

  testWidgets('Căutarea are numele părții, instanța și intervalul', (tester) async {
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    expect(find.text('Nume parte'), findsOneWidget);
    expect(find.text('Instanța'), findsNothing);

    await tester.tap(find.text('Mai multe criterii'));
    await tester.pumpAndSettle();
    expect(find.text('Instanța'), findsOneWidget);
    expect(find.text('Toate instanțele'), findsOneWidget);
    expect(find.text('Înregistrat între'), findsOneWidget);

    await tester.tap(find.text('Toate instanțele'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Caută instanța sau județul'), 'sinaia');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Judecătoria Sinaia'));
    await tester.pumpAndSettle();
    expect(find.text('Judecătoria Sinaia'), findsOneWidget);

    // Instanța singură nu ajunge: portalul cere număr, obiect sau parte.
    await tester.ensureVisible(find.text('Caută dosar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caută dosar'), warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Introdu numărul dosarului, obiectul sau numele unei părți.'), findsOneWidget);
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
    // Părțile și ședințele sunt restrânse până le atingi.
    expect(find.text('POPESCU ION'), findsNothing);
    expect(find.text('Admite cererea de probe.'), findsNothing);
    await tester.ensureVisible(find.text('Părți'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Părți'));
    await tester.pumpAndSettle();
    expect(find.text('POPESCU ION'), findsOneWidget);
    await tester.ensureVisible(find.text('Ședințe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ședințe'));
    await tester.pumpAndSettle();
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

  testWidgets('Din detaliu se poate sări la alt dosar monitorizat', (tester) async {
    final altul = Dosar(
      numar: '5900/2/2026',
      data: DateTime(2026, 9, 16),
      institutie: 'CurteadeApelBUCURESTI',
      obiect: 'suspendare executare act administrativ',
      stadiuProcesual: 'Recurs',
      sectie: '',
      categorie: '',
      parti: const [],
      sedinte: const [],
    );
    await tester.runAsync(() async {
      await BibliotecaService.instance.adauga(_dosar);
      await BibliotecaService.instance.adauga(altul);
    });
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dosarele mele'));
    await tester.pumpAndSettle();
    expect(find.text('2 dosare monitorizate'), findsOneWidget);

    await tester.tap(find.text('5900/2/2026'));
    await tester.pumpAndSettle();
    expect(find.text('suspendare executare act administrativ'), findsOneWidget);
    expect(find.text('468/310/2026'), findsNothing);
  });

  testWidgets('Tap pe instanță filtrează dosarele salvate', (tester) async {
    final altaInstanta = Dosar(
      numar: '5900/2/2026',
      data: DateTime(2026, 9, 16),
      institutie: 'CurteadeApelBUCURESTI',
      obiect: 'suspendare executare',
      stadiuProcesual: 'Recurs',
      sectie: '',
      categorie: 'Civil',
      parti: const [],
      sedinte: const [],
    );
    await tester.runAsync(() async {
      await BibliotecaService.instance.adauga(_dosar);
      await BibliotecaService.instance.adauga(altaInstanta);
    });
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Judecătoria Sectorul 1 București'));
    await tester.pumpAndSettle();
    expect(find.text('Dosarele mele'), findsOneWidget);
    expect(find.text('Un dosar'), findsOneWidget);
    expect(find.text('5900/2/2026'), findsNothing);

    // Scos filtrul de instanță: apar ambele dosare.
    await tester.tap(find.byTooltip('Scoate filtrul'));
    await tester.pumpAndSettle();
    expect(find.text('2 dosare'), findsOneWidget);
  });

  testWidgets('Din rezultate dosarul se adaugă și se scoate din bibliotecă', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: construiesteTema(),
      home: RezultateScreen(numar: '468/310/2026', soap: _SoapFals()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Adaugă'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Adaugă în bibliotecă'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(BibliotecaService.instance.contine(_dosar.cheie), isTrue);
    expect(find.text('În bibliotecă'), findsOneWidget);

    await tester.tap(find.byTooltip('Scoate din bibliotecă'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Oprește'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(BibliotecaService.instance.contine(_dosar.cheie), isFalse);
    expect(find.text('Adaugă'), findsOneWidget);
  });

  testWidgets('La fond apare și calea de atac, cu soluția și ședințele ei', (tester) async {
    ParcursDosar.soap = () => _SoapFals([_dosar, _apel]);
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();
    expect(find.text('Parcursul dosarului'), findsOneWidget);
    expect(find.text('Tribunalul Prahova'), findsOneWidget);
    expect(find.text('Soluție: Respinge apelul'), findsOneWidget);
    expect(find.text('20.10.2026 · ora 10:30 · Complet A2'), findsOneWidget);
    // Soluția de la fond apare și ea, în aceeași cronologie.
    expect(find.text('Soluție: Amână cauza'), findsOneWidget);
    // Ierarhic: tribunalul (apel) deasupra judecătoriei (fond).
    expect(
      tester.getTopLeft(find.text('Tribunalul Prahova')).dy,
      lessThan(tester.getTopLeft(find.text('Soluție: Amână cauza')).dy),
    );
    await tester.tap(find.text('Ședințe (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Respinge apelul ca nefondat. Definitivă.'), findsWidgets);
  });

  testWidgets('Tap pe o soluție lungă din parcurs o arată întreagă', (tester) async {
    final lung = 'Admite apelul. ${'Schimbă în parte sentința apelată. ' * 12}Definitivă.';
    final apel = Dosar(
      numar: _apel.numar,
      data: _apel.data,
      institutie: _apel.institutie,
      obiect: _apel.obiect,
      stadiuProcesual: 'Apel',
      sectie: _apel.sectie,
      categorie: 'Civil',
      parti: const [],
      sedinte: [
        Sedinta(
          complet: 'A2',
          data: DateTime(2026, 10, 20),
          ora: '10:30',
          solutie: 'Schimbat în parte',
          solutieSumar: lung,
        ),
      ],
    );
    ParcursDosar.soap = () => _SoapFals([_dosar, apel]);
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();
    expect(find.text(lung), findsNothing);

    await tester.ensureVisible(find.text('Arată toată soluția'));
    await tester.tap(find.text('Soluție: Schimbat în parte'));
    await tester.pumpAndSettle();
    expect(find.text(lung), findsOneWidget);
    expect(find.text('Restrânge'), findsOneWidget);

    await tester.tap(find.text('Restrânge'));
    await tester.pumpAndSettle();
    expect(find.text(lung), findsNothing);
  });

  testWidgets('Fără alte instanțe, parcursul nu apare', (tester) async {
    await _pompeazaCard(tester);
    await tester.tap(find.byType(DosarCardWidget));
    await tester.pumpAndSettle();
    expect(find.text('Parcursul dosarului'), findsNothing);
    expect(find.textContaining('apare doar la'), findsNothing);
  });

  testWidgets('În apel, fără fondul pe portal, spune ce lipsește', (tester) async {
    ParcursDosar.soap = () => _SoapFals([_apel]);
    await tester.pumpWidget(MaterialApp(theme: construiesteTema(), home: DosarDetaliuScreen(dosar: _apel)));
    await tester.pumpAndSettle();
    expect(find.text('Parcursul dosarului'), findsNothing);
    expect(find.textContaining('apare doar la Tribunalul Prahova'), findsOneWidget);
    expect(find.text('Reîncearcă'), findsOneWidget);
  });
}
