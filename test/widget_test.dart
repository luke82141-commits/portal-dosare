import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';

void main() {
  testWidgets('Ecranul de căutare are câmpurile pentru număr și obiect', (tester) async {
    await tester.pumpWidget(const LegalManagementApp());
    expect(find.text('Număr dosar'), findsOneWidget);
    expect(find.text('Obiectul dosarului'), findsOneWidget);
    expect(find.text('Caută'), findsOneWidget);
  });
}
