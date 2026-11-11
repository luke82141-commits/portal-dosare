import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/sincronizare_calendar_screen.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/calendar_sync_service.dart';
import 'package:legal_management_app/services/soap_service.dart';
import 'package:legal_management_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CalendarFals implements CalendareTelefon {
  final List<EvenimentCalendar> evenimenteExistente;
  final creat = <Map<String, Object>>[];

  _CalendarFals([List<EvenimentCalendar>? e]) : evenimenteExistente = e ?? [];

  @override
  Future<List<CalendarTelefon>> calendare() async => const [
        CalendarTelefon(id: 'g1', nume: 'Termene', cont: 'luke@gmail.com', culoare: Colors.blue),
        CalendarTelefon(id: 'i1', nume: 'Acasă', cont: 'iCloud', culoare: Colors.red),
      ];

  @override
  Future<List<EvenimentCalendar>> evenimente(String calendarId, DateTime de, DateTime pana) async =>
      evenimenteExistente.where((e) => !e.start.isBefore(de) && e.start.isBefore(pana)).toList();

  @override
  Future<String> creeaza({
    required String calendarId,
    required String titlu,
    required DateTime start,
    required DateTime sfarsit,
    required bool totaZiua,
    required String descriere,
    required String locatie,
    required Duration amintire,
  }) async {
    final id = 'e${creat.length}';
    creat.add({'titlu': titlu, 'start': start, 'totaZiua': totaZiua, 'locatie': locatie, 'amintire': amintire});
    evenimenteExistente.add(EvenimentCalendar(id: id, titlu: titlu, start: start, descriere: descriere, locatie: locatie));
    return id;
  }
}

class _SoapFals extends SoapService {
  final List<Dosar> dosare;
  _SoapFals(this.dosare);

  @override
  Future<RezultatCautare> cautaDosare({String numarDosar = '', String obiectDosar = ''}) async =>
      RezultatCautare(dosare.where((d) => d.numar == numarDosar).toList(), false);
}

Sedinta _s(DateTime d, String ora) => Sedinta(complet: 'C1', data: d, ora: ora, solutie: '', solutieSumar: '');

Dosar _d(String numar, String inst, List<Sedinta> s) => Dosar(
      numar: numar,
      data: DateTime(2026, 1, 1),
      institutie: inst,
      obiect: 'pretenții',
      stadiuProcesual: 'Fond',
      sectie: '',
      categorie: '',
      parti: const [],
      sedinte: s,
    );

void main() {
  final acum = DateTime(2026, 11, 11);
  final sync = CalendarSyncService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BibliotecaService.instance.incarca();
    sync
      ..calendarId = 'g1'
      ..dosareAlese = null
      ..amintire = const Duration(hours: 1);
  });

  test('numerele de dosar se recunosc în text', () {
    expect(numereDinText('Termen 14993/299/2025 la Jud. S1; vezi și 55/1/2026/a1 și 12/3/2026*'),
        ['14993/299/2025', '55/1/2026/a1', '12/3/2026*']);
    expect(numereDinText('telefon 0721/123/456 și 11/11/2026'), ['11/11/2026']);
  });

  test('trimite termenele viitoare, cu locația instanței, fără dubluri', () async {
    final cal = _CalendarFals();
    sync.calendareTelefon = cal;
    final d = _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [
      _s(DateTime(2026, 11, 20), '09:30'),
      _s(DateTime(2026, 12, 4), ''),
      _s(DateTime(2026, 10, 1), '09:00'), // trecut
    ]);
    final r = await sync.trimite([d], acum: acum);
    expect(r.adaugate, 2);
    expect(cal.creat.first['titlu'], 'Termen 14993/299/2025 · Judecătoria Sectorul 1 București');
    expect(cal.creat.first['start'], DateTime(2026, 11, 20, 9, 30));
    expect(cal.creat.first['locatie'], 'Judecătoria Sectorul 1 București, România');
    expect(cal.creat.first['amintire'], const Duration(hours: 1));
    expect(cal.creat.last['totaZiua'], isTrue);

    final aDouaOara = await sync.trimite([d], acum: acum);
    expect(aDouaOara.adaugate, 0);
    expect(aDouaOara.existente, 2);
    expect(cal.creat, hasLength(2));
  });

  test('un eveniment pus de mână pentru același dosar și zi nu se dublează', () async {
    final cal = _CalendarFals([
      EvenimentCalendar(id: 'x', titlu: 'Instanță 14993/299/2025', start: DateTime(2026, 11, 20, 9)),
    ]);
    sync.calendareTelefon = cal;
    final d = _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [_s(DateTime(2026, 11, 20), '09:30')]);
    expect((await sync.trimite([d], acum: acum)).adaugate, 0);
  });

  test('trimite doar dosarele bifate', () async {
    final cal = _CalendarFals();
    sync
      ..calendareTelefon = cal
      ..dosareAlese = {'2/2/2026|TribunalulBUCURESTI'};
    await sync.trimite([
      _d('1/1/2026', 'TribunalulBUCURESTI', [_s(DateTime(2026, 11, 20), '09:00')]),
      _d('2/2/2026', 'TribunalulBUCURESTI', [_s(DateTime(2026, 11, 21), '09:00')]),
    ], acum: acum);
    expect(cal.creat.single['titlu'], 'Termen 2/2/2026 · Tribunalul București');
  });

  test('din calendar se adaugă doar dosarele noi, la instanța pomenită', () async {
    final existent = _d('1/1/2026', 'TribunalulBUCURESTI', const []);
    await BibliotecaService.instance.adauga(existent);
    sync.calendareTelefon = _CalendarFals([
      EvenimentCalendar(id: 'a', titlu: 'Termen 1/1/2026', start: DateTime(2026, 11, 20, 9)),
      EvenimentCalendar(
        id: 'b',
        titlu: 'Dosar 777/3/2026 - Tribunalul București',
        start: DateTime(2026, 11, 25, 10),
      ),
    ]);
    final gasite = await sync.cautaInCalendare(['g1'], acum: acum);
    expect(gasite.map((g) => g.numar), ['777/3/2026']);

    sync.soap = () => _SoapFals([
          _d('777/3/2026', 'JudecatoriaSECTORUL1BUCURESTI', const []),
          _d('777/3/2026', 'TribunalulBUCURESTI', const []),
        ]);
    final (n, negasite) = await sync.adaugaInBiblioteca(gasite);
    expect(n, 1);
    expect(negasite, isEmpty);
    expect(BibliotecaService.instance.contine('777/3/2026|TribunalulBUCURESTI'), isTrue);
    expect(BibliotecaService.instance.contine('777/3/2026|JudecatoriaSECTORUL1BUCURESTI'), isFalse);
  });

  testWidgets('ecranul: alegi calendarul, bifezi dosarele și trimiți', (tester) async {
    final cal = _CalendarFals();
    sync
      ..calendareTelefon = cal
      ..calendarId = null;
    await tester.runAsync(() => BibliotecaService.instance.adauga(
          _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [_s(DateTime.now().add(const Duration(days: 9)), '09:30')]),
        ));
    await tester.pumpWidget(MaterialApp(theme: construiesteTema(), home: const SincronizareCalendarScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Termene'), findsOneWidget);
    expect(find.text('Alege întâi un calendar.'), findsOneWidget);
    await tester.tap(find.text('Termene'));
    await tester.pumpAndSettle();
    expect(sync.calendarId, 'g1');
    await tester.ensureVisible(find.text('Sincronizează un dosar în calendar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Sincronizează un dosar în calendar'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(cal.creat, hasLength(1));
    expect(find.text('Un dosar sincronizat în calendar.'), findsOneWidget);
  });
}
