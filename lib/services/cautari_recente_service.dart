import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O căutare făcută anterior, afișată ca scurtătură pe ecranul de căutare.
class CautareRecenta {
  final String numar;
  final String obiect;

  const CautareRecenta({this.numar = '', this.obiect = ''});

  String get eticheta => [numar, obiect].where((e) => e.isNotEmpty).join(' · ');

  String _codifica() => '$numar\u0001$obiect';

  static CautareRecenta _decodifica(String s) {
    final p = s.split('\u0001');
    return CautareRecenta(numar: p.first, obiect: p.length > 1 ? p[1] : '');
  }

  @override
  bool operator ==(Object other) =>
      other is CautareRecenta && other.numar == numar && other.obiect == obiect;

  @override
  int get hashCode => Object.hash(numar, obiect);
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
