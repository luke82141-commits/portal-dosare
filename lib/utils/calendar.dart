import 'package:flutter/material.dart';

import '../models/dosar_model.dart';

const lunileAnului = [
  'Ianuarie', 'Februarie', 'Martie', 'Aprilie', 'Mai', 'Iunie',
  'Iulie', 'August', 'Septembrie', 'Octombrie', 'Noiembrie', 'Decembrie',
];

const zileleSaptamanii = ['Luni', 'Marți', 'Miercuri', 'Joi', 'Vineri', 'Sâmbătă', 'Duminică'];

/// Un termen (o ședință) al unui dosar, așezat în calendar.
class Termen {
  final Dosar dosar;
  final Sedinta sedinta;

  /// Ziua ședinței, fără oră.
  final DateTime zi;

  /// Minutul din zi la care începe (ex. 09:30 → 570), sau null dacă portalul
  /// nu a dat ora.
  final int? minut;

  final Color culoare;

  const Termen({
    required this.dosar,
    required this.sedinta,
    required this.zi,
    required this.minut,
    required this.culoare,
  });

  String get ora => sedinta.ora;

  /// Ședința a avut deja loc și are soluție.
  bool get trecut => sedinta.arePronuntare;
}

/// „09:00”, „9:00” sau „09.00” → minutul din zi.
int? minutDinOra(String ora) {
  final m = RegExp(r'^\s*(\d{1,2})[:.](\d{2})').firstMatch(ora);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// Toate ședințele dosarelor, grupate pe zile și ordonate după oră.
/// [culoare] dă culoarea fiecărui dosar (aleasă sau automată).
Map<DateTime, List<Termen>> termenePeZile(
  List<Dosar> dosare, {
  Color Function(Dosar)? culoare,
}) {
  final rezultat = <DateTime, List<Termen>>{};
  for (final d in dosare) {
    final c = culoare?.call(d) ?? const Color(0xFF1F3A93);
    for (final s in d.sedinte) {
      if (s.data == null) continue;
      final zi = DateUtils.dateOnly(s.data!);
      (rezultat[zi] ??= []).add(Termen(
        dosar: d,
        sedinta: s,
        zi: zi,
        minut: minutDinOra(s.ora),
        culoare: c,
      ));
    }
  }
  for (final l in rezultat.values) {
    l.sort((a, b) => (a.minut ?? -1).compareTo(b.minut ?? -1));
  }
  return rezultat;
}

/// Lunea săptămânii din care face parte [d].
DateTime inceputSaptamana(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Cele 6 × 7 zile afișate în grila lunii (de luni până duminică).
List<DateTime> zileGrilaLuna(DateTime luna) {
  final start = inceputSaptamana(DateTime(luna.year, luna.month));
  return [for (var i = 0; i < 42; i++) DateTime(start.year, start.month, start.day + i)];
}

/// Coloanele pentru termenele care se suprapun în aceeași zi (durată
/// presupusă: o oră), ca în Google Calendar: întoarce, pentru fiecare termen,
/// (coloana, numărul de coloane din grupul lui).
List<(int, int)> coloaneSuprapuse(List<Termen> termene, {int durata = 60}) {
  final rezultat = List<(int, int)>.filled(termene.length, (0, 1));
  var grup = <int>[];
  var sfarsitGrup = -1;
  final sfarsitColoane = <int>[];

  void inchideGrup() {
    final n = sfarsitColoane.length;
    for (final i in grup) {
      rezultat[i] = (rezultat[i].$1, n);
    }
    grup = [];
    sfarsitColoane.clear();
  }

  for (var i = 0; i < termene.length; i++) {
    final start = termene[i].minut;
    if (start == null) continue;
    if (start >= sfarsitGrup) inchideGrup();
    var col = sfarsitColoane.indexWhere((s) => s <= start);
    if (col == -1) {
      col = sfarsitColoane.length;
      sfarsitColoane.add(start + durata);
    } else {
      sfarsitColoane[col] = start + durata;
    }
    rezultat[i] = (col, 1);
    grup.add(i);
    if (start + durata > sfarsitGrup) sfarsitGrup = start + durata;
  }
  inchideGrup();
  return rezultat;
}
