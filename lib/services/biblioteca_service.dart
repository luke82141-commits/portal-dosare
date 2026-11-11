import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import 'comparator_dosar.dart';

/// Schimbările găsite la un dosar în urma unei verificări.
class RezultatVerificare {
  final Dosar dosar;
  final List<String> schimbari;

  const RezultatVerificare(this.dosar, this.schimbari);
}

/// Biblioteca de dosare salvate pe dispozitiv.
///
/// Datele stau în SharedPreferences ca JSON. Verificarea din fundal rulează în
/// alt isolate și scrie în același loc, de aceea fiecare operație recitește
/// întâi starea de pe disc.
class BibliotecaService extends ChangeNotifier {
  BibliotecaService._();
  static final BibliotecaService instance = BibliotecaService._();

  static const _cheieDosare = 'biblioteca_dosare_v1';
  static const _cheieIgnorate = 'biblioteca_ignorate_v1';
  static const _maxModificari = 50;

  List<DosarSalvat> _dosare = [];

  // Dosare șterse de utilizator; nu se readaugă automat când reapar la
  // căutarea după număr.
  Set<String> _ignorate = {};

  List<DosarSalvat> get dosare => List.unmodifiable(_dosare);
  int get totalNecitite => _dosare.fold(0, (s, d) => s + d.necitite);

  bool contine(String cheie) => _dosare.any((d) => d.dosar.cheie == cheie);

  /// Numerele distincte de dosar urmărite (o interogare pe portal per număr).
  Set<String> get numereUrmarite => {for (final d in _dosare) d.dosar.numar};

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final brut = prefs.getString(_cheieDosare);
    try {
      _dosare = brut == null
          ? []
          : [for (final j in jsonDecode(brut) as List) DosarSalvat.fromJson(j)];
    } catch (e) {
      debugPrint('Biblioteca nu a putut fi citită: $e');
      _dosare = [];
    }
    _ignorate = (prefs.getStringList(_cheieIgnorate) ?? []).toSet();
    notifyListeners();
  }

  Future<void> _salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cheieDosare,
      jsonEncode([for (final d in _dosare) d.toJson()]),
    );
    await prefs.setStringList(_cheieIgnorate, _ignorate.toList());
    notifyListeners();
  }

  Future<void> adauga(Dosar dosar) async {
    await incarca();
    if (contine(dosar.cheie)) return;
    final acum = DateTime.now();
    _dosare.insert(0, DosarSalvat(dosar: dosar, adaugatLa: acum, ultimaVerificare: acum));
    _ignorate.remove(dosar.cheie);
    await _salveaza();
  }

  Future<void> sterge(String cheie) async {
    await incarca();
    _dosare.removeWhere((d) => d.dosar.cheie == cheie);
    _ignorate.add(cheie);
    await _salveaza();
  }

  Future<void> marcheazaCitit(String cheie) async {
    await incarca();
    final i = _dosare.indexWhere((d) => d.dosar.cheie == cheie);
    if (i < 0 || _dosare[i].necitite == 0) return;
    _dosare[i] = _dosare[i].copyWith(necitite: 0);
    await _salveaza();
  }

  /// Aplică datele proaspete de pe portal peste cele salvate și întoarce
  /// schimbările găsite, pe dosare.
  ///
  /// [proaspete] sunt dosarele întoarse de portal pentru numerele din
  /// [numereVerificate]. Un dosar salvat care lipsește din răspuns rămâne
  /// neatins. Un dosar cu un număr urmărit care apare la o instanță nouă
  /// (de exemplu în apel) este adăugat automat în bibliotecă.
  Future<List<RezultatVerificare>> aplicaActualizari(
    List<Dosar> proaspete, {
    required Set<String> numereVerificate,
    DateTime? acum,
  }) async {
    await incarca();
    final moment = acum ?? DateTime.now();
    final dupaCheie = {for (final d in proaspete) d.cheie: d};
    final rezultate = <RezultatVerificare>[];

    for (var i = 0; i < _dosare.length; i++) {
      final salvat = _dosare[i];
      if (!numereVerificate.contains(salvat.dosar.numar)) continue;

      final nou = dupaCheie[salvat.dosar.cheie];
      if (nou == null) {
        _dosare[i] = salvat.copyWith(ultimaVerificare: moment);
        continue;
      }

      final schimbari = comparaDosare(salvat.dosar, nou);
      _dosare[i] = salvat.copyWith(
        dosar: nou,
        ultimaVerificare: moment,
        modificari: [
          for (final s in schimbari) Modificare(detectataLa: moment, text: s),
          ...salvat.modificari,
        ].take(_maxModificari).toList(),
        necitite: salvat.necitite + schimbari.length,
      );
      if (schimbari.isNotEmpty) rezultate.add(RezultatVerificare(nou, schimbari));
    }

    final urmarite = numereUrmarite;
    for (final d in proaspete) {
      if (!urmarite.contains(d.numar) || contine(d.cheie) || _ignorate.contains(d.cheie)) {
        continue;
      }
      final text = 'Dosarul a fost înregistrat la o nouă instanță: ${d.instanta}'
          '${d.stadiuProcesual.isEmpty ? '' : ' (${d.stadiuProcesual})'}';
      _dosare.insert(
        0,
        DosarSalvat(
          dosar: d,
          adaugatLa: moment,
          ultimaVerificare: moment,
          modificari: [Modificare(detectataLa: moment, text: text)],
          necitite: 1,
        ),
      );
      rezultate.add(RezultatVerificare(d, [text]));
    }

    await _salveaza();
    return rezultate;
  }
}
