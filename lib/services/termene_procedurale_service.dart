import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unitatea în care e exprimat un termen procedural.
enum UnitateTermen { zile, luni, ani }

/// Un act cu termenul lui legal, ales din listă în calculator.
class ActProcedural {
  final String nume;
  final int durata;
  final UnitateTermen unitate;

  /// De la ce curge termenul, așa cum îl spune legea.
  final String deLa;

  /// Temeiul legal, afișat sub rezultat.
  final String temei;

  const ActProcedural(
    this.nume,
    this.durata,
    this.unitate, {
    required this.deLa,
    required this.temei,
  });
}

/// Termenele uzuale. Durata se poate schimba în calculator, pentru cazurile
/// în care o lege specială prevede altceva.
const actePrecompletate = <ActProcedural>[
  ActProcedural(
    'Apel (civil)',
    30,
    UnitateTermen.zile,
    deLa: 'comunicarea hotărârii',
    temei: 'art. 468 alin. (1) CPC',
  ),
  ActProcedural(
    'Recurs (civil)',
    30,
    UnitateTermen.zile,
    deLa: 'comunicarea hotărârii',
    temei: 'art. 485 alin. (1) CPC',
  ),
  ActProcedural(
    'Întâmpinare',
    25,
    UnitateTermen.zile,
    deLa: 'comunicarea cererii de chemare în judecată',
    temei: 'art. 201 alin. (1) CPC',
  ),
  ActProcedural(
    'Răspuns la întâmpinare',
    10,
    UnitateTermen.zile,
    deLa: 'comunicarea întâmpinării',
    temei: 'art. 201 alin. (2) CPC',
  ),
  ActProcedural(
    'Contestație în anulare',
    15,
    UnitateTermen.zile,
    deLa: 'comunicarea hotărârii',
    temei: 'art. 506 alin. (1) CPC',
  ),
  ActProcedural(
    'Revizuire',
    1,
    UnitateTermen.luni,
    deLa: 'data prevăzută la art. 511 CPC (de regulă comunicarea)',
    temei: 'art. 511 alin. (1) CPC',
  ),
  ActProcedural(
    'Contestație la executare',
    15,
    UnitateTermen.zile,
    deLa: 'data prevăzută la art. 715 CPC',
    temei: 'art. 715 alin. (1) CPC',
  ),
  ActProcedural(
    'Cerere în anulare (ordonanță de plată)',
    10,
    UnitateTermen.zile,
    deLa: 'comunicarea ordonanței',
    temei: 'art. 1023 alin. (1) CPC',
  ),
  ActProcedural(
    'Apel (cerere de valoare redusă)',
    30,
    UnitateTermen.zile,
    deLa: 'comunicarea hotărârii',
    temei: 'art. 1033 alin. (1) CPC',
  ),
  ActProcedural(
    'Reexaminare taxă de timbru',
    3,
    UnitateTermen.zile,
    deLa: 'comunicarea încheierii',
    temei: 'art. 39 alin. (1) OUG nr. 80/2013',
  ),
  ActProcedural(
    'Plângere contravențională',
    15,
    UnitateTermen.zile,
    deLa: 'comunicarea procesului-verbal',
    temei: 'art. 31 alin. (1) OG nr. 2/2001',
  ),
  ActProcedural(
    'Recurs (contencios administrativ)',
    15,
    UnitateTermen.zile,
    deLa: 'comunicarea hotărârii',
    temei: 'art. 20 alin. (1) Legea nr. 554/2004',
  ),
  ActProcedural(
    'Apel (penal)',
    10,
    UnitateTermen.zile,
    deLa: 'comunicarea copiei minutei',
    temei: 'art. 410 alin. (1) CPP',
  ),
];

/// Data Paștelui ortodox (calendarul iulian, convertit la cel gregorian;
/// diferența de 13 zile e valabilă între 1900 și 2099).
DateTime pasteOrtodox(int an) {
  final a = an % 4, b = an % 7, c = an % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final luna = (d + e + 114) ~/ 31;
  final zi = (d + e + 114) % 31 + 1;
  return DateTime(an, luna, zi).add(const Duration(days: 13));
}

/// Sărbătorile legale din România (art. 139 Codul muncii), într-un an.
Map<DateTime, String> sarbatoriLegale(int an) {
  final paste = pasteOrtodox(an);
  DateTime fata(int zile) =>
      DateTime(paste.year, paste.month, paste.day + zile);
  return {
    DateTime(an, 1, 1): 'Anul Nou',
    DateTime(an, 1, 2): 'Anul Nou',
    DateTime(an, 1, 6): 'Boboteaza',
    DateTime(an, 1, 7): 'Sfântul Ioan',
    DateTime(an, 1, 24): 'Ziua Unirii Principatelor',
    fata(-2): 'Vinerea Mare',
    paste: 'Paștele',
    fata(1): 'a doua zi de Paște',
    DateTime(an, 5, 1): 'Ziua Muncii',
    DateTime(an, 6, 1): 'Ziua Copilului',
    fata(49): 'Rusaliile',
    fata(50): 'a doua zi de Rusalii',
    DateTime(an, 8, 15): 'Adormirea Maicii Domnului',
    DateTime(an, 11, 30): 'Sfântul Andrei',
    DateTime(an, 12, 1): 'Ziua Națională',
    DateTime(an, 12, 25): 'Crăciunul',
    DateTime(an, 12, 26): 'a doua zi de Crăciun',
  };
}

/// De ce o zi nu e lucrătoare („sâmbătă”, „Crăciunul”), sau null dacă e.
String? motivZiNelucratoare(DateTime zi) {
  final z = DateTime(zi.year, zi.month, zi.day);
  final sarbatoare = sarbatoriLegale(z.year)[z];
  if (sarbatoare != null) return sarbatoare;
  if (z.weekday == DateTime.saturday) return 'sâmbătă';
  if (z.weekday == DateTime.sunday) return 'duminică';
  return null;
}

/// Rezultatul calculului: ultima zi în care actul poate fi făcut.
class CalculTermen {
  /// Ziua în care se împlinește termenul, după regula de calcul.
  final DateTime implinire;

  /// Ultima zi utilă, după prelungirea peste zilele nelucrătoare.
  final DateTime ultimaZi;

  /// Zilele nelucrătoare peste care s-a prelungit, cu motivul lor.
  final List<(DateTime, String)> prelungiri;

  const CalculTermen(this.implinire, this.ultimaZi, this.prelungiri);
}

/// Calculează termenul după art. 181 CPC (aceeași regulă la art. 269 CPP):
/// - pe zile, termenul e pe zile libere: nu se socotește nici ziua în care
///   începe să curgă, nici cea în care se împlinește, deci actul se poate
///   face până în ziua de după cele [durata] zile întregi;
/// - pe luni și ani, se împlinește în ziua corespunzătoare, iar dacă luna nu
///   are o asemenea zi, în ultima zi a lunii;
/// - dacă ultima zi e nelucrătoare, termenul se prelungește până la sfârșitul
///   primei zile lucrătoare următoare.
CalculTermen calculeazaTermen(
  DateTime start,
  int durata,
  UnitateTermen unitate,
) {
  final s = DateTime(start.year, start.month, start.day);
  DateTime peLuni(int luni) {
    final tinta = DateTime(s.year, s.month + luni, 1);
    final ultimaZiLuna = DateTime(tinta.year, tinta.month + 1, 0).day;
    return DateTime(
      tinta.year,
      tinta.month,
      s.day > ultimaZiLuna ? ultimaZiLuna : s.day,
    );
  }

  final implinire = switch (unitate) {
    UnitateTermen.zile => DateTime(s.year, s.month, s.day + durata + 1),
    UnitateTermen.luni => peLuni(durata),
    UnitateTermen.ani => peLuni(12 * durata),
  };
  var zi = implinire;
  final prelungiri = <(DateTime, String)>[];
  for (
    var motiv = motivZiNelucratoare(zi);
    motiv != null;
    motiv = motivZiNelucratoare(zi)
  ) {
    prelungiri.add((zi, motiv));
    zi = DateTime(zi.year, zi.month, zi.day + 1);
  }
  return CalculTermen(implinire, zi, prelungiri);
}

/// Un termen calculat și păstrat, ca să apară în rezumatul zilnic.
class TermenSalvat {
  final String id;
  final String act;
  final String numarDosar;
  final DateTime start;
  final DateTime ultimaZi;

  const TermenSalvat({
    required this.id,
    required this.act,
    required this.numarDosar,
    required this.start,
    required this.ultimaZi,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'act': act,
    'dosar': numarDosar,
    'start': start.toIso8601String(),
    'ultimaZi': ultimaZi.toIso8601String(),
  };

  factory TermenSalvat.fromJson(Map<String, dynamic> j) => TermenSalvat(
    id: j['id'] as String,
    act: j['act'] as String,
    numarDosar: (j['dosar'] as String?) ?? '',
    start: DateTime.parse(j['start'] as String),
    ultimaZi: DateTime.parse(j['ultimaZi'] as String),
  );
}

/// Termenele procedurale păstrate de utilizator.
class TermeneProceduraleService extends ChangeNotifier {
  TermeneProceduraleService._();
  static final TermeneProceduraleService instance =
      TermeneProceduraleService._();

  static const _cheie = 'termene_procedurale_v1';

  List<TermenSalvat> _termene = [];

  /// Cele mai apropiate întâi.
  List<TermenSalvat> get termene => List.unmodifiable(_termene);

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      final brut = prefs.getString(_cheie);
      _termene = brut == null
          ? []
          : [
              for (final j in jsonDecode(brut) as List)
                TermenSalvat.fromJson(j),
            ];
    } catch (e) {
      debugPrint('Termenele procedurale nu au putut fi citite: $e');
      _termene = [];
    }
    _sorteaza();
    notifyListeners();
  }

  void _sorteaza() => _termene.sort((a, b) => a.ultimaZi.compareTo(b.ultimaZi));

  Future<void> _salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cheie,
      jsonEncode([for (final t in _termene) t.toJson()]),
    );
    notifyListeners();
  }

  Future<void> adauga(TermenSalvat t) async {
    await incarca();
    _termene.add(t);
    _sorteaza();
    await _salveaza();
  }

  Future<void> sterge(String id) async {
    await incarca();
    _termene.removeWhere((t) => t.id == id);
    await _salveaza();
  }

  /// Termenele a căror ultimă zi e între azi și peste [zile] zile.
  List<TermenSalvat> apropiate(DateTime acum, {int zile = 7}) {
    final azi = DateTime(acum.year, acum.month, acum.day);
    return [
      for (final t in _termene)
        if (!t.ultimaZi.isBefore(azi) &&
            t.ultimaZi.difference(azi).inDays <= zile)
          t,
    ];
  }
}
