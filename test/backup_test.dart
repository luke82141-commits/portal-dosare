import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/backup_screen.dart';
import 'package:legal_management_app/services/backup_service.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/parti_urmarite_service.dart';
import 'package:legal_management_app/services/setari_notificari_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dosar = Dosar(
  numar: '468/310/2026',
  data: DateTime(2026, 3, 3),
  institutie: 'JudecatoriaSECTORUL1BUCURESTI',
  obiect: 'uzucapiune',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: const [],
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await SetariNotificariService.instance.incarca();
  });

  test('Backup-ul se restaurează pe un telefon gol', () async {
    await BibliotecaService.instance.adauga(_dosar);
    await SetariNotificariService.instance.seteazaLiniste(activ: true);
    await SetariNotificariService.instance.seteazaImportant(_dosar.cheie, true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sincronizare_calendar_v1', '{"calendar":"x"}');

    final json = await BackupService.exporta(acum: DateTime(2026, 11, 14));
    final date = (jsonDecode(json) as Map)['date'] as Map;
    expect(date.keys, isNot(contains('sincronizare_calendar_v1')));
    expect(date['liniste_activa_v1'], isTrue);

    // Telefonul nou.
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await SetariNotificariService.instance.incarca();
    expect(BibliotecaService.instance.dosare, isEmpty);

    final r = await BackupService.restaureaza(json);
    expect(r.dosare, 1);
    expect(BibliotecaService.instance.dosare.single.dosar.numar, '468/310/2026');
    expect(SetariNotificariService.instance.linisteActiva, isTrue);
    expect(SetariNotificariService.instance.important(_dosar.cheie), isTrue);
    expect(PartiUrmariteService.instance.parti, isEmpty);
  });

  test('Un fișier străin nu atinge datele', () async {
    await BibliotecaService.instance.adauga(_dosar);
    for (final text in ['nu e json', '{"format":"altceva","date":{}}', '[1,2]']) {
      await expectLater(BackupService.restaureaza(text), throwsA(isA<BackupException>()));
    }
    await expectLater(
      BackupService.restaureaza('{"format":"portal-dosare-backup","versiune":99,"date":{}}'),
      throwsA(isA<BackupException>()),
    );
    expect(BibliotecaService.instance.dosare.length, 1);
  });

  test('Numele fișierului are data', () {
    expect(BackupService.numeFisier(DateTime(2026, 1, 5)), 'portal-dosare-2026-01-05.json');
  });

  testWidgets('Ecranul salvează și restaurează după confirmare', (tester) async {
    await BibliotecaService.instance.adauga(_dosar);
    String? trimis;
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: BackupScreen(
          trimiteFisier: (json, nume) async => trimis = json,
          alegeFisier: () async => trimis,
        ),
      ),
    );

    await tester.tap(find.text('Salvează backup'));
    await tester.pumpAndSettle();
    expect(trimis, contains('468/310/2026'));

    await BibliotecaService.instance.sterge(_dosar.cheie);
    expect(BibliotecaService.instance.dosare, isEmpty);

    await tester.tap(find.text('Restaurează din fișier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurează'));
    await tester.pumpAndSettle();
    expect(BibliotecaService.instance.dosare.length, 1);
    expect(find.text('Am restaurat un dosar.'), findsOneWidget);
  });
}
