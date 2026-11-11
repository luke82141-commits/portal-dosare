import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/data/instante_portal.dart';
import 'package:legal_management_app/screens/instante_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('lista are toate instanțele, fiecare cu număr unic', () {
    expect(toateInstantele.length, 239);
    expect(toateInstantele.map((i) => i.id).toSet().length, 239);
    expect(toateInstantele.where((i) => i.tip == TipInstanta.curteDeApel).length, 16);
  });

  test('instanța unui dosar se găsește după codul de la portal', () {
    expect(instantaDupaCod('JudecatoriaSECTORUL1BUCURESTI')?.id, 299);
    expect(instantaDupaCod('CurteadeApelBUCURESTI')?.id, 2);
    expect(instantaDupaCod('TribunalulBUCURESTI')?.id, 3);
    expect(instantaDupaCod('necunoscut'), isNull);
    expect(
      instantaDupaCod('JudecatoriaSECTORUL1BUCURESTI')!.paginaContact.toString(),
      'https://portal.just.ro/299/SitePages/contact.aspx',
    );
  });

  test('denumirile au diacritice și spațiile corecte', () {
    String nume(int id) => toateInstantele.firstWhere((i) => i.id == id).nume;
    expect(nume(299), 'Judecătoria Sectorul 1 București');
    expect(nume(287), 'Judecătoria Râmnicu Sărat');
    expect(toateInstantele.where((i) => i.nume.contains('Odorheiu Secuiesc')), hasLength(1));
  });

  testWidgets('căutarea filtrează, iar tap deschide instanța', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(BibliotecaService.instance.incarca);
    await tester.pumpWidget(MaterialApp(theme: construiesteTema(), home: const InstanteScreen()));
    await tester.enterText(find.byType(TextField), 'valenii');
    await tester.pump();
    expect(find.text('Judecătoria Vălenii de Munte'), findsOneWidget);
    expect(find.text('Judecătoria Sectorul 1 București'), findsNothing);
    await tester.tap(find.text('Judecătoria Vălenii de Munte'));
    await tester.pumpAndSettle();
    expect(find.text('Date de contact și program'), findsOneWidget);
    expect(find.text('Județul Prahova · raza Curții de Apel Ploiești'), findsOneWidget);
  });
}
