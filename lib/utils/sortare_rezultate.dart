import '../models/dosar_model.dart';

/// Ordinea rezultatelor unei căutări.
enum SortareRezultate {
  portal('Ordinea portalului'),
  modificateRecent('Modificate recent'),
  celeMaiNoi('Data dosarului: cele mai noi'),
  celeMaiVechi('Data dosarului: cele mai vechi');

  final String eticheta;
  const SortareRezultate(this.eticheta);
}

/// Anii de înregistrare prezenți în rezultate, de la cel mai recent.
List<int> aniRezultate(List<Dosar> dosare) => {
  for (final d in dosare)
    if (d.data != null) d.data!.year,
}.toList()..sort((a, b) => b.compareTo(a));

/// Filtrează după anul înregistrării ([an] null = toți) și ordonează. Dosarele
/// fără dată ajung la sfârșit, oricare ar fi ordinea.
List<Dosar> ordoneazaRezultate(List<Dosar> dosare, SortareRezultate sortare, {int? an}) {
  final l = [
    for (final d in dosare)
      if (an == null || d.data?.year == an) d,
  ];
  int dupa(DateTime? a, DateTime? b, {bool desc = true}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  switch (sortare) {
    case SortareRezultate.portal:
      break;
    case SortareRezultate.modificateRecent:
      _sorteazaStabil(l, (a, b) => dupa(a.dataModificare ?? a.data, b.dataModificare ?? b.data));
    case SortareRezultate.celeMaiNoi:
      _sorteazaStabil(l, (a, b) => dupa(a.data, b.data));
    case SortareRezultate.celeMaiVechi:
      _sorteazaStabil(l, (a, b) => dupa(a.data, b.data, desc: false));
  }
  return l;
}

/// Sortare stabilă: la egalitate păstrează ordinea portalului.
void _sorteazaStabil<T>(List<T> l, int Function(T, T) cmp) {
  final indexat = [for (var i = 0; i < l.length; i++) (i, l[i])];
  indexat.sort((a, b) {
    final c = cmp(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < l.length; i++) {
    l[i] = indexat[i].$2;
  }
}
