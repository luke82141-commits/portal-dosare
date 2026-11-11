import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/screens/dosare_filtrate_screen.dart';

Dosar _d({
  String numar = '1/3/2026',
  String institutie = 'TribunalulBUCURESTI',
  String stadiu = 'Fond',
  String categorie = 'Civil',
  String sectie = 'Secția a III-a Civilă',
  String obiect = 'pretenții',
  DateTime? data,
  DateTime? modificat,
  List<Parte> parti = const [Parte(nume: 'POPESCU ION', calitate: 'Reclamant')],
  List<Sedinta> sedinte = const [],
}) =>
    Dosar(
      numar: numar,
      data: data ?? DateTime(2026, 3, 10),
      institutie: institutie,
      obiect: obiect,
      stadiuProcesual: stadiu,
      sectie: sectie,
      categorie: categorie,
      dataModificare: modificat,
      parti: parti,
      sedinte: sedinte,
    );

void main() {
  test('filtrul gol lasă să treacă orice dosar', () {
    expect(FiltreDosare().potriveste(_d()), isTrue);
    expect(FiltreDosare().gol, isTrue);
  });

  test('criteriile se combină', () {
    final f = FiltreDosare(categorii: {'Civil'}, stadii: {'Apel'});
    expect(f.potriveste(_d(stadiu: 'Apel')), isTrue);
    expect(f.potriveste(_d(stadiu: 'Fond')), isFalse);
    expect(f.potriveste(_d(stadiu: 'Apel', categorie: 'Penal')), isFalse);
  });

  test('mai multe valori pentru același criteriu: ajunge una', () {
    final f = FiltreDosare(institutii: {'TribunalulBUCURESTI', 'CurteadeApelBUCURESTI'});
    expect(f.potriveste(_d(institutie: 'CurteadeApelBUCURESTI')), isTrue);
    expect(f.potriveste(_d(institutie: 'TribunalulCLUJ')), isFalse);
  });

  test('obiectul și părțile se caută fără diacritice și fără majuscule', () {
    expect(FiltreDosare(obiect: 'pretentii').potriveste(_d()), isTrue);
    expect(FiltreDosare(parte: 'popescu').potriveste(_d()), isTrue);
    expect(FiltreDosare(parte: 'ionescu').potriveste(_d()), isFalse);
  });

  test('perioadele: data dosarului și data modificării', () {
    final martie = DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 31));
    expect(FiltreDosare(inregistrare: martie).potriveste(_d()), isTrue);
    expect(FiltreDosare(inregistrare: martie).potriveste(_d(data: DateTime(2026, 4, 1))), isFalse);
    expect(FiltreDosare(modificare: martie).potriveste(_d()), isFalse);
    expect(FiltreDosare(modificare: martie).potriveste(_d(modificat: DateTime(2026, 3, 31, 15))), isTrue);
  });

  test('pornit din detaliu: anul înregistrării', () {
    final f = FiltreDosare.din(TipFiltru.an, _d());
    expect(f.potriveste(_d(data: DateTime(2026, 12, 31))), isTrue);
    expect(f.potriveste(_d(data: DateTime(2025, 12, 31))), isFalse);
    expect(f.etichete().single.$1, 'Data dosarului: 01.01.2026 – 31.12.2026');
  });
}
