import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _inaltimeBara(WidgetTester tester) => tester.getSize(find.byType(NavigationBar)).height;

bool _barVizibila(WidgetTester tester) =>
    tester.getRect(find.byType(NavigationBar)).top <
    tester.getSize(find.byType(MaterialApp)).height - 1;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
  });

  testWidgets('La derulare în jos bara se strânge în buton, iar butonul o readuce', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    expect(_inaltimeBara(tester), greaterThan(0));
    expect(_barVizibila(tester), isTrue);

    // Instanțele au o listă lungă.
    await tester.tap(find.byIcon(Icons.account_balance_outlined));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_barVizibila(tester), isFalse);

    await tester.tap(find.byTooltip('Arată bara de navigare'));
    await tester.pumpAndSettle();
    expect(_barVizibila(tester), isTrue);

    // Și derularea în sus o aduce înapoi.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_barVizibila(tester), isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(_barVizibila(tester), isTrue);
  });

  testWidgets('Pe Căutare, lupa rotundă pornește căutarea și ascunde tastatura', (tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ex. SC Exemplu SRL, Popescu Ion (opțional)'),
      'Cantacuzino',
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_barVizibila(tester), isFalse);

    await tester.tap(find.byTooltip('Caută'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Rezultate'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
  });

  testWidgets('Utilități arată uneltele gratuite și pe cele Pro', (tester) async {
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.widgets_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Părți urmărite'), findsOneWidget);
    expect(find.text('PRO · ÎN CURÂND'), findsOneWidget);
    expect(find.text('Rapoarte'), findsOneWidget);
    expect(find.text('Statistici'), findsOneWidget);

    await tester.tap(find.text('Părți urmărite'));
    await tester.pumpAndSettle();
    expect(find.text('Nicio parte urmărită'), findsOneWidget);
  });

  testWidgets('Bara cu șase file încape pe un telefon îngust', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    for (final icon in [
      Icons.bookmark_border,
      Icons.calendar_month_outlined,
      Icons.notifications_none,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
