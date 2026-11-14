import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import '../utils/instante.dart';
import 'soap_service.dart';

/// Un dosar apărut pe portal pe numele unei părți urmărite.
class DosarNouParte {
  final Dosar dosar;
  final DateTime gasitLa;
  final bool citit;

  const DosarNouParte({required this.dosar, required this.gasitLa, this.citit = false});

  DosarNouParte citire() => DosarNouParte(dosar: dosar, gasitLa: gasitLa, citit: true);

  factory DosarNouParte.fromJson(Map<String, dynamic> j) => DosarNouParte(
    dosar: Dosar.fromJson(j['dosar']),
    gasitLa: DateTime.parse(j['gasitLa']),
    citit: j['citit'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'dosar': dosar.toJson(),
    'gasitLa': gasitLa.toIso8601String(),
    'citit': citit,
  };
}

/// O parte (persoană sau firmă) pentru care utilizatorul vrea să afle când
/// apare un dosar nou pe portal.
class ParteUrmarita {
  final String nume;

  /// Codul SOAP al instanței, gol = toate instanțele.
  final String institutie;
  final DateTime adaugataLa;
  final DateTime? ultimaVerificare;

  /// Cheile dosarelor deja văzute; doar cele din afara listei sunt „noi”.
  final Set<String> cunoscute;
  final List<DosarNouParte> dosareNoi;

  const ParteUrmarita({
    required this.nume,
    this.institutie = '',
    required this.adaugataLa,
    this.ultimaVerificare,
    this.cunoscute = const {},
    this.dosareNoi = const [],
  });

  /// Identifică urmărirea: aceeași parte poate fi urmărită separat la
  /// instanțe diferite.
  String get cheie => cheiePentru(nume, institutie);

  static String cheiePentru(String nume, String institutie) =>
      '${nume.trim().toLowerCase()}|$institutie';

  String get eticheta => institutie.isEmpty ? nume : '$nume · ${numeInstanta(institutie)}';

  int get necitite => dosareNoi.where((d) => !d.citit).length;

  /// Căutăm doar dosarele înregistrate cu puțin înainte de începutul
  /// urmăririi și după, ca numele des întâlnite să nu atingă limita de 1.000
  /// de rezultate a portalului.
  DateTime get dataStart => adaugataLa.subtract(const Duration(days: 30));

  ParteUrmarita copyWith({
    DateTime? ultimaVerificare,
    Set<String>? cunoscute,
    List<DosarNouParte>? dosareNoi,
  }) => ParteUrmarita(
    nume: nume,
    institutie: institutie,
    adaugataLa: adaugataLa,
    ultimaVerificare: ultimaVerificare ?? this.ultimaVerificare,
    cunoscute: cunoscute ?? this.cunoscute,
    dosareNoi: dosareNoi ?? this.dosareNoi,
  );

  factory ParteUrmarita.fromJson(Map<String, dynamic> j) => ParteUrmarita(
    nume: j['nume'] ?? '',
    institutie: j['institutie'] ?? '',
    adaugataLa: DateTime.parse(j['adaugataLa']),
    ultimaVerificare: DateTime.tryParse(j['ultimaVerificare'] ?? ''),
    cunoscute: {for (final c in (j['cunoscute'] as List? ?? const [])) c as String},
    dosareNoi: [for (final d in (j['dosareNoi'] as List? ?? const [])) DosarNouParte.fromJson(d)],
  );

  Map<String, dynamic> toJson() => {
    'nume': nume,
    'institutie': institutie,
    'adaugataLa': adaugataLa.toIso8601String(),
    'ultimaVerificare': ultimaVerificare?.toIso8601String(),
    'cunoscute': cunoscute.toList(),
    'dosareNoi': [for (final d in dosareNoi) d.toJson()],
  };
}

/// Ce a adus o verificare pentru o parte urmărită.
class RezultatParte {
  final ParteUrmarita parte;
  final List<Dosar> dosareNoi;

  const RezultatParte(this.parte, this.dosareNoi);
}

/// Părțile urmărite, păstrate pe dispozitiv. Ca biblioteca, fiecare operație
/// recitește întâi discul, fiindcă verificarea din fundal rulează în alt
/// isolate.
class PartiUrmariteService extends ChangeNotifier {
  PartiUrmariteService._();
  static final PartiUrmariteService instance = PartiUrmariteService._();

  static const _cheie = 'parti_urmarite_v1';
  static const _maxDosareNoi = 50;

  List<ParteUrmarita> _parti = [];
  List<ParteUrmarita> get parti => List.unmodifiable(_parti);
  int get totalNecitite => _parti.fold(0, (s, p) => s + p.necitite);

  bool urmareste(String nume, String institutie) =>
      _parti.any((p) => p.cheie == ParteUrmarita.cheiePentru(nume, institutie));

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final brut = prefs.getString(_cheie);
    try {
      _parti = brut == null
          ? []
          : [for (final j in jsonDecode(brut) as List) ParteUrmarita.fromJson(j)];
    } catch (e) {
      debugPrint('Părțile urmărite nu au putut fi citite: $e');
      _parti = [];
    }
    notifyListeners();
  }

  Future<void> _salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cheie, jsonEncode([for (final p in _parti) p.toJson()]));
    notifyListeners();
  }

  /// Începe urmărirea. Dosarele existente acum pe portal sunt marcate ca
  /// știute, ca să fie anunțate doar cele apărute de acum înainte. Întoarce
  /// true dacă portalul a atins limita de rezultate (numele e prea general).
  Future<bool> adauga(
    String nume, {
    String institutie = '',
    SoapService? soap,
    DateTime? acum,
  }) async {
    await incarca();
    final n = nume.trim();
    if (n.isEmpty || urmareste(n, institutie)) return false;

    final moment = acum ?? DateTime.now();
    var parte = ParteUrmarita(nume: n, institutie: institutie, adaugataLa: moment);
    final r = await (soap ?? SoapService()).cautaDosare(
      numeParte: n,
      institutie: institutie,
      dataStart: parte.dataStart,
    );
    parte = parte.copyWith(
      ultimaVerificare: moment,
      cunoscute: {for (final d in r.dosare) d.cheie},
    );

    await incarca();
    _parti = [parte, ..._parti.where((p) => p.cheie != parte.cheie)];
    await _salveaza();
    return r.limitaAtinsa;
  }

  Future<void> sterge(String cheie) async {
    await incarca();
    _parti = _parti.where((p) => p.cheie != cheie).toList();
    await _salveaza();
  }

  Future<void> marcheazaCitite(String cheie) async {
    await incarca();
    _parti = [
      for (final p in _parti)
        p.cheie == cheie ? p.copyWith(dosareNoi: [for (final d in p.dosareNoi) d.citire()]) : p,
    ];
    await _salveaza();
  }

  /// Caută pe portal fiecare parte urmărită și întoarce dosarele apărute de
  /// la ultima verificare. Interogările se fac pe rând. Aruncă eroarea doar
  /// dacă nicio parte nu a putut fi verificată.
  Future<List<RezultatParte>> verificaToate({SoapService? soap, DateTime? acum}) async {
    await incarca();
    if (_parti.isEmpty) return [];

    final serviciu = soap ?? SoapService();
    final moment = acum ?? DateTime.now();
    final gasite = <String, List<Dosar>>{};
    Object? ultimaEroare;

    for (final p in _parti) {
      try {
        final r = await serviciu.cautaDosare(
          numeParte: p.nume,
          institutie: p.institutie,
          dataStart: p.dataStart,
        );
        gasite[p.cheie] = r.dosare;
      } catch (e) {
        ultimaEroare = e;
      }
    }
    if (gasite.isEmpty && ultimaEroare != null) throw ultimaEroare;

    await incarca();
    final rezultate = <RezultatParte>[];
    _parti = [
      for (final p in _parti)
        if (gasite[p.cheie] case final dosare?)
          () {
            final noi = <Dosar>[
              for (final d in dosare)
                if (!p.cunoscute.contains(d.cheie)) d,
            ];
            final actualizata = p.copyWith(
              ultimaVerificare: moment,
              cunoscute: {...p.cunoscute, for (final d in noi) d.cheie},
              dosareNoi: [
                for (final d in noi) DosarNouParte(dosar: d, gasitLa: moment),
                ...p.dosareNoi,
              ].take(_maxDosareNoi).toList(),
            );
            if (noi.isNotEmpty) rezultate.add(RezultatParte(actualizata, noi));
            return actualizata;
          }()
        else
          p,
    ];
    await _salveaza();
    return rezultate;
  }
}
