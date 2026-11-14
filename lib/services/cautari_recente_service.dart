import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatare.dart';
import '../utils/instante.dart';

/// O căutare făcută anterior, afișată ca scurtătură pe ecranul de căutare.
/// Ține toate criteriile, ca să poată fi reluată exact.
class CautareRecenta {
  final String numar;
  final String obiect;
  final String parte;

  /// Codul SOAP al instanței (ex. „TribunalulPRAHOVA”), gol = toate.
  final String institutie;

  /// Intervalul în care a fost înregistrat dosarul.
  final DateTime? dataStart;
  final DateTime? dataStop;

  const CautareRecenta({
    this.numar = '',
    this.obiect = '',
    this.parte = '',
    this.institutie = '',
    this.dataStart,
    this.dataStop,
  });

  /// True dacă are cel puțin un criteriu pe care portalul îl acceptă singur.
  bool get areCriteriuPrincipal => numar.isNotEmpty || obiect.isNotEmpty || parte.isNotEmpty;

  String get interval => switch ((dataStart, dataStop)) {
        (null, null) => '',
        (final a?, null) => 'din ${formateazaData(a)}',
        (null, final b?) => 'până la ${formateazaData(b)}',
        (final a?, final b?) => '${formateazaData(a)}–${formateazaData(b)}',
      };

  String get eticheta => [
        numar,
        obiect,
        parte,
        if (institutie.isNotEmpty) numeInstanta(institutie),
        interval,
      ].where((e) => e.isNotEmpty).join(' · ');

  static String _data(DateTime? d) => d?.toIso8601String() ?? '';

  String _codifica() =>
      [numar, obiect, parte, institutie, _data(dataStart), _data(dataStop)].join('\u0001');

  static CautareRecenta _decodifica(String s) {
    final p = s.split('\u0001');
    String camp(int i) => p.length > i ? p[i] : '';
    return CautareRecenta(
      numar: camp(0),
      obiect: camp(1),
      parte: camp(2),
      institutie: camp(3),
      dataStart: DateTime.tryParse(camp(4)),
      dataStop: DateTime.tryParse(camp(5)),
    );
  }

  @override
  bool operator ==(Object other) => other is CautareRecenta && other._codifica() == _codifica();

  @override
  int get hashCode => _codifica().hashCode;
}

/// Ultimele căutări, păstrate pe dispozitiv.
class CautariRecenteService extends ChangeNotifier {
  CautariRecenteService._();
  static final CautariRecenteService instance = CautariRecenteService._();

  static const _cheie = 'cautari_recente_v1';
  static const _max = 6;

  List<CautareRecenta> _lista = [];
  List<CautareRecenta> get lista => List.unmodifiable(_lista);

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    _lista = [
      for (final s in prefs.getStringList(_cheie) ?? const <String>[])
        CautareRecenta._decodifica(s),
    ];
    notifyListeners();
  }

  Future<void> adauga(CautareRecenta c) async {
    if (c.eticheta.isEmpty) return;
    _lista = [c, ..._lista.where((e) => e != c)].take(_max).toList();
    await _salveaza();
  }

  Future<void> sterge() async {
    _lista = [];
    await _salveaza();
  }

  Future<void> _salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cheie, [for (final c in _lista) c._codifica()]);
    notifyListeners();
  }
}
