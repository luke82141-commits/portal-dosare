/// Toate instanțele de pe portal.just.ro, cu numărul lor de pe portal.
///
/// Numărul e și cel din mijlocul numerelor de dosar (14993/**299**/2026) și
/// duce la paginile oficiale ale instanței, de ex. „Date de contact”, unde
/// fiecare instanță își publică adresa, telefoanele și programul serviciilor
/// (registratură, arhivă, relații cu publicul etc.).
library;

import '../utils/instante.dart';

part 'instante_portal_lista.dart';

enum TipInstanta { curteDeApel, tribunal, judecatorie }

class InstantaPortal {
  final int id;

  /// Denumirea așa cum apare pe portal (uneori fără diacritice).
  final String numePortal;

  /// Identificatorul folosit de serviciul SOAP (ex. „JudecatoriaSECTORUL1BUCURESTI”).
  final String cod;
  final String judet;

  /// Curtea de apel în a cărei rază se află.
  final String curte;

  const InstantaPortal(this.id, this.numePortal, this.cod, this.judet, this.curte);

  /// Aceeași denumire ca la dosare (cu diacritice), dacă o știm; altfel cea
  /// de pe portal.
  String get nume {
    final n = numeInstanta(cod);
    return n == cod ? numePortal : n;
  }

  TipInstanta get tip => nume.startsWith('Curtea')
      ? TipInstanta.curteDeApel
      : nume.startsWith('Tribunalul')
          ? TipInstanta.tribunal
          : TipInstanta.judecatorie;

  Uri _pagina(String pagina) => Uri.https('portal.just.ro', '/$id/SitePages/$pagina');

  /// Adresa, telefoanele, emailul și programul serviciilor.
  Uri get paginaContact => _pagina('contact.aspx');
  Uri get paginaAcasa =>
      Uri.https('portal.just.ro', '/$id/SitePages/acasa_default.aspx', {'id_inst': '$id'});
  Uri get listaSedinte => _pagina('Lista_Sedinte.aspx');
}

const List<InstantaPortal> toateInstantele = _instante;

final Map<String, InstantaPortal> _dupaCod = {
  for (final i in _instante) i.cod.toLowerCase(): i,
};

/// Instanța unui dosar, după identificatorul primit de la portal.
InstantaPortal? instantaDupaCod(String cod) => _dupaCod[cod.trim().toLowerCase()];
