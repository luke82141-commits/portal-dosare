import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';

/// Compară două versiuni ale aceluiași dosar și descrie, în cuvinte, ce s-a
/// schimbat pe portal. Lista goală înseamnă că nu există schimbări vizibile.
List<String> comparaDosare(Dosar vechi, Dosar nou) {
  final schimbari = <String>[];

  void camp(String eticheta, String a, String b) {
    if (a == b) return;
    schimbari.add('$eticheta: ${a.isEmpty ? '—' : a} → ${b.isEmpty ? '—' : b}');
  }

  // Ședințele sunt cele mai importante, deci apar primele.
  schimbari.addAll(_comparaSedinte(vechi.sedinte, nou.sedinte));

  camp('Stadiu procesual', vechi.stadiuProcesual, nou.stadiuProcesual);
  camp('Secție', vechi.sectie, nou.sectie);
  camp('Obiect', vechi.obiect, nou.obiect);
  camp('Categorie', vechi.categorie, nou.categorie);

  String cheieCale(CaleAtac c) =>
      '${c.tip}|${c.parteDeclaratoare}|${c.dataDeclarare?.toIso8601String()}';
  final caiVechi = vechi.caiAtac.map(cheieCale).toSet();
  for (final c in nou.caiAtac) {
    if (caiVechi.contains(cheieCale(c))) continue;
    final detalii = [
      if (c.parteDeclaratoare.isNotEmpty) c.parteDeclaratoare,
      if (c.dataDeclarare != null) formateazaData(c.dataDeclarare),
    ].join(', ');
    schimbari.add('Cale de atac declarată: ${c.tip.isEmpty ? '—' : c.tip}'
        '${detalii.isEmpty ? '' : ' ($detalii)'}');
  }

  String cheieParte(Parte p) => '${p.nume}|${p.calitate}';
  String descriere(Parte p) =>
      p.calitate.isEmpty ? p.nume : '${p.nume} (${p.calitate})';
  final partiVechi = vechi.parti.map(cheieParte).toSet();
  final partiNoi = nou.parti.map(cheieParte).toSet();
  for (final p in nou.parti) {
    if (!partiVechi.contains(cheieParte(p))) {
      schimbari.add('Parte nouă: ${descriere(p)}');
    }
  }
  for (final p in vechi.parti) {
    if (!partiNoi.contains(cheieParte(p))) {
      schimbari.add('Parte eliminată: ${descriere(p)}');
    }
  }

  return schimbari;
}

List<String> _comparaSedinte(List<Sedinta> vechi, List<Sedinta> noi) {
  final schimbari = <String>[];

  // Ședințele se potrivesc după dată; dacă sunt mai multe în aceeași zi, în
  // ordinea în care apar.
  Map<String, List<Sedinta>> grupeaza(List<Sedinta> l) {
    final m = <String, List<Sedinta>>{};
    for (final s in l) {
      m.putIfAbsent(s.data?.toIso8601String() ?? '', () => []).add(s);
    }
    return m;
  }

  final gVechi = grupeaza(vechi);
  final gNoi = grupeaza(noi);

  for (final entry in gNoi.entries) {
    final perechi = gVechi[entry.key] ?? const <Sedinta>[];
    for (var i = 0; i < entry.value.length; i++) {
      final n = entry.value[i];
      final ziua = n.data == null ? 'fără dată' : formateazaData(n.data);

      if (i >= perechi.length) {
        if (n.arePronuntare) {
          schimbari.add('Ședință nouă din $ziua: ${_solutie(n)}');
        } else {
          final detalii = [
            if (n.ora.isNotEmpty) 'ora ${n.ora}',
            if (n.complet.isNotEmpty) 'complet ${n.complet}',
          ].join(', ');
          schimbari.add('Termen nou: $ziua${detalii.isEmpty ? '' : ', $detalii'}');
        }
        continue;
      }

      final v = perechi[i];
      if (v.solutie != n.solutie || v.solutieSumar != n.solutieSumar) {
        if (!n.arePronuntare) {
          schimbari.add('Soluția de la termenul din $ziua a fost retrasă de pe portal');
        } else if (!v.arePronuntare) {
          schimbari.add('Pronunțare la termenul din $ziua: ${_solutie(n)}');
        } else {
          schimbari.add('Soluție modificată la termenul din $ziua: ${_solutie(n)}');
        }
      }
      if (v.ora != n.ora) {
        schimbari.add('Ora termenului din $ziua: '
            '${v.ora.isEmpty ? '—' : v.ora} → ${n.ora.isEmpty ? '—' : n.ora}');
      }
      if (v.complet != n.complet) {
        schimbari.add('Complet schimbat la termenul din $ziua: '
            '${v.complet.isEmpty ? '—' : v.complet} → ${n.complet.isEmpty ? '—' : n.complet}');
      }
      if ((v.document != n.document || v.numarDocument != n.numarDocument) &&
          n.document.isNotEmpty) {
        schimbari.add('Document la termenul din $ziua: ${numeDocument(n.document)}'
            '${n.numarDocument.isEmpty ? '' : ' nr. ${n.numarDocument}'}');
      }
    }
  }

  for (final entry in gVechi.entries) {
    final ramase = gNoi[entry.key]?.length ?? 0;
    for (final v in entry.value.skip(ramase)) {
      final ziua = v.data == null ? 'fără dată' : formateazaData(v.data);
      schimbari.add('Termenul din $ziua nu mai apare pe portal');
    }
  }

  return schimbari;
}

String _solutie(Sedinta s) {
  final sumar = scurteaza(s.solutieSumar, 220);
  if (s.solutie.isEmpty) return sumar;
  if (sumar.isEmpty || sumar == s.solutie) return s.solutie;
  return '${s.solutie} — $sumar';
}
