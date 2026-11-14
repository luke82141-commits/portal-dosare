import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/screens/sugestie_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Emailul are subiect, text, versiune și sistem', () {
    final uri = emailSugestie(
      TipSugestie.problema,
      '  Nu apare termenul & ora ',
      platforma: 'android 15',
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, adresaSugestii);
    expect(uri.query, isNot(contains('+')));
    final p = Uri.splitQueryString(uri.query);
    expect(p['subject'], 'Portal Dosare · Ceva nu merge');
    expect(p['body'], startsWith('Nu apare termenul & ora\n'));
    expect(p['body'], contains('Versiunea aplicației: $versiuneAplicatie'));
    expect(p['body'], endsWith('Sistem: android 15'));
  });

  testWidgets('Din Căutare se deschide „Trimite o sugestie”', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Trimite o sugestie'));
    await tester.pumpAndSettle();
    expect(find.text('Trimite pe email'), findsOneWidget);

    await tester.tap(find.text('Trimite pe email'));
    await tester.pump();
    expect(find.text('Scrie mai întâi sugestia.'), findsOneWidget);

    await tester.tap(find.text('Ceva nu merge'));
    await tester.pump();
    expect(find.textContaining('ce s-a întâmplat'), findsOneWidget);
  });
}
