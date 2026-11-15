import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import 'calendar_sync_service.dart' show rezumatParti;

/// Rapoartele Pro: săptămânal, lunar și anual. Tot ce e aici e calcul pur,
/// din dosarele salvate; exportul în PDF și Word e în raport_export.dart.
enum PerioadaRaport { saptamanal, lunar, anual }

const lunileAnului = [
  'ianuarie',
  'februarie',
  'martie',
  'aprilie',
  'mai',
  'iunie',
  'iulie',
  'august',
  'septembrie',
  'octombrie',
  'noiembrie',
  'decembrie',
];

/// Intervalul [inceput, sfarsit) al unei perioade de raportare.
class IntervalRaport {
  final PerioadaRaport perioada;
  final DateTime inceput;

  /// Exclusiv: prima zi de după perioadă.
  final DateTime sfarsit;

  const IntervalRaport._(this.perioada, this.inceput, this.sfarsit);

  /// Perioada care conține ziua [zi]: săptămâna de luni până duminică, luna
  /// calendaristică sau anul.
  factory IntervalRaport.pentru(PerioadaRaport perioada, DateTime zi) {
    final z = DateTime(zi.year, zi.month, zi.day);
    return switch (perioada) {
      PerioadaRaport.saptamanal => () {
        final luni = DateTime(z.year, z.month, z.day - (z.weekday - 1));
        return IntervalRaport._(
          perioada,
          luni,
          DateTime(luni.year, luni.month, luni.day + 7),
        );
      }(),
      PerioadaRaport.lunar => IntervalRaport._(
        perioada,
        DateTime(z.year, z.month),
        DateTime(z.year, z.month + 1),
      ),
      PerioadaRaport.anual => IntervalRaport._(
        perioada,
        DateTime(z.year),
        DateTime(z.year + 1),
      ),
    };
  }

  IntervalRaport get precedent => IntervalRaport.pentru(
    perioada,
    inceput.subtract(const Duration(days: 1)),
  );
  IntervalRaport get urmator => IntervalRaport.pentru(perioada, sfarsit);

  /// Ultima zi inclusă.
  DateTime get ultimaZi =>
      DateTime(sfarsit.year, sfarsit.month, sfarsit.day - 1);

  bool contine(DateTime? d) =>
      d != null && !d.isBefore(inceput) && d.isBefore(sfarsit);

  /// „01.11.2026 – 30.11.2026”.
  String get text => '${formateazaData(inceput)} – ${formateazaData(ultimaZi)}';

  /// Eticheta scurtă din ecran: „9 – 15 nov. 2026”, „Noiembrie 2026”, „Anul 2026”.
  String get eticheta => switch (perioada) {
    PerioadaRaport.saptamanal => text,
    PerioadaRaport.lunar =>
      '${_majuscula(lunileAnului[inceput.month - 1])} ${inceput.year}',
    PerioadaRaport.anual => 'Anul ${inceput.year}',
  };

  /// Pentru titlu: „săptămânal”, „lunar”, „anual”.
  String get adjectiv => switch (perioada) {
    PerioadaRaport.saptamanal => 'săptămânal',
    PerioadaRaport.lunar => 'lunar',
    PerioadaRaport.anual => 'anual',
  };
}

String _majuscula(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

enum TipSolutie { admite, admiteInParte, respinge, amanare, alta }

String _fara(String s) => s
    .toLowerCase()
    .replaceAll('ţ', 'ț')
    .replaceAll('ş', 'ș')
    .replaceAll('ă', 'a')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('ș', 's')
    .replaceAll('ț', 't');

/// Felul soluției, după primul cuvânt al soluției publicate de instanță.
/// „Respinge excepția… Admite acțiunea” contează ca „respinge” doar dacă
/// portalul nu a dat un tip separat; de aceea întâi se citește [Sedinta.solutie].
TipSolutie tipSolutie(Sedinta s) {
  for (final text in [s.solutie, s.solutieSumar]) {
    final t = _fara(text).trim();
    if (t.isEmpty) continue;
    if (RegExp(r'^admi(te|sa|s)\w*\s+in\s+parte').hasMatch(t))
      return TipSolutie.admiteInParte;
    if (RegExp(r'^admi(te|sa|s)').hasMatch(t)) return TipSolutie.admite;
    if (RegExp(r'^respin').hasMatch(t)) return TipSolutie.respinge;
    if (RegExp(r'^(amana|amanare|amanarea)').hasMatch(t))
      return TipSolutie.amanare;
    return TipSolutie.alta;
  }
  return TipSolutie.alta;
}

/// O hotărâre: soluție pe fond (admite, respinge) sau act de dispoziție
/// (sentință, decizie). Amânările și încheierile intermediare nu intră.
bool esteHotarare(Sedinta s) {
  if (!s.arePronuntare) return false;
  final tip = tipSolutie(s);
  if (tip == TipSolutie.amanare) return false;
  if (tip != TipSolutie.alta) return true;
  final doc = _fara(s.document);
  return doc.contains('hotarare') ||
      doc.contains('sentinta') ||
      doc.contains('decizie');
}

/// Un termen de judecată, pentru tabelele raportului.
class RandTermen {
  final Dosar dosar;
  final Sedinta sedinta;
  const RandTermen(this.dosar, this.sedinta);

  DateTime get moment {
    final p = sedinta.ora.split(':');
    return sedinta.data!.add(
      Duration(
        hours: int.tryParse(p.first) ?? 0,
        minutes: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
      ),
    );
  }

  String get dataOra => sedinta.ora.isEmpty
      ? formateazaData(sedinta.data)
      : '${formateazaData(sedinta.data)}, ${sedinta.ora}';

  /// Cel mult trei părți, debitorul întâi la insolvență.
  List<String> get parti => [
    for (final r in rezumatParti(dosar, max: 3).skip(1))
      r.replaceFirst('• ', ''),
  ];

  String get solutie => scurteaza(
    sedinta.solutieSumar.isNotEmpty ? sedinta.solutieSumar : sedinta.solutie,
    220,
  );

  DateTime get dataHotarare => sedinta.dataPronuntare ?? sedinta.data!;

  /// „Hotărâre 388/2026” sau tipul documentului, dacă nu are număr.
  String get document => documentSedinta(sedinta);
}

/// „Hotărâre 388/2026” sau tipul documentului, dacă nu are număr.
String documentSedinta(Sedinta sedinta) {
  final tip = switch (_fara(sedinta.document)) {
    final d when d.contains('hotarare') => 'Hotărâre',
    final d when d.contains('sentinta') => 'Sentință',
    final d when d.contains('decizie') => 'Decizie',
    final d when d.contains('incheiere') => 'Încheiere',
    _ => '',
  };
  if (sedinta.numarDocument.isEmpty) return tip;
  return '${tip.isEmpty ? 'Nr.' : tip} ${sedinta.numarDocument}';
}

class RandCaleAtac {
  final Dosar dosar;
  final CaleAtac cale;
  const RandCaleAtac(this.dosar, this.cale);
}

/// Pe luni sau pe instanțe, pentru raportul anual.
class Repartizare {
  final String eticheta;
  final int dosare;
  final int termene;
  final int hotarari;
  const Repartizare(
    this.eticheta, {
    this.dosare = 0,
    required this.termene,
    required this.hotarari,
  });
}

class Raport {
  final IntervalRaport interval;
  final DateTime intocmitLa;
  final String beneficiar;
  final int dosareMonitorizate;
  final int instante;
  final List<RandTermen> termene;
  final List<RandTermen> hotarari;
  final List<RandCaleAtac> caiAtac;
  final List<RandTermen> urmatoare;
  final List<Repartizare> peLuni;
  final List<Repartizare> peInstante;

  const Raport({
    required this.interval,
    required this.intocmitLa,
    required this.beneficiar,
    required this.dosareMonitorizate,
    required this.instante,
    required this.termene,
    required this.hotarari,
    required this.caiAtac,
    required this.urmatoare,
    required this.peLuni,
    required this.peInstante,
  });

  bool get anual => interval.perioada == PerioadaRaport.anual;

  int _numara(TipSolutie tip) =>
      hotarari.where((h) => tipSolutie(h.sedinta) == tip).length;

  int get amanari =>
      termene.where((t) => tipSolutie(t.sedinta) == TipSolutie.amanare).length;

  /// Tabelul „Sinteză”: (indicator, valoare, subordonat).
  List<(String, String, bool)> get indicatori {
    final alte =
        hotarari.length -
        _numara(TipSolutie.admite) -
        _numara(TipSolutie.admiteInParte) -
        _numara(TipSolutie.respinge);
    return [
      ('Dosare monitorizate la data întocmirii', '$dosareMonitorizate', false),
      (
        'Termene de judecată în perioada de referință',
        '${termene.length}',
        false,
      ),
      ('Termene amânate', '$amanari', false),
      ('Hotărâri pronunțate', '${hotarari.length}', false),
      ('din care: admite', '${_numara(TipSolutie.admite)}', true),
      (
        'din care: admite în parte',
        '${_numara(TipSolutie.admiteInParte)}',
        true,
      ),
      ('din care: respinge', '${_numara(TipSolutie.respinge)}', true),
      if (alte > 0) ('din care: alte soluții', '$alte', true),
      ('Căi de atac declarate', '${caiAtac.length}', false),
      (_eticheteUrmatoare, '${urmatoare.length}', false),
    ];
  }

  String get _eticheteUrmatoare => switch (interval.perioada) {
    PerioadaRaport.saptamanal => 'Termene stabilite în săptămâna următoare',
    PerioadaRaport.lunar => 'Termene stabilite în luna următoare',
    PerioadaRaport.anual =>
      'Termene stabilite în primele 30 de zile ale anului următor',
  };

  /// Fraza de început a sintezei, în limbajul raportului.
  String get introducere {
    final d = dosareMonitorizate == 1
        ? 'un dosar'
        : numarCu(dosareMonitorizate, 'dosare');
    final i = instante == 1
        ? 'unei singure instanțe'
        : 'a ${numarCu(instante, 'instanțe')}';
    return 'În perioada de referință au fost monitorizate $d, aflate pe rolul $i. '
        'Situația se prezintă după cum urmează:';
  }
}

/// „3 dosare”, „42 de dosare”, „101 dosare”: după 20 (și la sute rotunde)
/// româna cere „de”.
String numarCu(int n, String plural) {
  final rest = n % 100;
  final de = n >= 20 && (rest == 0 || rest >= 20);
  return '$n ${de ? 'de ' : ''}$plural';
}

/// Construiește raportul pentru [interval] din dosarele salvate.
Raport construiesteRaport(
  List<DosarSalvat> salvate,
  IntervalRaport interval, {
  String beneficiar = '',
  DateTime? acum,
}) {
  final dosare = [for (final s in salvate) s.dosar];
  final termene = <RandTermen>[];
  final hotarari = <RandTermen>[];
  final urmatoare = <RandTermen>[];
  final caiAtac = <RandCaleAtac>[];

  final finalUrmatoare = switch (interval.perioada) {
    PerioadaRaport.anual => interval.sfarsit.add(const Duration(days: 30)),
    _ => interval.urmator.sfarsit,
  };

  for (final d in dosare) {
    for (final s in d.sedinte) {
      if (s.data == null) continue;
      if (interval.contine(s.data)) termene.add(RandTermen(d, s));
      if (!s.data!.isBefore(interval.sfarsit) &&
          s.data!.isBefore(finalUrmatoare)) {
        urmatoare.add(RandTermen(d, s));
      }
      if (esteHotarare(s) && interval.contine(s.dataPronuntare ?? s.data)) {
        hotarari.add(RandTermen(d, s));
      }
    }
    for (final c in d.caiAtac) {
      if (interval.contine(c.dataDeclarare)) caiAtac.add(RandCaleAtac(d, c));
    }
  }
  termene.sort((a, b) => a.moment.compareTo(b.moment));
  urmatoare.sort((a, b) => a.moment.compareTo(b.moment));
  hotarari.sort((a, b) => a.dataHotarare.compareTo(b.dataHotarare));
  caiAtac.sort(
    (a, b) => a.cale.dataDeclarare!.compareTo(b.cale.dataDeclarare!),
  );

  final peLuni = <Repartizare>[];
  final peInstante = <Repartizare>[];
  if (interval.perioada == PerioadaRaport.anual) {
    for (var m = 1; m <= 12; m++) {
      peLuni.add(
        Repartizare(
          _majuscula(lunileAnului[m - 1]),
          termene: termene.where((t) => t.sedinta.data!.month == m).length,
          hotarari: hotarari.where((h) => h.dataHotarare.month == m).length,
        ),
      );
    }
    final instante = {for (final d in dosare) d.instanta}.toList()..sort();
    for (final i in instante) {
      peInstante.add(
        Repartizare(
          i,
          dosare: dosare.where((d) => d.instanta == i).length,
          termene: termene.where((t) => t.dosar.instanta == i).length,
          hotarari: hotarari.where((h) => h.dosar.instanta == i).length,
        ),
      );
    }
    peInstante.sort((a, b) => b.dosare.compareTo(a.dosare));
  }

  return Raport(
    interval: interval,
    intocmitLa: acum ?? DateTime.now(),
    beneficiar: beneficiar.trim(),
    dosareMonitorizate: dosare.length,
    instante: {for (final d in dosare) d.institutie}.length,
    termene: termene,
    hotarari: hotarari,
    caiAtac: caiAtac,
    urmatoare: urmatoare,
    peLuni: peLuni,
    peInstante: peInstante,
  );
}

/// Textele fixe de la finalul raportului.
const mentiuniRaport = [
  'Prezentul raport are caracter informativ și a fost întocmit automat, pe baza informațiilor '
      'publicate pe portalul instanțelor de judecată (portal.just.ro) și pe site-ul Înaltei Curți '
      'de Casație și Justiție, disponibile la data întocmirii.',
  'Informațiile cuprinse în raport nu țin loc de comunicare a actelor de procedură și nu substituie '
      'consultarea dosarului la instanță. Pentru calculul termenelor procedurale se vor avea în '
      'vedere actele comunicate potrivit legii.',
  'Soluțiile sunt redate în forma publicată de instanță; formulările pe scurt rezumă dispozitivul și '
      'nu reproduc integral minuta.',
];

/// Numele fișierului: „Raport lunar 2026-11.pdf”.
String numeFisierRaport(Raport r, String extensie) {
  final i = r.interval.inceput;
  String d(int n) => n.toString().padLeft(2, '0');
  final perioada = switch (r.interval.perioada) {
    PerioadaRaport.saptamanal => '${i.year}-${d(i.month)}-${d(i.day)}',
    PerioadaRaport.lunar => '${i.year}-${d(i.month)}',
    PerioadaRaport.anual => '${i.year}',
  };
  return 'Raport ${r.interval.adjectiv} $perioada.$extensie';
}
