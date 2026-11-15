import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/screens/widgeturi_screen.dart';
import 'package:legal_management_app/services/pro_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('În perioada de lansare Pro e activ fără abonament', () async {
    SharedPreferences.setMockInitialValues({});
    await ProService.instance.incarca();
    expect(ProService.perioadaLansare, isTrue);
    expect(ProService.instance.activ, isTrue);
  });

  testWidgets('Widgeturile nu mai au comutator de test pentru Pro', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(theme: construiesteTema(), home: const WidgeturiScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Pro activ (test)'), findsNothing);
    expect(find.text(ProService.etichetaLansare), findsOneWidget);
  });
}
