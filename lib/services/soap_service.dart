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

/// Client pentru serviciul web oficial al Ministerului Justiției
/// (portalquery.just.ro). Serviciul răspunde doar pe HTTP; pe HTTPS
/// întoarce eroarea 525.
class SoapService {
  static final Uri _endpoint = Uri.parse('http://portalquery.just.ro/query.asmx');
  static const String _ns = 'portalquery.just.ro';
  static const int limitaServiciu = 1000;

  final http.Client _client;

  SoapService({http.Client? client}) : _client = client ?? http.Client();

  /// Caută dosare după număr și/sau obiect. Cel puțin un criteriu e obligatoriu.
  Future<RezultatCautare> cautaDosare({
    String numarDosar = '',
    String obiectDosar = '',
  }) async {
    final numar = numarDosar.trim();
    final obiect = obiectDosar.trim();
    if (numar.isEmpty && obiect.isEmpty) {
      return const RezultatCautare([], false);
    }

    final envelope = _construiesteCerere(numar: numar, obiect: obiect);

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

    if (response.statusCode != 200) {
      throw SoapException('Portalul a răspuns cu eroarea ${response.statusCode}.');
    }

    // Răspunsurile pot avea mai mulți MB; parsarea se face în alt isolate
    // ca să nu blocheze interfața.
    final body = utf8.decode(response.bodyBytes);
    final dosare = await Isolate.run(() => _parseazaRaspuns(body));
    return RezultatCautare(dosare, dosare.length >= limitaServiciu);
  }

  String _construiesteCerere({required String numar, required String obiect}) {
    String camp(String nume, String valoare) => valoare.isEmpty
        ? '<$nume xsi:nil="true"/>'
        : '<$nume>${_escape(valoare)}</$nume>';

    return '<?xml version="1.0" encoding="utf-8"?>'
        '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
        'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
        '<soap:Body><CautareDosare xmlns="$_ns">'
        '${camp('numarDosar', numar)}'
        '${camp('obiectDosar', obiect)}'
        '<numeParte xsi:nil="true"/>'
        '<institutie xsi:nil="true"/>'
        '<dataStart xsi:nil="true"/>'
        '<dataStop xsi:nil="true"/>'
        '</CautareDosare></soap:Body></soap:Envelope>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

List<Dosar> _parseazaRaspuns(String body) {
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

  final parti = e
          .getElement('parti')
          ?.childElements
          .map((p) => Parte(nume: text(p, 'nume'), calitate: text(p, 'calitateParte')))
          .toList() ??
      [];

  final sedinte = e
          .getElement('sedinte')
          ?.childElements
          .map((s) => Sedinta(
                complet: text(s, 'complet'),
                data: _formateazaData(text(s, 'data')),
                ora: text(s, 'ora'),
                solutie: text(s, 'solutie'),
                solutieSumar: text(s, 'solutieSumar'),
              ))
          .toList() ??
      [];

  final stadiu = text(e, 'stadiuProcesualNume');
  final categorie = text(e, 'categorieCazNume');

  return Dosar(
    numar: text(e, 'numar'),
    data: _formateazaData(text(e, 'data')),
    institutie: text(e, 'institutie'),
    obiect: text(e, 'obiect'),
    stadiuProcesual: stadiu.isNotEmpty ? stadiu : text(e, 'stadiuProcesual'),
    sectie: text(e, 'departament'),
    categorie: categorie.isNotEmpty ? categorie : text(e, 'categorieCaz'),
    parti: parti,
    sedinte: sedinte,
  );
}

/// "2026-11-04T10:32:00" -> "04.11.2026"
String _formateazaData(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}
