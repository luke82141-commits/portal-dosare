import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/statistici_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/pro_service.dart';
import 'package:legal_management_app/services/raport_service.dart';
import 'package:legal_management_app/services/statistici_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sedinta _t(DateTime zi, [String solutie = '']) => Sedinta(
  complet: 'C1',
  data: zi,
  ora: '09:00',
  solutie: solutie,
  solutieSumar: '',
);

Dosar _d(
  String numar,
  DateTime inregistrat,
  List<Sedinta> sedinte, {
  String institutie = 'TribunalulPRAHOVA',
  String stadiu = 'Fond',
}) => Dosar(
  numar: numar,
  data: inregistrat,
  institutie: institutie,
  obiect: 'pretenții',
  stadiuProcesual: stadiu,
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: sedinte,
);

DosarSalvat _s(Dosar d) => DosarSalvat(dosar: d, adaugatLa: DateTime(2026));

final _dosare = [
  _s(
    _d('1/105/2026', DateTime(2026, 2, 3), [
      _t(DateTime(2026, 3, 10), 'Amână cauza'),
      _t(DateTime(2026, 5, 12), 'Admite'),
    ]),
  ),
  _s(
    _d('2/281/2026', DateTime(2026, 2, 20), [
      _t(DateTime(2026, 6, 1), 'Respinge'),
    ], institutie: 'JudecatoriaPLOIESTI'),
  ),
  _s(
    _d(
      '3/42/2025',
      DateTime(2025, 9, 1),
      [
        _t(DateTime(2025, 10, 1), 'Amânare'),
        _t(DateTime(2026, 11, 4), 'Admite în parte'),
        _t(DateTime(2026, 12, 9)),
      ],
      institutie: 'CurteadeApelPLOIESTI',
      stadiu: 'Apel',
    ),
  ),
];

void main() {
  test('Statisticile pe an: luni, amânări, soluții, faze, instanțe', () {
    final s = calculeazaStatistici(_dosare, 2026);
    expect(s.totalDosare, 2);
    expect(s.dosareInregistrate[1], 2);
    expect(s.totalDosareAnTrecut, 1);
    expect(s.totalTermene, 5);
    expect(s.termene[10], 1);
    expect(s.totalTermeneAnTrecut, 1);
    expect(s.amanari, 1);
    expect(s.amanariAnTrecut, 1);
    expect(s.solutii[TipSolutie.admite], 1);
    expect(s.solutii[TipSolutie.admiteInParte], 1);
    expect(s.solutii[TipSolutie.respinge], 1);
    expect(s.totalHotarari, 3);
    expect(s.solutiiPeFaze['Apel']![TipSolutie.admiteInParte], 1);
    expect(s.solutiiPeFaze['Fond']![TipSolutie.admite], 1);
    expect(s.instante, [
      ('Curtea de Apel Ploiești', 2),
      ('Tribunalul Prahova', 2),
      ('Judecătoria Ploiești', 1),
    ]);
  });

  test('Variația față de anul trecut', () {
    expect(variatie(5, 4, 2025), '+25% față de 2025');
    expect(variatie(3, 4, 2025), '−25% față de 2025');
    expect(variatie(4, 4, 2025), 'la fel ca în 2025');
    expect(variatie(4, 0, 2025), '');
  });

  testWidgets('Ecranul arată cifrele și graficele', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final b = BibliotecaService.instance;
    await b.incarca();
    for (final s in _dosare) {
      await b.adauga(s.dosar);
    }
    await ProService.instance.incarca();

    final captura = Platform.environment['CAPTURA'];
    if (captura != null) {
      await tester.runAsync(() async {
        for (final fam in ['Roboto', '']) {
          final l = FontLoader(fam)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
                      .readAsBytesSync(),
                ),
              ),
            );
          await l.load();
        }
        final l = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await l.load();
      });
    }
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: construiesteTema(),
        home: const RepaintBoundary(child: StatisticiScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anul ${DateTime.now().year}'), findsOneWidget);
    expect(find.text('Termene de judecată'), findsOneWidget);
    expect(find.text('Soluții pe faze procesuale'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (captura != null) {
      final r = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final img = await r.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(captura).writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}
