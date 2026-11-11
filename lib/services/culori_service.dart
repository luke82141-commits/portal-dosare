import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import 'biblioteca_service.dart';

/// Culorile din care se aleg dosarele (ca în Google Calendar).
const List<(Color, String)> paletaDosare = [
  (Color(0xFF1F3A93), 'Bleumarin'),
  (Color(0xFF039BE5), 'Albastru'),
  (Color(0xFF0B8043), 'Verde'),
  (Color(0xFF33B679), 'Salvie'),
  (Color(0xFFB8892F), 'Auriu'),
  (Color(0xFFF6BF26), 'Galben'),
  (Color(0xFFF4511E), 'Portocaliu'),
  (Color(0xFFD50000), 'Roșu'),
  (Color(0xFFE67C73), 'Roz'),
  (Color(0xFF8E24AA), 'Mov'),
  (Color(0xFF7986CB), 'Lavandă'),
  (Color(0xFF616161), 'Grafit'),
];

/// Culoarea fiecărui dosar: cea aleasă de utilizator sau, dacă nu a ales,
/// una automată, diferită de a dosarelor care au termen în aceeași zi.
class CuloriDosareService extends ChangeNotifier {
  CuloriDosareService._() {
    BibliotecaService.instance.addListener(_invalideaza);
  }
  static final CuloriDosareService instance = CuloriDosareService._();

  static const _cheie = 'culori_dosare_v1';

  Map<String, int> _alese = {};
  Map<String, Color>? _calculate;

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    final l = prefs.getStringList(_cheie) ?? const <String>[];
    _alese = {
      for (final s in l)
        if (s.lastIndexOf('=') case final i when i > 0)
          s.substring(0, i): int.tryParse(s.substring(i + 1)) ?? 0,
    };
    _invalideaza();
  }

  /// Culoarea aleasă de utilizator, sau null dacă e automată.
  Color? aleasa(String cheie) => _alese[cheie] == null ? null : Color(_alese[cheie]!);

  /// [culoare] null revine la culoarea automată.
  Future<void> seteaza(String cheie, Color? culoare) async {
    if (culoare == null) {
      _alese.remove(cheie);
    } else {
      _alese[cheie] = culoare.toARGB32();
    }
    _invalideaza();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cheie, [for (final e in _alese.entries) '${e.key}=${e.value}']);
  }

  /// Culoarea dosarului [d] (din bibliotecă sau nu).
  Color culoare(Dosar d) {
    _calculate ??= culoriAutomate(
      [for (final s in BibliotecaService.instance.dosare.reversed) s.dosar],
      alese: {for (final e in _alese.entries) e.key: Color(e.value)},
    );
    return _calculate![d.cheie] ?? aleasa(d.cheie) ?? paletaDosare[_preferata(d.cheie)].$1;
  }

  void _invalideaza() {
    _calculate = null;
    notifyListeners();
  }
}

int _preferata(String cheie) {
  var h = 0;
  for (final c in cheie.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h % paletaDosare.length;
}

/// Atribuie culori dosarelor [dosare] (de la cel mai vechi la cel mai nou),
/// astfel încât două dosare cu termen în aceeași zi să nu aibă aceeași
/// culoare, cât timp paleta ajunge. Culorile din [alese] se păstrează.
///
/// Fiecare dosar pornește de la o culoare derivată din număr, deci adăugarea
/// unui dosar nou nu le schimbă pe ale celor existente.
Map<String, Color> culoriAutomate(List<Dosar> dosare, {Map<String, Color> alese = const {}}) {
  final peZile = <DateTime, Set<String>>{};
  for (final d in dosare) {
    for (final s in d.sedinte) {
      if (s.data == null) continue;
      (peZile[DateUtils.dateOnly(s.data!)] ??= {}).add(d.cheie);
    }
  }
  final vecini = <String, Set<String>>{};
  for (final zi in peZile.values) {
    for (final c in zi) {
      (vecini[c] ??= {}).addAll(zi.where((x) => x != c));
    }
  }

  final rezultat = <String, Color>{...alese};
  for (final d in dosare) {
    if (rezultat.containsKey(d.cheie)) continue;
    final ocupate = {
      for (final v in vecini[d.cheie] ?? const <String>{}) ?rezultat[v],
    };
    final start = _preferata(d.cheie);
    Color? aleasa;
    for (var k = 0; k < paletaDosare.length; k++) {
      final c = paletaDosare[(start + k) % paletaDosare.length].$1;
      if (!ocupate.contains(c)) {
        aleasa = c;
        break;
      }
    }
    rezultat[d.cheie] = aleasa ?? paletaDosare[start].$1;
  }
  return rezultat;
}
