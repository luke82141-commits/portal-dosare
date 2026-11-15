import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/calendar_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/utils/calendar.dart';
import 'package:legal_management_app/utils/ruta.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/widgets/parcurs_dosar.dart';
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

class _SoapGol extends SoapService {
  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async =>
      const RezultatCautare([], false);
}

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
      ParcursDosar.soap = _SoapGol.new;
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

    testWidgets('luna arată cel mult 4 termene pe zi, apoi „…”', (tester) async {
      final zi = DateTime(2026, 11, 13);
      await tester.runAsync(() async {
        for (var i = 1; i <= 6; i++) {
          await BibliotecaService.instance.adauga(_d('$i/1/2026', [_s(zi, '0$i:00')]));
        }
      });
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: construiesteTema(),
        home: Scaffold(
          body: CalendarScreen(azi: DateTime(2026, 11, 11)),
          bottomNavigationBar: NavigationBar(destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'a'),
            NavigationDestination(icon: Icon(Icons.search), label: 'b'),
          ]),
        ),
      ));
      for (var i = 1; i <= 4; i++) {
        expect(find.text('$i/1'), findsOneWidget);
      }
      expect(find.text('5/1'), findsNothing);
      expect(find.text('… +2'), findsOneWidget);

      // Ziua → vederea pe zi → detaliul dosarului.
      await tester.tap(find.text('… +2'));
      await tester.pumpAndSettle();
      expect(find.text('Vineri, 13 noiembrie'), findsOneWidget);
      await tester.tap(find.text('6/1/2026'));
      await tester.pumpAndSettle();
      expect(find.text('Detaliu dosar'), findsOneWidget);
      expect(find.text('Mergi la instanță'), findsOneWidget);
    });
  });

  test('rutele către instanță pornesc din locația curentă', () {
    final g = rutaGoogleMaps('Judecătoria Sectorul 1 București');
    expect(g.host, 'www.google.com');
    expect(g.queryParameters['destination'], 'Judecătoria Sectorul 1 București, România');
    expect(g.queryParameters.containsKey('origin'), isFalse);
    final w = rutaWaze('Tribunalul București');
    expect(w.queryParameters, {'q': 'Tribunalul București, România', 'navigate': 'yes'});
  });
}
