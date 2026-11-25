import 'legislatie_service.dart';
import 'monitor_oficial_service.dart';

const _luni = [
  'ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie', 'iulie', 'august',
  'septembrie', 'octombrie', 'noiembrie', 'decembrie',
];

/// „MONITORUL OFICIAL nr. 1.050 bis din 24 noiembrie 2026” → numărul și ziua.
({String monitor, DateTime zi})? monitorDinPublicatie(String publicatie) {
  final m = RegExp(
    r'nr\.\s*([\d.]+)(\s*bis)?\s*din\s+(\d{1,2})\s+([a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+)\s+(\d{4})',
    caseSensitive: false,
  ).firstMatch(publicatie);
  if (m == null) return null;
  final luna = _luni.indexOf(fataDiacritice(m.group(4)!.toLowerCase())) + 1;
  if (luna == 0) return null;
  final nr = m.group(1)!.replaceAll('.', '');
  return (
    monitor: m.group(2) == null ? nr : '$nr bis',
    zi: DateTime(int.parse(m.group(5)!), luna, int.parse(m.group(3)!)),
  );
}

/// Ce caută sursa pentru ziua [zi]: „din 24 noiembrie 2026”. Titlul din
/// serviciu conține și antetul („PUBLICAT ÎN: MONITORUL OFICIAL nr. … din
/// 24 noiembrie 2026”), deci fraza prinde actele publicate atunci (și pe
/// cele emise atunci, pe care le scoatem după câmpul Publicatie).
String frazaZi(DateTime zi) => 'din ${zi.day} ${_luni[zi.month - 1]} ${zi.year}';

ActPublicat? actPublicatDin(ActNormativ a, DateTime zi) {
  final mo = monitorDinPublicatie(a.publicatie);
  if (mo == null || mo.zi != DateTime(zi.year, zi.month, zi.day)) return null;
  return ActPublicat(
    tip: a.tipAct,
    numar: a.numar,
    titlu: _faraDenumire(titluCurat(a.titlu)),
    emitent: a.emitent,
    monitor: mo.monitor,
    dataPublicarii: mo.zi,
    link: a.linkHtml,
  );
}

/// „LEGE nr. 312 din 20 noiembrie 2026 privind …” → „privind …”.
String _faraDenumire(String titlu) {
  final m = RegExp(
    r'^.*?\bdin\s+\d{1,2}\s+[a-zA-ZăâîșşțţĂÂÎȘŞȚŢ]+\s+\d{4}\s*',
  ).firstMatch(titlu);
  final rest = m == null ? titlu : titlu.substring(m.end);
  return rest.trim().isEmpty ? titlu.trim() : rest.trim();
}

/// Monitorul Oficial din Portalul Legislativ (legislatie.just.ro), prin
/// serviciul SOAP gratuit al aplicației.
///
/// DE VERIFICAT pe un telefon sau PC din România (din cloud site-ul e
/// blocat): dacă SearchTitlu caută și în antet („PUBLICAT ÎN …”) și cât
/// de repede apar actele după publicare.
class SursaLegislatieMO implements SursaMonitorOficial {
  final LegislatieService _serviciu;

  SursaLegislatieMO({LegislatieService? serviciu})
    : _serviciu = serviciu ?? LegislatieService.instance;

  /// Un Monitor are de obicei 5–15 acte, o zi 20–80. Peste atâtea pagini
  /// ne oprim, ca să nu încărcăm serviciul public.
  static const maxPagini = 15;

  @override
  String get nume => 'Portalul Legislativ (legislatie.just.ro)';

  @override
  Future<List<ActPublicat>> actePublicate(DateTime zi) async {
    final cerere = CerereLegislatie(titlu: frazaZi(zi), an: zi.year);
    final acte = <ActPublicat>[];
    final vazute = <String>{};
    for (var p = 1; p <= maxPagini; p++) {
      final PaginaLegislatie pagina;
      try {
        pagina = await _serviciu.cauta(cerere, pagina: p, simplu: true);
      } on LegislatieException catch (e) {
        if (p == 1) throw MonitorOficialException(e.mesaj);
        break;
      }
      for (final a in pagina.acte) {
        final x = actPublicatDin(a, zi);
        if (x != null && vazute.add(x.cheie)) acte.add(x);
      }
      if (!pagina.maiSunt) break;
    }
    return acte;
  }
}
