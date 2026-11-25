import '../services/legislatie_service.dart';
import 'analiza_document.dart';

/// Rezultatul căutării unui act din [AnalizaDocument] în Legislație.
class PrevedereGasita {
  final ActDeCautat cautare;

  /// Actele găsite (unul la trimiterile exacte, câteva la termeni).
  final List<ActNormativ> acte;

  /// Mesajul de eroare, dacă serviciul n-a răspuns.
  final String? eroare;

  const PrevedereGasita(this.cautare, this.acte, {this.eroare});

  bool get gasita => acte.isNotEmpty;
}

/// Câte acte arătăm pentru un termen căutat în titluri.
const acteDinTermen = 2;

/// Caută pe rând fiecare act din analiză. Rezultatele vin unul câte unul
/// (serviciul cere ≥1 s între cereri, iar codurile au mulți MB), ca ecranul
/// să le arate pe măsură ce sosesc.
Stream<PrevedereGasita> cautaPrevederi(
  AnalizaDocument analiza, {
  LegislatieService? service,
}) async* {
  final s = service ?? LegislatieService.instance;
  for (final a in analiza.acte) {
    try {
      final pagina = await s.cauta(a.cerere);
      if (a.cerere.numar.isNotEmpty || a.cerere.titlu.isNotEmpty) {
        final exact = potrivireExacta(pagina.acte, a.cerere, a.tip);
        yield PrevedereGasita(a, [?exact]);
      } else {
        yield PrevedereGasita(a, pagina.acte.take(acteDinTermen).toList());
      }
    } catch (e) {
      yield PrevedereGasita(
        a,
        const [],
        eroare: e is LegislatieException ? e.mesaj : e.toString(),
      );
    }
  }
}
