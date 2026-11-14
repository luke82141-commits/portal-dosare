import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/selecteaza_monitorizate_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/client_service.dart';
import 'package:legal_management_app/services/monitorizare_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alfa = Parte(nume: 'ALFA SRL', calitate: 'Reclamant');

Dosar _dosar(String numar, String institutie) => Dosar(
  numar: numar,
  data: DateTime(2026, 11, 1),
  institutie: institutie,
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [_alfa],
  sedinte: const [],
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await ClientService.instance.incarca();
  });

  group('Biblioteca', () {
    test('stergeToate scoate dosarele, iar restaureaza le pune la loc cu istoric', () async {
      final b = BibliotecaService.instance;
      final chei = await b.adaugaToate([
        _dosar('1/105/2026', 'TribunalulPRAHOVA'),
        _dosar('2/105/2026', 'TribunalulPRAHOVA'),
        _dosar('3/281/2026', 'JudecatoriaPLOIESTI'),
      ]);
      expect(chei, hasLength(3));
      expect(await b.adaugaToate([_dosar('1/105/2026', 'TribunalulPRAHOVA')]), isEmpty);

      final scoase = await b.stergeToate([chei[0], chei[2]]);
      expect(scoase, hasLength(2));
      expect(b.dosare.map((s) => s.dosar.numar), ['2/105/2026']);

      await b.restaureaza(scoase);
      expect(b.dosare.map((s) => s.dosar.numar).toSet(), {
        '1/105/2026',
        '2/105/2026',
        '3/281/2026',
      });
    });

    test('Filtrul găsește dosarele de la o instanță fără clientul meu', () async {
      final b = BibliotecaService.instance;
      await b.adaugaToate([
        _dosar('1/105/2026', 'TribunalulPRAHOVA'),
        _dosar('2/105/2026', 'TribunalulPRAHOVA'),
        _dosar('3/281/2026', 'JudecatoriaPLOIESTI'),
      ]);
      await ClientService.instance.comuta('1/105/2026', _alfa);
      final r = filtreazaPentruSelectie(
        b.dosare,
        institutie: 'TribunalulPRAHOVA',
        faraClient: true,
        clienti: ClientService.instance,
      );
      expect(r.map((s) => s.dosar.numar), ['2/105/2026']);
    });
  });

  group('Programul de verificare', () {
    test('Din oră în oră ziua, în zilele lucrătoare; la 4 ore noaptea și în weekend', () {
      // 13.11.2026 e vineri, 14.11.2026 sâmbătă.
      expect(intervalVerificare(DateTime(2026, 11, 13, 10)), const Duration(hours: 1));
      expect(intervalVerificare(DateTime(2026, 11, 13, 22)), const Duration(hours: 4));
      expect(intervalVerificare(DateTime(2026, 11, 13, 6)), const Duration(hours: 4));
      expect(intervalVerificare(DateTime(2026, 11, 14, 12)), const Duration(hours: 4));
      expect(intervalVerificare(DateTime(2026, 11, 15, 12)), const Duration(hours: 4));
    });

    test('Peste plafon intervalele se dublează', () {
      expect(
        intervalVerificare(DateTime(2026, 11, 13, 10), dosare: plafonDosare + 1),
        const Duration(hours: 2),
      );
      expect(
        intervalVerificare(DateTime(2026, 11, 14, 10), dosare: plafonDosare + 1),
        const Duration(hours: 8),
      );
    });
  });

  testWidgets('Selectezi dosarele unei instanțe, le scoți și anulezi', (tester) async {
    final b = BibliotecaService.instance;
    await b.adaugaToate([
      _dosar('1/105/2026', 'TribunalulPRAHOVA'),
      _dosar('2/105/2026', 'TribunalulPRAHOVA'),
      _dosar('3/281/2026', 'JudecatoriaPLOIESTI'),
    ]);
    await tester.pumpWidget(
      MaterialApp(theme: construiesteTema(), home: const SelecteazaMonitorizateScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toate instanțele'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tribunalul Prahova'));
    await tester.pumpAndSettle();
    expect(find.text('3/281/2026'), findsNothing);

    await tester.tap(find.text('Selectează tot'));
    await tester.pumpAndSettle();
    expect(find.text('2 selectate'), findsOneWidget);

    await tester.tap(find.text('Nu mai urmări (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Nu mai urmărești 2 dosare?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Nu mai urmări'));
    await tester.pumpAndSettle();
    expect(b.dosare.map((s) => s.dosar.numar), ['3/281/2026']);
    expect(find.text('2 dosare scoase din monitorizate.'), findsOneWidget);

    await tester.tap(find.text('Anulează'));
    await tester.pumpAndSettle();
    expect(b.dosare, hasLength(3));
  });
}
