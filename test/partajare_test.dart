import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:legal_management_app/widgets/elemente.dart';
import 'package:legal_management_app/widgets/partajare_solutie.dart';

final _sedinta = Sedinta(
  complet: 'C12',
  data: DateTime(2025, 11, 4),
  ora: '09:00',
  solutie: 'Admite în parte',
  solutieSumar: 'Admite în parte cererea. Obligă pârâta la plata sumei de 12.400 lei.',
  document: 'SentintaCivila',
  numarDocument: '5123/2025',
  dataDocument: DateTime(2025, 11, 4),
);

final _dosar = Dosar(
  numar: '14993/299/2025',
  data: DateTime(2025, 2, 10),
  institutie: 'JudecatoriaSECTORUL1BUCURESTI',
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: [_sedinta],
);

void main() {
  test('textul distribuit păstrează dosarul, instanța, data și soluția', () {
    expect(
      textSolutie(_sedinta, dosar: _dosar),
      'Dosar nr. 14993/299/2025\n'
      'Judecătoria Sectorul 1 București\n'
      'Stadiu: Fond\n'
      '\n'
      'Soluție: Admite în parte\n'
      'Admite în parte cererea. Obligă pârâta la plata sumei de 12.400 lei.\n'
      '\n'
      'Data pronunțării: 04.11.2025\n'
      'Ora ședinței: 09:00\n'
      'Complet: C12\n'
      'Document: Sentință civilă nr. 5123/2025 din 04.11.2025\n'
      '\n'
      'Sursa: portal.just.ro',
    );
  });

  testWidgets('apăsare lungă pe soluție: Copiază pune textul în clipboard', (tester) async {
    String? copiat;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copiat = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      theme: construiesteTema(),
      home: Scaffold(body: SedintaRand(sedinta: _sedinta, dosar: _dosar)),
    ));
    await tester.longPress(find.text('Admite în parte'));
    await tester.pumpAndSettle();
    expect(find.text('Distribuie'), findsOneWidget);
    await tester.tap(find.text('Copiază'));
    await tester.pumpAndSettle();
    expect(copiat, textSolutie(_sedinta, dosar: _dosar));
    expect(find.text('Soluția a fost copiată.'), findsOneWidget);
  });
}
