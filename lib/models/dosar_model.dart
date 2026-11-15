import '../utils/instante.dart';

DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Parte {
  final String nume;
  final String calitate;

  const Parte({required this.nume, required this.calitate});

  factory Parte.fromJson(Map<String, dynamic> j) =>
      Parte(nume: j['nume'] ?? '', calitate: j['calitate'] ?? '');

  Map<String, dynamic> toJson() => {'nume': nume, 'calitate': calitate};
}

class Sedinta {
  final String complet;
  final DateTime? data;
  final String ora;
  final String solutie;
  final String solutieSumar;
  final DateTime? dataPronuntare;

  /// Tipul documentului emis (valoare brută de la portal, ex. "incheieredesedinta").
  final String document;
  final String numarDocument;
  final DateTime? dataDocument;

  const Sedinta({
    required this.complet,
    required this.data,
    required this.ora,
    required this.solutie,
    required this.solutieSumar,
    this.dataPronuntare,
    this.document = '',
    this.numarDocument = '',
    this.dataDocument,
  });

  /// True dacă instanța a publicat o soluție pentru acest termen.
  bool get arePronuntare => solutie.isNotEmpty || solutieSumar.isNotEmpty;

  factory Sedinta.fromJson(Map<String, dynamic> j) => Sedinta(
        complet: j['complet'] ?? '',
        data: _data(j['data']),
        ora: j['ora'] ?? '',
        solutie: j['solutie'] ?? '',
        solutieSumar: j['solutieSumar'] ?? '',
        dataPronuntare: _data(j['dataPronuntare']),
        document: j['document'] ?? '',
        numarDocument: j['numarDocument'] ?? '',
        dataDocument: _data(j['dataDocument']),
      );

  Map<String, dynamic> toJson() => {
        'complet': complet,
        'data': data?.toIso8601String(),
        'ora': ora,
        'solutie': solutie,
        'solutieSumar': solutieSumar,
        'dataPronuntare': dataPronuntare?.toIso8601String(),
        'document': document,
        'numarDocument': numarDocument,
        'dataDocument': dataDocument?.toIso8601String(),
      };
}

class CaleAtac {
  final DateTime? dataDeclarare;
  final String parteDeclaratoare;
  final String tip;

  const CaleAtac({
    required this.dataDeclarare,
    required this.parteDeclaratoare,
    required this.tip,
  });

  factory CaleAtac.fromJson(Map<String, dynamic> j) => CaleAtac(
        dataDeclarare: _data(j['dataDeclarare']),
        parteDeclaratoare: j['parteDeclaratoare'] ?? '',
        tip: j['tip'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'dataDeclarare': dataDeclarare?.toIso8601String(),
        'parteDeclaratoare': parteDeclaratoare,
        'tip': tip,
      };
}

class Dosar {
  final String numar;
  final DateTime? data;

  /// Codul instanței așa cum îl întoarce portalul (ex. "JudecatoriaSECTORUL1BUCURESTI").
  /// Pentru afișare folosește [instanta].
  final String institutie;
  final String obiect;
  final String stadiuProcesual;
  final String sectie;
  final String categorie;
  final DateTime? dataModificare;
  final List<Parte> parti;
  final List<Sedinta> sedinte;
  final List<CaleAtac> caiAtac;

  const Dosar({
    required this.numar,
    required this.data,
    required this.institutie,
    required this.obiect,
    required this.stadiuProcesual,
    required this.sectie,
    required this.categorie,
    required this.parti,
    required this.sedinte,
    this.dataModificare,
    this.caiAtac = const [],
  });

  /// Același număr de dosar poate exista la mai multe instanțe (fond, apel,
  /// recurs), deci identificarea se face după număr + instanță.
  String get cheie => '$numar|$institutie';

  /// Numele instanței, lizibil: "Judecătoria Sectorul 1 București".
  String get instanta => numeInstanta(institutie);

  /// Ședințele, de la cea mai recentă la cea mai veche.
  List<Sedinta> get sedinteSortate {
    final l = [...sedinte];
    l.sort((a, b) {
      final da = a.data, db = b.data;
      if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
      return db.compareTo(da);
    });
    return l;
  }

  factory Dosar.fromJson(Map<String, dynamic> j) => Dosar(
        numar: j['numar'] ?? '',
        data: _data(j['data']),
        institutie: j['institutie'] ?? '',
        obiect: j['obiect'] ?? '',
        stadiuProcesual: j['stadiuProcesual'] ?? '',
        sectie: j['sectie'] ?? '',
        categorie: j['categorie'] ?? '',
        dataModificare: _data(j['dataModificare']),
        parti: [for (final p in (j['parti'] as List? ?? [])) Parte.fromJson(p)],
        sedinte: [for (final s in (j['sedinte'] as List? ?? [])) Sedinta.fromJson(s)],
        caiAtac: [for (final c in (j['caiAtac'] as List? ?? [])) CaleAtac.fromJson(c)],
      );

  Map<String, dynamic> toJson() => {
        'numar': numar,
        'data': data?.toIso8601String(),
        'institutie': institutie,
        'obiect': obiect,
        'stadiuProcesual': stadiuProcesual,
        'sectie': sectie,
        'categorie': categorie,
        'dataModificare': dataModificare?.toIso8601String(),
        'parti': [for (final p in parti) p.toJson()],
        'sedinte': [for (final s in sedinte) s.toJson()],
        'caiAtac': [for (final c in caiAtac) c.toJson()],
      };
}

/// O schimbare detectată pe portal la un dosar din bibliotecă.
class Modificare {
  final DateTime detectataLa;
  final String text;

  const Modificare({required this.detectataLa, required this.text});

  factory Modificare.fromJson(Map<String, dynamic> j) => Modificare(
        detectataLa: _data(j['detectataLa']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        text: j['text'] ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'detectataLa': detectataLa.toIso8601String(), 'text': text};
}

/// Un dosar salvat în bibliotecă, împreună cu istoricul schimbărilor detectate.
class DosarSalvat {
  final Dosar dosar;
  final DateTime adaugatLa;
  final DateTime? ultimaVerificare;

  /// Cele mai recente primele.
  final List<Modificare> modificari;

  /// Câte dintre [modificari] nu au fost încă văzute de utilizator.
  final int necitite;

  const DosarSalvat({
    required this.dosar,
    required this.adaugatLa,
    this.ultimaVerificare,
    this.modificari = const [],
    this.necitite = 0,
  });

  DosarSalvat copyWith({
    Dosar? dosar,
    DateTime? ultimaVerificare,
    List<Modificare>? modificari,
    int? necitite,
  }) =>
      DosarSalvat(
        dosar: dosar ?? this.dosar,
        adaugatLa: adaugatLa,
        ultimaVerificare: ultimaVerificare ?? this.ultimaVerificare,
        modificari: modificari ?? this.modificari,
        necitite: necitite ?? this.necitite,
      );

  factory DosarSalvat.fromJson(Map<String, dynamic> j) => DosarSalvat(
        dosar: Dosar.fromJson(j['dosar']),
        adaugatLa: _data(j['adaugatLa']) ?? DateTime.now(),
        ultimaVerificare: _data(j['ultimaVerificare']),
        modificari: [
          for (final m in (j['modificari'] as List? ?? [])) Modificare.fromJson(m),
        ],
        necitite: j['necitite'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'dosar': dosar.toJson(),
        'adaugatLa': adaugatLa.toIso8601String(),
        'ultimaVerificare': ultimaVerificare?.toIso8601String(),
        'modificari': [for (final m in modificari) m.toJson()],
        'necitite': necitite,
      };
}
