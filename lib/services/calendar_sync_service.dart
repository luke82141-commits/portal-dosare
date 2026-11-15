import 'dart:convert';

import 'package:eventide/eventide.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import '../utils/calendar.dart' show minutDinOra;
import '../utils/formatare.dart';
import '../utils/termene.dart';
import 'biblioteca_service.dart';
import 'soap_service.dart';

/// Un calendar din telefon (Google, iCloud, Outlook etc., cum e configurat în
/// setările telefonului).
class CalendarTelefon {
  final String id;
  final String nume;
  final String cont;
  final Color culoare;

  const CalendarTelefon({
    required this.id,
    required this.nume,
    required this.cont,
    required this.culoare,
  });
}

/// Un eveniment citit din calendar.
class EvenimentCalendar {
  final String id;
  final String titlu;
  final DateTime start;
  final String descriere;
  final String locatie;

  const EvenimentCalendar({
    required this.id,
    required this.titlu,
    required this.start,
    this.descriere = '',
    this.locatie = '',
  });

  String get text => '$titlu\n$descriere\n$locatie';
}

/// Accesul la calendarele telefonului; înlocuibil în teste.
abstract class CalendareTelefon {
  Future<List<CalendarTelefon>> calendare();
  Future<List<EvenimentCalendar>> evenimente(String calendarId, DateTime de, DateTime pana);
  Future<String> creeaza({
    required String calendarId,
    required String titlu,
    required DateTime start,
    required DateTime sfarsit,
    required bool totaZiua,
    required String descriere,
    required String locatie,
    required Duration amintire,
  });

  /// Schimbă titlul și/sau descrierea unui eveniment citit înainte cu
  /// [evenimente]. Câmpurile null rămân cum sunt.
  Future<void> actualizeaza(String eventId, {String? titlu, String? descriere});
}

/// Calendarele reale, prin pachetul eventide (Android: CalendarContract,
/// deci și conturile Google; iOS: EventKit, deci și iCloud).
class CalendareEventide implements CalendareTelefon {
  final Eventide _e = Eventide();
  final _citite = <String, ETEvent>{};

  @override
  Future<List<CalendarTelefon>> calendare() async => [
    for (final c in await _e.retrieveCalendars(onlyWritableCalendars: true))
      CalendarTelefon(id: c.id, nume: c.title, cont: c.account.name, culoare: c.color),
  ];

  @override
  Future<List<EvenimentCalendar>> evenimente(String calendarId, DateTime de, DateTime pana) async {
    final ev = await _e.retrieveEvents(calendarId: calendarId, startDate: de, endDate: pana);
    for (final e in ev) {
      _citite[e.id] = e;
    }
    return [
      for (final e in ev)
        EvenimentCalendar(
          id: e.id,
          titlu: e.title,
          start: e.startDate.toLocal(),
          descriere: e.description ?? '',
          locatie: e.location ?? '',
        ),
    ];
  }

  @override
  Future<void> actualizeaza(String eventId, {String? titlu, String? descriere}) async {
    final e = _citite[eventId];
    if (e == null) return;
    _citite[eventId] = await _e.updateEvent(e, title: titlu, description: descriere);
  }

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
    final e = await _e.createEvent(
      calendarId: calendarId,
      title: titlu,
      startDate: start,
      endDate: sfarsit,
      isAllDay: totaZiua,
      description: descriere,
      location: locatie,
      reminders: [amintire],
    );
    return e.id;
  }
}

/// Un dosar găsit într-un eveniment din calendar și care nu e în bibliotecă.
class DosarDinCalendar {
  final String numar;
  final EvenimentCalendar eveniment;

  const DosarDinCalendar(this.numar, this.eveniment);
}

/// Rezultatul unei trimiteri în calendar.
class RezultatTrimitere {
  final int adaugate;
  final int existente;

  const RezultatTrimitere(this.adaugate, this.existente);
}

/// Numerele de dosar dintr-un text: „14993/299/2025”, „123/3/2026*”,
/// „55/1/2026/a1”.
final _numarDosar = RegExp(r'(?<![\d/])(\d{1,6}/\d{1,4}/(?:19|20)\d{2}(?:/a\d+)?\**)(?![\d/])');

/// Simbolurile din care se alege semnul pus în fața termenelor, ca să fie
/// găsite ușor prin căutarea din aplicația de calendar. '' = fără simbol.
const simboluriTermen = ['🌟', '⚖️', '📌', '🏛️', '📅', '🔔', '❗', ''];
const simbolImplicit = '🌟';

/// Titlul evenimentului: simbolul ales, apoi numărul dosarului, ca să se vadă
/// și în căsuțele mici din vederea pe lună.
String titluEveniment(Dosar d, {String simbol = simbolImplicit}) =>
    '${simbol.isEmpty ? '' : '$simbol '}${d.numar} · ${d.instanta}';

/// Titlul unui eveniment pus de aplicație, refăcut cu simbolul de acum: scoate
/// „Termen ” (versiunile vechi) și orice simbol din listă pus înainte.
String retitlu(String titlu, String simbol) {
  var t = titlu;
  if (t.startsWith('Termen ')) t = t.substring(7);
  for (final s in simboluriTermen) {
    if (s.isNotEmpty && t.startsWith('$s ')) {
      t = t.substring(s.length + 1);
      break;
    }
  }
  return simbol.isEmpty ? t : '$simbol $t';
}

List<String> numereDinText(String text) =>
    {for (final m in _numarDosar.allMatches(text)) m.group(1)!}.toList();

/// Eticheta pusă în descrierea fiecărui eveniment creat de aplicație. Cu ea
/// recunoaștem evenimentele noastre și nu creăm dubluri.
const _marcaj = 'ID termen Portal Dosare: ';

String cheieTermen(Dosar d, Sedinta s) {
  final z = s.data!;
  final ora = s.ora.trim().isEmpty ? 'zi' : s.ora.trim();
  return '${d.numar}|${d.institutie}|${z.year}-${z.month}-${z.day}|$ora';
}

/// Sincronizarea termenelor cu calendarele telefonului, în ambele sensuri.
/// Nu șterge niciodată nimic, nici din calendar, nici din bibliotecă.
class CalendarSyncService extends ChangeNotifier {
  CalendarSyncService._();
  static final CalendarSyncService instance = CalendarSyncService._();

  /// Se poate înlocui în teste.
  CalendareTelefon calendareTelefon = CalendareEventide();
  SoapService Function() soap = SoapService.new;

  static const _cheie = 'sincronizare_calendar_v1';

  String? calendarId;
  String? numeCalendar;
  Duration amintire = const Duration(hours: 1);
  String simbol = simbolImplicit;

  /// Câte zile în urmă se trimit și termenele trecute (0 = doar cele viitoare).
  int zileIstoric = 0;

  /// Dosarele alese pentru sincronizare (cheile lor). Null = toate.
  Set<String>? dosareAlese;
  DateTime? ultimaSincronizare;

  bool get configurat => calendarId != null;

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_cheie);
    if (s == null) return;
    final j = jsonDecode(s) as Map<String, dynamic>;
    calendarId = j['calendarId'] as String?;
    numeCalendar = j['numeCalendar'] as String?;
    amintire = Duration(minutes: (j['amintireMin'] as int?) ?? 60);
    simbol = (j['simbol'] as String?) ?? simbolImplicit;
    zileIstoric = (j['zileIstoric'] as int?) ?? 0;
    final alese = j['dosare'] as List?;
    dosareAlese = alese == null ? null : {for (final a in alese) a as String};
    final u = j['ultima'] as String?;
    ultimaSincronizare = u == null ? null : DateTime.tryParse(u);
    notifyListeners();
  }

  Future<void> salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cheie,
      jsonEncode({
        'calendarId': calendarId,
        'numeCalendar': numeCalendar,
        'amintireMin': amintire.inMinutes,
        'simbol': simbol,
        'zileIstoric': zileIstoric,
        'dosare': dosareAlese?.toList(),
        'ultima': ultimaSincronizare?.toIso8601String(),
      }),
    );
    notifyListeners();
  }

  bool esteAles(String cheie) => dosareAlese == null || dosareAlese!.contains(cheie);

  /// Trimite în calendarul ales termenele viitoare ale dosarelor alese.
  /// Termenele deja trimise (recunoscute după eticheta din descriere) nu se
  /// dublează.
  Future<RezultatTrimitere> trimite(List<Dosar> dosare, {DateTime? acum}) async {
    final id = calendarId;
    if (id == null) return const RezultatTrimitere(0, 0);
    final azi = DateUtils.dateOnly(acum ?? DateTime.now());

    final dela = azi.subtract(Duration(days: zileIstoric));
    final termene = [
      for (final d in dosare)
        if (esteAles(d.cheie))
          for (final s in d.sedinte)
            if (esteTermenViitor(s, acum: dela)) (d, s),
    ];
    if (termene.isEmpty) return const RezultatTrimitere(0, 0);

    final ultimul = termene.map((t) => t.$2.data!).reduce((a, b) => a.isAfter(b) ? a : b);
    final existente = await calendareTelefon.evenimente(
      id,
      dela,
      ultimul.add(const Duration(days: 2)),
    );
    final marcate = <String>{
      for (final e in existente)
        if (e.descriere.indexOf(_marcaj) case final i when i >= 0)
          e.descriere.substring(i + _marcaj.length).split('\n').first.trim(),
    };
    // Și evenimentele puse de mână, cu același număr de dosar în aceeași zi.
    String cheieZi(DateTime t) => '${t.year}-${t.month}-${t.day}';
    final deMana = <String>{
      for (final e in existente)
        for (final n in numereDinText(e.text)) '$n|${cheieZi(e.start)}',
    };

    // Evenimentele puse înainte primesc titlul de acum (fără „Termen ” în
    // față, cu simbolul ales) și descrierea de acum (părțile, soluția nouă).
    // Doar ale noastre, recunoscute după marcaj.
    final dupaCheie = {for (final (d, s) in termene) cheieTermen(d, s): (d, s)};
    for (final e in existente) {
      final i = e.descriere.indexOf(_marcaj);
      if (i < 0) continue;
      final titluNou = retitlu(e.titlu, simbol);
      final termen = dupaCheie[e.descriere.substring(i + _marcaj.length).split('\n').first.trim()];
      final descriereNoua = termen == null
          ? null
          : pastreazaNotite(e.descriere, descriereEveniment(termen.$1, termen.$2));
      final schimbaTitlu = titluNou != e.titlu;
      final schimbaDescriere = descriereNoua != null && descriereNoua != e.descriere;
      if (!schimbaTitlu && !schimbaDescriere) continue;
      try {
        await calendareTelefon.actualizeaza(
          e.id,
          titlu: schimbaTitlu ? titluNou : null,
          descriere: schimbaDescriere ? descriereNoua : null,
        );
      } catch (_) {}
    }

    var adaugate = 0, sarite = 0;
    for (final (d, s) in termene) {
      final cheie = cheieTermen(d, s);
      if (marcate.contains(cheie) || deMana.contains('${d.numar}|${cheieZi(s.data!)}')) {
        sarite++;
        continue;
      }
      final minut = minutDinOra(s.ora);
      final zi = DateUtils.dateOnly(s.data!);
      final start = minut == null ? zi : zi.add(Duration(minutes: minut));
      await calendareTelefon.creeaza(
        calendarId: id,
        titlu: titluEveniment(d, simbol: simbol),
        start: start,
        sfarsit: minut == null
            ? zi.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)),
        totaZiua: minut == null,
        descriere: descriereEveniment(d, s),
        locatie: '${d.instanta}, România',
        amintire: amintire,
      );
      marcate.add(cheie);
      adaugate++;
    }
    ultimaSincronizare = acum ?? DateTime.now();
    await salveaza();
    return RezultatTrimitere(adaugate, sarite);
  }

  /// Caută numere de dosar în evenimentele calendarelor [calendarIds] (cu 3
  /// luni în urmă și un an înainte) și le întoarce pe cele care nu sunt deja
  /// în bibliotecă. Evenimentele create de aplicație sunt ignorate.
  Future<List<DosarDinCalendar>> cautaInCalendare(
    Iterable<String> calendarIds, {
    DateTime? acum,
  }) async {
    final azi = DateUtils.dateOnly(acum ?? DateTime.now());
    final inBiblioteca = {for (final s in BibliotecaService.instance.dosare) s.dosar.numar};
    final gasite = <String, DosarDinCalendar>{};
    for (final id in calendarIds) {
      final ev = await calendareTelefon.evenimente(
        id,
        azi.subtract(const Duration(days: 90)),
        azi.add(const Duration(days: 365)),
      );
      for (final e in ev) {
        if (e.descriere.contains(_marcaj)) continue;
        for (final n in numereDinText(e.text)) {
          if (inBiblioteca.contains(n)) continue;
          gasite.putIfAbsent(n, () => DosarDinCalendar(n, e));
        }
      }
    }
    final l = gasite.values.toList()
      ..sort((a, b) => a.eveniment.start.compareTo(b.eveniment.start));
    return l;
  }

  /// Caută pe portal dosarele găsite în calendar și le adaugă în bibliotecă.
  /// Dintre instanțele cu același număr o alege pe cea pomenită în eveniment
  /// sau pe cea cu termen în ziua evenimentului; altfel pe cea mai recentă.
  /// Întoarce câte dosare au fost adăugate și numerele negăsite pe portal.
  Future<(int, List<String>)> adaugaInBiblioteca(List<DosarDinCalendar> alese) async {
    final client = soap();
    var adaugate = 0;
    final negasite = <String>[];
    for (final a in alese) {
      final r = await client.cautaDosare(numarDosar: a.numar);
      final potrivite = r.dosare.where((d) => d.numar == a.numar).toList();
      final d = alegeInstanta(potrivite, a.eveniment);
      if (d == null) {
        negasite.add(a.numar);
        continue;
      }
      if (!BibliotecaService.instance.contine(d.cheie)) {
        await BibliotecaService.instance.adauga(d);
        adaugate++;
      }
    }
    return (adaugate, negasite);
  }
}

String _simplu(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ăâ]'), 'a')
    .replaceAll('î', 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't');

/// Instanța potrivită pentru un eveniment, dintre dosarele cu același număr.
Dosar? alegeInstanta(List<Dosar> dosare, EvenimentCalendar e) {
  if (dosare.isEmpty) return null;
  final text = _simplu(e.text);
  for (final d in dosare) {
    if (text.contains(_simplu(d.instanta))) return d;
  }
  final zi = DateUtils.dateOnly(e.start);
  for (final d in dosare) {
    if (d.sedinte.any((s) => s.data != null && DateUtils.isSameDay(s.data, zi))) return d;
  }
  return ([
    ...dosare,
  ]..sort((a, b) => (b.data ?? DateTime(0)).compareTo(a.data ?? DateTime(0)))).first;
}

String descriereEveniment(Dosar d, Sedinta s) => [
  'Dosar nr. ${d.numar}',
  d.instanta,
  if (d.stadiuProcesual.isNotEmpty) 'Stadiu: ${d.stadiuProcesual}',
  if (d.obiect.isNotEmpty) 'Obiect: ${d.obiect}',
  if (s.complet.isNotEmpty) 'Complet: ${s.complet}',
  'Termen: ${formateazaData(s.data)}${s.ora.isEmpty ? '' : ', ora ${s.ora}'}',
  if (s.solutie.isNotEmpty)
    'Soluție: ${s.solutie}${s.solutieSumar.isEmpty ? '' : ' — ${s.solutieSumar}'}',
  ...rezumatParti(d),
  '',
  '$_marcaj${cheieTermen(d, s)}',
].join('\n');

bool _eInsolventa(Dosar d) {
  final t = '${d.obiect} ${d.categorie} ${d.sectie}'.toLowerCase();
  return t.contains('insolven') || t.contains('faliment') || t.contains('reorganizare judiciar');
}

bool _eDebitor(Parte p) => p.calitate.toLowerCase().contains('debitor');

/// Părțile pentru descrierea din calendar: cel mult [max] rânduri, ca să nu
/// umple evenimentul. La insolvență debitorul apare mereu, primul.
List<String> rezumatParti(Dosar d, {int max = 4}) {
  if (d.parti.isEmpty) return const [];
  final debitori = _eInsolventa(d) ? d.parti.where(_eDebitor).toList() : const <Parte>[];
  final restul = d.parti.where((p) => !debitori.contains(p)).toList();
  final alese = [...debitori, ...restul.take((max - debitori.length).clamp(0, max))];
  String rand(Parte p) => p.calitate.isEmpty ? p.nume : '${p.calitate}: ${p.nume}';
  final ramase = d.parti.length - alese.length;
  return [
    'Părți:',
    for (final p in alese) '• ${rand(p)}',
    if (ramase == 1) '• și încă o parte',
    if (ramase > 1) '• și încă $ramase părți',
  ];
}

/// Rândurile pe care le scrie aplicația în descriere (și cele din versiunile
/// vechi); orice alt rând e scris de utilizator.
const _prefixeAplicatie = [
  'Dosar nr. ',
  'Stadiu: ',
  'Obiect: ',
  'Complet: ',
  'Termen: ',
  'Soluție: ',
  'Părți:',
  '• ',
  _marcaj,
];

/// Descrierea [noua] plus ce a scris utilizatorul în descrierea [veche]
/// (notițe adăugate de mână în calendar), ca să nu se piardă la actualizare.
String pastreazaNotite(String veche, String noua) {
  final aleNoastre = noua.split('\n').toSet();
  final notite = [
    for (final r in veche.split('\n'))
      if (r.trim().isNotEmpty &&
          !aleNoastre.contains(r) &&
          !_prefixeAplicatie.any((p) => r.startsWith(p)))
        r,
  ];
  if (notite.isEmpty) return noua;
  return [...notite, '', noua].join('\n');
}
