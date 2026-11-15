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

/// O intrare din lista de schimbări a unui termen. Toate schimbările găsite
/// la aceeași verificare pentru același termen ajung într-o singură intrare,
/// ca utilizatorul să primească o notificare, nu câte una pentru fiecare câmp.
class _IntrareTermen {
  final DateTime? data;
  String text;

  /// True dacă intrarea anunță o soluție pronunțată (nouă sau modificată).
  final bool pronuntare;

  /// True dacă intrarea anunță doar un termen nou, fără soluție.
  final bool termenNou;

  _IntrareTermen(this.data, this.text, {this.pronuntare = false, this.termenNou = false});
}

List<String> _comparaSedinte(List<Sedinta> vechi, List<Sedinta> noi) {
  final intrari = <_IntrareTermen>[];

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

  String detaliiTermen(Sedinta n) => [
        if (n.ora.isNotEmpty) 'ora ${n.ora}',
        if (n.complet.isNotEmpty) 'complet ${n.complet}',
      ].join(', ');

  for (final entry in gNoi.entries) {
    final perechi = gVechi[entry.key] ?? const <Sedinta>[];
    for (var i = 0; i < entry.value.length; i++) {
      final n = entry.value[i];
      final ziua = n.data == null ? 'fără dată' : formateazaData(n.data);

      if (i >= perechi.length) {
        if (n.arePronuntare) {
          final document = n.document.isEmpty
              ? ''
              : ' · ${numeDocument(n.document)}'
                  '${n.numarDocument.isEmpty ? '' : ' nr. ${n.numarDocument}'}';
          intrari.add(_IntrareTermen(n.data, 'Ședință nouă din $ziua: ${_solutie(n)}$document',
              pronuntare: true));
        } else {
          final detalii = detaliiTermen(n);
          intrari.add(_IntrareTermen(
              n.data, 'Termen nou: $ziua${detalii.isEmpty ? '' : ', $detalii'}',
              termenNou: true));
        }
        continue;
      }

      // Fiecare schimbare are o formă lungă (când e singura la acest termen)
      // și una scurtă (când se adună cu altele în aceeași intrare).
      final lungi = <String>[];
      final scurte = <String>[];
      var pronuntare = false;

      final v = perechi[i];
      if (v.solutie != n.solutie || v.solutieSumar != n.solutieSumar) {
        if (!n.arePronuntare) {
          lungi.add('Soluția de la termenul din $ziua a fost retrasă de pe portal');
          scurte.add('soluția a fost retrasă de pe portal');
        } else if (!v.arePronuntare) {
          lungi.add('Pronunțare la termenul din $ziua: ${_solutie(n)}');
          scurte.add(_solutie(n));
          pronuntare = true;
        } else {
          lungi.add('Soluție modificată la termenul din $ziua: ${_solutie(n)}');
          scurte.add('soluție modificată: ${_solutie(n)}');
          pronuntare = true;
        }
      }
      if (v.ora != n.ora) {
        final schimbare = '${v.ora.isEmpty ? '—' : v.ora} → ${n.ora.isEmpty ? '—' : n.ora}';
        lungi.add('Ora termenului din $ziua: $schimbare');
        scurte.add('ora $schimbare');
      }
      if (v.complet != n.complet) {
        final schimbare =
            '${v.complet.isEmpty ? '—' : v.complet} → ${n.complet.isEmpty ? '—' : n.complet}';
        lungi.add('Complet schimbat la termenul din $ziua: $schimbare');
        scurte.add('complet $schimbare');
      }
      if ((v.document != n.document || v.numarDocument != n.numarDocument) &&
          n.document.isNotEmpty) {
        final document = '${numeDocument(n.document)}'
            '${n.numarDocument.isEmpty ? '' : ' nr. ${n.numarDocument}'}';
        lungi.add('Document la termenul din $ziua: $document');
        scurte.add(document);
      }

      if (lungi.isEmpty) continue;
      intrari.add(_IntrareTermen(
        n.data,
        lungi.length == 1 ? lungi.single : 'Termenul din $ziua: ${scurte.join(' · ')}',
        pronuntare: pronuntare,
      ));
    }
  }

  // O amânare aduce de obicei și termenul următor: îl punem în aceeași
  // intrare cu soluția, nu separat.
  final pronuntari = intrari.where((e) => e.pronuntare && e.data != null).toList()
    ..sort((a, b) => a.data!.compareTo(b.data!));
  if (pronuntari.isNotEmpty) {
    final ultima = pronuntari.last;
    final urmatoare = intrari
        .where((e) => e.termenNou && e.data != null && e.data!.isAfter(ultima.data!))
        .toList()
      ..sort((a, b) => a.data!.compareTo(b.data!));
    if (urmatoare.isNotEmpty) {
      final termen = urmatoare.first;
      ultima.text = '${ultima.text} → ${termen.text.replaceFirst('Termen nou: ', 'termen nou: ')}';
      intrari.remove(termen);
    }
  }

  final schimbari = [for (final e in intrari) e.text];

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
