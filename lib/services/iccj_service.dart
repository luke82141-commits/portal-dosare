import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dosar_model.dart';

/// Codul sub care ținem în bibliotecă dosarele Înaltei Curți (portal.just.ro
/// nu le are; vin din serviciul separat al ÎCCJ).
const codIccj = 'InaltaCurteDeCasatieSiJustitie';
const numeIccj = 'Înalta Curte de Casație și Justiție';

/// Serviciul ÎCCJ (documentația v1.0, oct. 2019: scj.ro). Răspunde, după
/// documentație, doar între 03:30 și 06:30; în rest conexiunea expiră.
class IccjService {
  final http.Client _client;
  IccjService({http.Client? client}) : _client = client ?? http.Client();

  static const _baza = 'http://api.scj.ro:97/api';

  /// Dacă [t] cade în fereastra în care răspunde serviciul ÎCCJ.
  static bool inFereastra(DateTime t) {
    final m = t.hour * 60 + t.minute;
    return m >= 3 * 60 + 30 && m < 6 * 60 + 30;
  }

  /// Dosarele ÎCCJ cu numărul [numar]. Aruncă [IccjException] dacă serviciul
  /// nu răspunde (de obicei în afara ferestrei de noapte).
  Future<List<Dosar>> cautaDosar(String numar) async {
    final uri = Uri.parse('$_baza/CautareDosare').replace(queryParameters: {'nr': numar.trim()});
    final http.Response r;
    try {
      r = await _client.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw IccjException('ÎCCJ nu răspunde acum. Serviciul lor merge doar între 03:30 și 06:30.');
    }
    if (r.statusCode != 200) {
      throw IccjException('ÎCCJ a răspuns cu eroarea ${r.statusCode}.');
    }
    return parseazaDosareIccj(utf8.decode(r.bodyBytes));
  }
}

class IccjException implements Exception {
  final String mesaj;
  const IccjException(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Câmpurile, căutate fără să conteze majusculele (documentația le scrie
/// camelCase, dar ASP.NET le poate întoarce și PascalCase).
Object? _camp(Map m, String nume) {
  if (m.containsKey(nume)) return m[nume];
  final mic = nume.toLowerCase();
  for (final e in m.entries) {
    if ('${e.key}'.toLowerCase() == mic) return e.value;
  }
  return null;
}

String _text(Map m, String nume) => '${_camp(m, nume) ?? ''}'.trim();
DateTime? _data(Map m, String nume) => DateTime.tryParse(_text(m, nume));
List<Map> _lista(Map m, String nume) => [
  for (final e in (_camp(m, nume) as List? ?? const []))
    if (e is Map) e,
];

/// Transformă răspunsul ÎCCJ în dosarele aplicației. Acceptă atât o listă,
/// cât și un obiect care conține lista (ex. {"dosare": [...]}).
List<Dosar> parseazaDosareIccj(String json) {
  final brut = jsonDecode(json);
  final List lista = switch (brut) {
    List l => l,
    Map m => m.values.whereType<List>().firstOrNull ?? [m],
    _ => const [],
  };
  return [
    for (final d in lista.whereType<Map>())
      if (_text(d, 'numar').isNotEmpty)
        Dosar(
          numar: _text(d, 'numar'),
          data: _data(d, 'data'),
          institutie: codIccj,
          obiect: _text(d, 'obiect'),
          stadiuProcesual: _text(d, 'stadiuProcesual'),
          sectie: _text(d, 'departament'),
          categorie: _text(d, 'categorieCaz'),
          parti: [
            for (final p in _lista(d, 'parti'))
              Parte(
                nume: _text(p, 'nume'),
                calitate: _text(p, 'calitateaProcesualaCurenta').isNotEmpty
                    ? _text(p, 'calitateaProcesualaCurenta')
                    : _text(p, 'calitateParte'),
              ),
          ],
          sedinte: [
            for (final s in _lista(d, 'sedinte'))
              Sedinta(
                complet: _text(s, 'complet'),
                data: _data(s, 'data'),
                ora: _text(s, 'ora'),
                solutie: _text(s, 'solutie'),
                solutieSumar: _text(s, 'detaliiSolutie').isNotEmpty
                    ? _text(s, 'detaliiSolutie')
                    : _text(s, 'solutieSumar'),
                document: _text(s, 'tipDocument'),
                numarDocument: _text(s, 'numarDocument'),
                dataDocument: _data(s, 'dataDocument'),
              ),
          ],
        ),
  ];
}

/// Un dosar ÎCCJ adăugat ziua, când serviciul nu răspunde: îl ținem în
/// bibliotecă doar cu numărul, iar verificarea de noapte îl completează.
Dosar dosarIccjInAsteptare(String numar) => Dosar(
  numar: numar.trim(),
  data: null,
  institutie: codIccj,
  obiect: 'Se încarcă de la ÎCCJ la noapte (serviciul lor merge 03:30–06:30)',
  stadiuProcesual: '',
  sectie: '',
  categorie: '',
  parti: const [],
  sedinte: const [],
);

bool esteIccjInAsteptare(Dosar d) => d.institutie == codIccj && d.data == null && d.sedinte.isEmpty;
