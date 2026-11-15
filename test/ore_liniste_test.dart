import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/main.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/setari_notificari_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _la(int ora, [int minut = 0]) => DateTime(2026, 11, 14, ora, minut);

void main() {
  final setari = SetariNotificariService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await setari.incarca();
  });

  test('Oprite implicit: nicio notificare nu e silențioasă', () {
    expect(setari.linisteActiva, isFalse);
    expect(setari.esteLiniste(_la(3)), isFalse);
  });

  test('Intervalul peste miezul nopții: 22:00–07:00', () async {
    await setari.seteazaLiniste(activ: true);
    expect(setari.esteLiniste(_la(21, 59)), isFalse);
    expect(setari.esteLiniste(_la(22)), isTrue);
    expect(setari.esteLiniste(_la(0, 30)), isTrue);
    expect(setari.esteLiniste(_la(6, 59)), isTrue);
    expect(setari.esteLiniste(_la(7)), isFalse);
    expect(setari.esteLiniste(_la(12)), isFalse);
  });

  test('Interval în aceeași zi: 13:00–15:00', () async {
    await setari.seteazaLiniste(
      activ: true,
      start: const TimeOfDay(hour: 13, minute: 0),
      stop: const TimeOfDay(hour: 15, minute: 0),
    );
    expect(setari.esteLiniste(_la(12, 59)), isFalse);
    expect(setari.esteLiniste(_la(14)), isTrue);
    expect(setari.esteLiniste(_la(15)), isFalse);
  });

  test('Dosarele importante sună și noaptea, iar setările rămân salvate', () async {
    await setari.seteazaLiniste(activ: true);
    await setari.seteazaImportant('468/310/2026|X', true);
    expect(setari.silentioasa(_la(23), cheie: '468/310/2026|X'), isFalse);
    expect(setari.silentioasa(_la(23), cheie: 'altul'), isTrue);
    expect(setari.silentioasa(_la(23)), isTrue);
    expect(setari.silentioasa(_la(10), cheie: 'altul'), isFalse);

    await setari.incarca();
    expect(setari.linisteActiva, isTrue);
    expect(setari.important('468/310/2026|X'), isTrue);

    await setari.seteazaImportant('468/310/2026|X', false);
    await setari.incarca();
    expect(setari.important('468/310/2026|X'), isFalse);
  });

  testWidgets('Din Utilități se pornesc orele de liniște', (tester) async {
    await BibliotecaService.instance.incarca();
    await tester.pumpWidget(const LegalManagementApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.widgets_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ore de liniște'));
    await tester.pumpAndSettle();

    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(setari.linisteActiva, isTrue);
  });
}
