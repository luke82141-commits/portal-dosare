import '../models/dosar_model.dart';
import 'raport_service.dart';

/// Statisticile Pro pe un an, comparate cu anul dinainte. Calcul pur, din
/// dosarele urmărite.
class Statistici {
  final int an;

  /// Dosare înregistrate (după data înregistrării) pe luni, ian.–dec.
  final List<int> dosareInregistrate;
  final List<int> dosareInregistrateAnTrecut;

  /// Termene de judecată pe luni.
  final List<int> termene;
  final List<int> termeneAnTrecut;

  final int amanari;
  final int amanariAnTrecut;

  /// Hotărâri pe felul soluției.
  final Map<TipSolutie, int> solutii;

  /// Hotărâri pe stadiul procesual (Fond, Apel, Recurs…), fiecare cu
  /// împărțirea pe felul soluției.
  final Map<String, Map<TipSolutie, int>> solutiiPeFaze;

  /// Instanțele cu cele mai multe termene în an.
  final List<(String, int)> instante;

  const Statistici({
    required this.an,
    required this.dosareInregistrate,
    required this.dosareInregistrateAnTrecut,
    required this.termene,
    required this.termeneAnTrecut,
    required this.amanari,
    required this.amanariAnTrecut,
    required this.solutii,
    required this.solutiiPeFaze,
    required this.instante,
  });

  int get totalDosare => dosareInregistrate.fold(0, (a, b) => a + b);
  int get totalDosareAnTrecut => dosareInregistrateAnTrecut.fold(0, (a, b) => a + b);
  int get totalTermene => termene.fold(0, (a, b) => a + b);
  int get totalTermeneAnTrecut => termeneAnTrecut.fold(0, (a, b) => a + b);
  int get totalHotarari => solutii.values.fold(0, (a, b) => a + b);

  bool get gol => totalDosare == 0 && totalTermene == 0 && totalHotarari == 0;
}

/// Ordinea în care apar felurile soluțiilor în grafice și legende.
const ordineSolutii = [
  TipSolutie.admite,
  TipSolutie.admiteInParte,
  TipSolutie.respinge,
  TipSolutie.alta,
];

String numeSolutie(TipSolutie t) => switch (t) {
  TipSolutie.admite => 'Admite',
  TipSolutie.admiteInParte => 'Admite în parte',
  TipSolutie.respinge => 'Respinge',
  TipSolutie.amanare => 'Amânare',
  TipSolutie.alta => 'Alte soluții',
};

/// „+25% față de 2025”, „−10% față de 2025”; gol dacă anul trecut e 0.
String variatie(int acum, int inainte, int anTrecut) {
  if (inainte == 0) return '';
  final p = ((acum - inainte) * 100 / inainte).round();
  if (p == 0) return 'la fel ca în $anTrecut';
  return '${p > 0 ? '+' : '−'}${p.abs()}% față de $anTrecut';
}

Statistici calculeazaStatistici(List<DosarSalvat> salvate, int an) {
  final dosare = [for (final s in salvate) s.dosar];
  List<int> luni() => List.filled(12, 0);

  final inregistrate = luni(), inregistrateTrecut = luni();
  final termene = luni(), termeneTrecut = luni();
  var amanari = 0, amanariTrecut = 0;
  final solutii = {for (final t in ordineSolutii) t: 0};
  final peFaze = <String, Map<TipSolutie, int>>{};
  final peInstante = <String, int>{};

  for (final d in dosare) {
    if (d.data?.year == an) inregistrate[d.data!.month - 1]++;
    if (d.data?.year == an - 1) inregistrateTrecut[d.data!.month - 1]++;

    for (final s in d.sedinte) {
      final zi = s.data;
      if (zi == null) continue;
      final amanare = tipSolutie(s) == TipSolutie.amanare;
      if (zi.year == an) {
        termene[zi.month - 1]++;
        peInstante[d.instanta] = (peInstante[d.instanta] ?? 0) + 1;
        if (amanare) amanari++;
      } else if (zi.year == an - 1) {
        termeneTrecut[zi.month - 1]++;
        if (amanare) amanariTrecut++;
      }

      if (esteHotarare(s) && (s.dataPronuntare ?? zi).year == an) {
        final tip = tipSolutie(s);
        solutii[tip] = (solutii[tip] ?? 0) + 1;
        final faza = d.stadiuProcesual.isEmpty ? 'Nespecificat' : d.stadiuProcesual;
        final f = peFaze.putIfAbsent(faza, () => {for (final t in ordineSolutii) t: 0});
        f[tip] = (f[tip] ?? 0) + 1;
      }
    }
  }

  final instante = [for (final e in peInstante.entries) (e.key, e.value)]
    ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));

  return Statistici(
    an: an,
    dosareInregistrate: inregistrate,
    dosareInregistrateAnTrecut: inregistrateTrecut,
    termene: termene,
    termeneAnTrecut: termeneTrecut,
    amanari: amanari,
    amanariAnTrecut: amanariTrecut,
    solutii: solutii,
    solutiiPeFaze: peFaze,
    instante: instante.take(5).toList(),
  );
}
