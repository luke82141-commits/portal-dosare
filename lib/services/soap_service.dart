import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/dosar_model.dart';

/// Rezultatul unei căutări. [limitaAtinsa] este true când serviciul a întors
/// numărul maxim de dosare (1000) și probabil există mai multe rezultate.
class RezultatCautare {
  final List<Dosar> dosare;
  final bool limitaAtinsa;

  const RezultatCautare(this.dosare, this.limitaAtinsa);
}

class SoapException implements Exception {
  final String mesaj;
  SoapException(this.mesaj);

  @override
  String toString() => mesaj;
}

/// Portalul a refuzat cererea pentru că au venit prea multe într-un timp
/// scurt (HTTP 429) sau e supraîncărcat (503). Nu e o defecțiune: trece
/// singur după câteva minute.
class PortalOcupatException extends SoapException {
  final DateTime reincearcaDupa;
  PortalOcupatException(this.reincearcaDupa)
    : super(
        'Portalul instanțelor a primit prea multe cereri într-un timp scurt și a pus '
        'o pauză. Reîncearcă după ora ${reincearcaDupa.hour.toString().padLeft(2, '0')}:'
        '${reincearcaDupa.minute.toString().padLeft(2, '0')}; '
        'verificarea automată reia singură.',
      );
}

/// Client pentru serviciul web oficial al Ministerului Justiției
/// (portalquery.just.ro). Serviciul răspunde doar pe HTTP; pe HTTPS
/// întoarce eroarea 525.
class SoapService {
  static final Uri _endpoint = Uri.parse(
    'http://portalquery.just.ro/query.asmx',
  );
  static const String _ns = 'portalquery.just.ro';
  static const int limitaServiciu = 1000;

  final http.Client _client;

  SoapService({http.Client? client}) : _client = client ?? http.Client();

  /// Pauza minimă între două cereri către portal, pentru toată aplicația
  /// (verificări, căutări, părți urmărite), ca să nu fim limitați (HTTP 429).
  static Duration pauzaIntreCereri = const Duration(milliseconds: 800);

  /// Cât așteptăm după un 429 fără antet Retry-After.
  static Duration asteptareImplicita = const Duration(minutes: 5);

  static DateTime? _ultimaCerere;
  static DateTime? _blocatPanaLa;
  static Future<void> _coada = Future.value();

  /// Așteaptă rândul: cererile pleacă una câte una, cu [pauzaIntreCereri]
  /// între ele. Cât timp portalul ne-a cerut pauză, nu mai trimitem nimic.
  static Future<void> _asteaptaRandul() {
    final rand = _coada.then((_) async {
      final blocat = _blocatPanaLa;
      if (blocat != null && DateTime.now().isBefore(blocat)) {
        throw PortalOcupatException(blocat);
      }
      final ultima = _ultimaCerere;
      if (ultima != null) {
        final ramas = pauzaIntreCereri - DateTime.now().difference(ultima);
        if (ramas > Duration.zero) await Future<void>.delayed(ramas);
      }
      _ultimaCerere = DateTime.now();
    });
    _coada = rand.catchError((_) {});
    return rand;
  }

  /// Pentru teste: uită pauza cerută de portal.
  static void reseteazaLimita() {
    _blocatPanaLa = null;
    _ultimaCerere = null;
  }

  /// Ca [cautaDosare], dar la mai multe instanțe deodată: portalul primește
  /// o singură instanță pe cerere, deci întrebăm pe rând fiecare instanță și
  /// unim rezultatele (fără dubluri). Fără instanțe = toate instanțele.
  Future<RezultatCautare> cautaDosareLaInstante({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    List<String> institutii = const [],
    DateTime? dataStart,
    DateTime? dataStop,
  }) async {
    if (institutii.length <= 1) {
      return cautaDosare(
        numarDosar: numarDosar,
        obiectDosar: obiectDosar,
        numeParte: numeParte,
        institutie: institutii.firstOrNull ?? '',
        dataStart: dataStart,
        dataStop: dataStop,
      );
    }
    final dosare = <String, Dosar>{};
    var limita = false;
    for (final i in institutii) {
      final r = await cautaDosare(
        numarDosar: numarDosar,
        obiectDosar: obiectDosar,
        numeParte: numeParte,
        institutie: i,
        dataStart: dataStart,
        dataStop: dataStop,
      );
      for (final d in r.dosare) {
        dosare.putIfAbsent(d.cheie, () => d);
      }
      limita = limita || r.limitaAtinsa;
    }
    return RezultatCautare(dosare.values.toList(), limita);
  }

  /// Caută dosare după număr, obiect și/sau numele unei părți. Cel puțin unul
  /// dintre aceste trei criterii e obligatoriu; [institutie] (codul SOAP al
  /// instanței, ex. „TribunalulPRAHOVA”) și intervalul [dataStart]–[dataStop]
  /// (data înregistrării dosarului) doar restrâng rezultatele.
  ///
  /// Căutarea după număr este exactă: portalul întoarce doar dosarele cu
  /// numărul respectiv, de la toate instanțele la care a ajuns dosarul.
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
    String numeParte = '',
    String institutie = '',
    DateTime? dataStart,
    DateTime? dataStop,
  }) async {
    final numar = numarDosar.trim();
    final obiect = obiectDosar.trim();
    final parte = numeParte.trim();
    if (numar.isEmpty && obiect.isEmpty && parte.isEmpty) {
      return const RezultatCautare([], false);
    }

    final envelope = construiesteCerereCautare(
      numar: numar,
      obiect: obiect,
      parte: parte,
      institutie: institutie.trim(),
      dataStart: dataStart,
      dataStop: dataStop,
    );

    await _asteaptaRandul();

    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'text/xml; charset=utf-8',
              'SOAPAction': '"$_ns/CautareDosare"',
            },
            body: utf8.encode(envelope),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw SoapException('Nu s-a putut contacta portalul instanțelor: $e');
    }

    if (response.statusCode == 429 || response.statusCode == 503) {
      final secunde = int.tryParse(response.headers['retry-after'] ?? '');
      final pauza = secunde != null && secunde > 0 && secunde < 3600
          ? Duration(seconds: secunde)
          : asteptareImplicita;
      final pana = DateTime.now().add(pauza);
      _blocatPanaLa = pana;
      throw PortalOcupatException(pana);
    }
    if (response.statusCode != 200) {
      throw SoapException(
        'Portalul a răspuns cu eroarea ${response.statusCode}.',
      );
    }

    // Răspunsurile pot avea mai mulți MB; parsarea se face în alt isolate
    // ca să nu blocheze interfața.
    final body = utf8.decode(response.bodyBytes);
    final dosare = await Isolate.run(() => parseazaRaspunsDosare(body));
    return RezultatCautare(dosare, dosare.length >= limitaServiciu);
  }

  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Cererea SOAP pentru operația CautareDosare. Câmpurile goale se trimit ca
/// `xsi:nil`, adică „fără filtru”.
String construiesteCerereCautare({
  String numar = '',
  String obiect = '',
  String parte = '',
  String institutie = '',
  DateTime? dataStart,
  DateTime? dataStop,
}) {
  String camp(String nume, String valoare) => valoare.isEmpty
      ? '<$nume xsi:nil="true"/>'
      : '<$nume>${SoapService.escape(valoare)}</$nume>';
  String zi(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
            '-${d.day.toString().padLeft(2, '0')}T00:00:00';

  return '<?xml version="1.0" encoding="utf-8"?>'
      '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
      'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
      '<soap:Body><CautareDosare xmlns="${SoapService._ns}">'
      '${camp('numarDosar', numar)}'
      '${camp('obiectDosar', obiect)}'
      '${camp('numeParte', parte)}'
      '${camp('institutie', institutie)}'
      '${camp('dataStart', zi(dataStart))}'
      '${camp('dataStop', zi(dataStop))}'
      '</CautareDosare></soap:Body></soap:Envelope>';
}

/// Transformă răspunsul SOAP al operației CautareDosare în lista de dosare.
List<Dosar> parseazaRaspunsDosare(String body) {
  final doc = XmlDocument.parse(body);

  final fault = doc.findAllElements('faultstring').firstOrNull;
  if (fault != null) {
    throw SoapException('Eroare de la portal: ${fault.innerText}');
  }

  final result = doc.findAllElements('CautareDosareResult').firstOrNull;
  if (result == null) return [];

  return result.childElements
      .where((e) => e.localName == 'Dosar')
      .map(_parseazaDosar)
      .toList();
}

Dosar _parseazaDosar(XmlElement e) {
  String text(XmlElement parent, String name) =>
      parent.getElement(name)?.innerText.trim() ?? '';

  final parti =
      e
          .getElement('parti')
          ?.childElements
          .map(
            (p) => Parte(
              nume: text(p, 'nume'),
              calitate: text(p, 'calitateParte'),
            ),
          )
          .toList() ??
      [];

  final sedinte =
      e
          .getElement('sedinte')
          ?.childElements
          .map(
            (s) => Sedinta(
              complet: text(s, 'complet'),
              data: _data(text(s, 'data')),
              ora: text(s, 'ora'),
              solutie: text(s, 'solutie'),
              solutieSumar: text(s, 'solutieSumar'),
              dataPronuntare: _data(text(s, 'dataPronuntare')),
              document: text(s, 'documentSedinta'),
              numarDocument: text(s, 'numarDocument'),
              dataDocument: _data(text(s, 'dataDocument')),
            ),
          )
          .toList() ??
      [];

  final caiAtac =
      e
          .getElement('caiAtac')
          ?.childElements
          .map(
            (c) => CaleAtac(
              dataDeclarare: _data(text(c, 'dataDeclarare')),
              parteDeclaratoare: text(c, 'parteDeclaratoare'),
              tip: text(c, 'tipCaleAtac'),
            ),
          )
          .toList() ??
      [];

  final stadiu = text(e, 'stadiuProcesualNume');
  final categorie = text(e, 'categorieCazNume');

  return Dosar(
    numar: text(e, 'numar'),
    data: _data(text(e, 'data')),
    institutie: text(e, 'institutie'),
    obiect: text(e, 'obiect'),
    stadiuProcesual: stadiu.isNotEmpty ? stadiu : text(e, 'stadiuProcesual'),
    sectie: text(e, 'departament'),
    categorie: categorie.isNotEmpty ? categorie : text(e, 'categorieCaz'),
    dataModificare: _data(text(e, 'dataModificare')),
    parti: parti,
    sedinte: sedinte,
    caiAtac: caiAtac,
  );
}

/// Câmpurile de dată lipsă vin goale (xsi:nil) sau ca 0001-01-01.
DateTime? _data(String iso) {
  final d = DateTime.tryParse(iso);
  return (d == null || d.year < 1900) ? null : d;
}
