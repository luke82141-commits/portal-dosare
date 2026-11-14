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

  final redenumite = <String, String>{};
  final redescrise = <String, String>{};

  @override
  Future<void> actualizeaza(String eventId, {String? titlu, String? descriere}) async {
    if (titlu != null) redenumite[eventId] = titlu;
    if (descriere != null) redescrise[eventId] = descriere;
    final i = evenimenteExistente.indexWhere((e) => e.id == eventId);
    final e = evenimenteExistente[i];
    evenimenteExistente[i] = EvenimentCalendar(
        id: e.id,
        titlu: titlu ?? e.titlu,
        start: e.start,
        descriere: descriere ?? e.descriere,
        locatie: e.locatie);
  }
}

class _SoapFals extends SoapService {
  final List<Dosar> dosare;
  _SoapFals(this.dosare);

  @override
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async =>
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
      ..amintire = const Duration(hours: 1)
      ..simbol = simbolImplicit
      ..zileIstoric = 0;
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
    expect(cal.creat.first['titlu'], '🌟 14993/299/2025 · Judecătoria Sectorul 1 București');
    expect(cal.creat.first['start'], DateTime(2026, 11, 20, 9, 30));
    expect(cal.creat.first['locatie'], 'Judecătoria Sectorul 1 București, România');
    expect(cal.creat.first['amintire'], const Duration(hours: 1));
    expect(cal.creat.last['totaZiua'], isTrue);

    final aDouaOara = await sync.trimite([d], acum: acum);
    expect(aDouaOara.adaugate, 0);
    expect(aDouaOara.existente, 2);
    expect(cal.creat, hasLength(2));
  });

  test('cu istoric pornit, trimite și termenele trecute din interval', () async {
    final cal = _CalendarFals();
    sync
      ..calendareTelefon = cal
      ..zileIstoric = 365;
    final d = _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [
      _s(DateTime(2026, 11, 20), '09:30'),
      _s(DateTime(2026, 10, 1), '09:00'),
      _s(DateTime(2025, 6, 1), '09:00'), // mai vechi de un an
    ]);
    final r = await sync.trimite([d], acum: acum);
    expect(r.adaugate, 2);
    expect(cal.creat.map((e) => e['start']), contains(DateTime(2026, 10, 1, 9)));
    expect((await sync.trimite([d], acum: acum)).adaugate, 0);
  });

  test('descrierea are părțile: cel mult 4, iar la insolvență debitorul primul', () {
    Dosar cu(List<Parte> parti, {String obiect = 'pretenții'}) => Dosar(
          numar: '1/105/2026',
          data: DateTime(2026, 1, 1),
          institutie: 'TribunalulPRAHOVA',
          obiect: obiect,
          stadiuProcesual: 'Fond',
          sectie: '',
          categorie: '',
          parti: parti,
          sedinte: const [],
        );
    final parti = [
      for (var i = 1; i <= 6; i++) Parte(nume: 'CREDITOR $i SRL', calitate: 'Creditor'),
      const Parte(nume: 'ALFA SRL', calitate: 'Debitor'),
    ];
    expect(rezumatParti(cu(parti.take(2).toList())), [
      'Părți:',
      '• Creditor: CREDITOR 1 SRL',
      '• Creditor: CREDITOR 2 SRL',
    ]);
    expect(rezumatParti(cu(parti)), [
      'Părți:',
      '• Creditor: CREDITOR 1 SRL',
      '• Creditor: CREDITOR 2 SRL',
      '• Creditor: CREDITOR 3 SRL',
      '• Creditor: CREDITOR 4 SRL',
      '• și încă 3 părți',
    ]);
    expect(rezumatParti(cu(parti, obiect: 'procedura insolvenței - societăți')), [
      'Părți:',
      '• Debitor: ALFA SRL',
      '• Creditor: CREDITOR 1 SRL',
      '• Creditor: CREDITOR 2 SRL',
      '• Creditor: CREDITOR 3 SRL',
      '• și încă 3 părți',
    ]);
    expect(rezumatParti(cu(const [])), isEmpty);
  });

  test('evenimentele deja trimise primesc descrierea nouă, cu părțile', () async {
    final cal = _CalendarFals();
    sync.calendareTelefon = cal;
    final fara = _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [_s(DateTime(2026, 11, 20), '09:30')]);
    await sync.trimite([fara], acum: acum);
    final e = cal.evenimenteExistente.single;
    expect(e.descriere, isNot(contains('Părți')));

    final cu = Dosar(
      numar: fara.numar,
      data: fara.data,
      institutie: fara.institutie,
      obiect: fara.obiect,
      stadiuProcesual: fara.stadiuProcesual,
      sectie: '',
      categorie: '',
      parti: const [Parte(nume: 'POPESCU ION', calitate: 'Reclamant')],
      sedinte: fara.sedinte,
    );
    expect((await sync.trimite([cu], acum: acum)).adaugate, 0);
    expect(cal.redescrise[e.id], contains('• Reclamant: POPESCU ION'));
    expect(cal.redenumite, isEmpty);

    cal.redescrise.clear();
    await sync.trimite([cu], acum: acum);
    expect(cal.redescrise, isEmpty);
  });

  test('evenimentele vechi, care încep cu „Termen”, sunt redenumite', () async {
    final cal = _CalendarFals();
    sync.calendareTelefon = cal;
    final d = _d('14993/299/2025', 'JudecatoriaSECTORUL1BUCURESTI', [_s(DateTime(2026, 11, 20), '09:30')]);
    await sync.trimite([d], acum: acum);
    // Cum arăta un eveniment pus de versiunea veche.
    final e = cal.evenimenteExistente.single;
    cal.evenimenteExistente[0] = EvenimentCalendar(
        id: e.id, titlu: e.titlu.replaceFirst('🌟 ', 'Termen '), start: e.start, descriere: e.descriere, locatie: e.locatie);
    // Și unul pus de mână, care trebuie lăsat în pace.
    cal.evenimenteExistente.add(EvenimentCalendar(id: 'm', titlu: 'Termen avocat', start: DateTime(2026, 11, 20, 12)));

    final r = await sync.trimite([d], acum: acum);
    expect(r.adaugate, 0);
    expect(cal.redenumite, {e.id: '🌟 14993/299/2025 · Judecătoria Sectorul 1 București'});

    // Alt simbol ales: și evenimentele existente îl primesc.
    sync.simbol = '⚖️';
    await sync.trimite([d], acum: acum);
    expect(cal.redenumite[e.id], '⚖️ 14993/299/2025 · Judecătoria Sectorul 1 București');
    sync.simbol = '';
    await sync.trimite([d], acum: acum);
    expect(cal.redenumite[e.id], '14993/299/2025 · Judecătoria Sectorul 1 București');
    expect(cal.redenumite.keys, isNot(contains('m')));
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
    expect(cal.creat.single['titlu'], '🌟 2/2/2026 · Tribunalul București');
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
