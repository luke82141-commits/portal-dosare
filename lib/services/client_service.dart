import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import 'raport_service.dart';

/// „Clientul meu”: partea pe care o reprezinți, aleasă în detaliul dosarului
/// (Părți). Se ține după numărul dosarului, deci rămâne aceeași la fond,
/// apel și recurs, chiar dacă își schimbă calitatea.
class ClientService extends ChangeNotifier {
  ClientService._();
  static final ClientService instance = ClientService._();

  static const _cheie = 'clientul_meu_v1';
  Map<String, String> _clienti = {};

  static String _nume(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    final l = prefs.getStringList(_cheie) ?? const <String>[];
    _clienti = {
      for (final s in l)
        if (s.indexOf('\u0001') case final i when i > 0)
          s.substring(0, i): s.substring(i + 1),
    };
    notifyListeners();
  }

  /// Numele clientului la dosarul [numar], dacă e ales.
  String? client(String numar) => _clienti[numar];

  bool esteClient(String numar, Parte p) => _clienti[numar] == _nume(p.nume);

  /// Partea clientului în dosarul [d] (cu calitatea din această fază).
  Parte? parteaClientului(Dosar d) {
    final c = _clienti[d.numar];
    if (c == null) return null;
    for (final p in d.parti) {
      if (_nume(p.nume) == c) return p;
    }
    return null;
  }

  /// Alege [p] drept client; dacă era deja, îl scoate.
  Future<void> comuta(String numar, Parte p) async {
    if (esteClient(numar, p)) {
      _clienti.remove(numar);
    } else {
      _clienti[numar] = _nume(p.nume);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cheie, [
      for (final e in _clienti.entries) '${e.key}\u0001${e.value}',
    ]);
  }
}

String _fara(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ăâ]'), 'a')
    .replaceAll('î', 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't');

enum Pozitie { initiator, aparare, necunoscuta }

/// Cine a pornit cererea în faza respectivă: apelantul, recurentul,
/// contestatorul, reclamantul… Calitatea din faza curentă contează întâi
/// („Intimat-Reclamant” apără o hotărâre, deci e în apărare).
Pozitie pozitie(String calitate) {
  final c = _fara(calitate);
  if (c.isEmpty || c.contains('debitor') || c.contains('creditor'))
    return Pozitie.necunoscuta;
  if (RegExp(r'apelant|recurent|revizuent|contestator|petitionar')
      .hasMatch(c)) {
    return Pozitie.initiator;
  }
  if (c.contains('intimat')) return Pozitie.aparare;
  if (RegExp(r'reclamant|petent').hasMatch(c)) return Pozitie.initiator;
  if (RegExp(r'parat|chemat in garantie').hasMatch(c)) return Pozitie.aparare;
  return Pozitie.necunoscuta;
}

/// „Favorabil”, „Nefavorabil”, „Parțial” sau gol (fără client, fără
/// hotărâre sau calitate neclară, ex. la insolvență).
String rezultatPentruClient(Parte? client, Sedinta hotarare) {
  if (client == null) return '';
  final poz = pozitie(client.calitate);
  if (poz == Pozitie.necunoscuta) return '';
  return switch (tipSolutie(hotarare)) {
    TipSolutie.admiteInParte => 'Parțial',
    TipSolutie.admite => poz == Pozitie.initiator ? 'Favorabil' : 'Nefavorabil',
    TipSolutie.respinge =>
      poz == Pozitie.initiator ? 'Nefavorabil' : 'Favorabil',
    _ => '',
  };
}
