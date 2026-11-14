import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/rezumat_service.dart';
import 'package:legal_management_app/services/termene_procedurale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sedinta _s(DateTime data, String ora) =>
    Sedinta(complet: 'C3', data: data, ora: ora, solutie: '', solutieSumar: '');

DosarSalvat _salvat(
  String numar,
  List<Sedinta> sedinte, {
  List<Modificare> modificari = const [],
}) => DosarSalvat(
  dosar: Dosar(
    numar: numar,
    data: DateTime(2026, 1, 1),
    institutie: 'TribunalulPRAHOVA',
    obiect: 'pretenții',
    stadiuProcesual: 'Fond',
    sectie: '',
    categorie: 'Civil',
    parti: const [],
    sedinte: sedinte,
  ),
  adaugatLa: DateTime(2026, 1, 1),
  modificari: modificari,
);

void main() {
  test('Vinerea, „următoarea zi” e lunea', () {
    expect(urmatoareaZiLucratoare(DateTime(2026, 11, 13)), DateTime(2026, 11, 16));
    // Înainte de 30.11 și 1.12, sărbători.
    expect(urmatoareaZiLucratoare(DateTime(2026, 11, 27)), DateTime(2026, 12, 2));
  });

  test('Rezumatul strânge termenele, actualizările și ce expiră', () {
    final acum = DateTime(2026, 11, 13, 7, 40); // vineri
    final salvate = [
      _salvat('1/105/2026', [
        _s(DateTime(2026, 11, 13), '11:00'),
        _s(DateTime(2026, 12, 1), '9:00'),
      ]),
      _salvat(
        '2/105/2026',
        [_s(DateTime(2026, 11, 13), '09:00'), _s(DateTime(2026, 11, 16), '10:00')],
        modificari: [
          Modificare(detectataLa: DateTime(2026, 11, 13, 3), text: 'Termen nou'),
          Modificare(detectataLa: DateTime(2026, 11, 10), text: 'Veche'),
        ],
      ),
    ];
    final procedurale = [
      TermenSalvat(
        id: 'a',
        act: 'Apel (civil)',
        numarDosar: '1/105/2026',
        start: DateTime(2026, 10, 15),
        ultimaZi: DateTime(2026, 11, 16),
      ),
      TermenSalvat(
        id: 'b',
        act: 'Recurs (civil)',
        numarDosar: '',
        start: DateTime(2026, 11, 1),
        ultimaZi: DateTime(2026, 12, 2),
      ),
    ];
    final r = construiesteRezumat(salvate, procedurale, acum: acum);
    expect(r.azi.map((t) => t.dosar.numar), ['2/105/2026', '1/105/2026']);
    expect(r.ziUrmatoare, DateTime(2026, 11, 16));
    expect(r.urmatoare.single.dosar.numar, '2/105/2026');
    expect(r.actualizari.single.modificare.text, 'Termen nou');
    expect(r.procedurale.single.id, 'a');
    expect(numeZiUrmatoare(r), 'Luni');

    final t = textRezumat(r, ziUrm: numeZiUrmatoare(r));
    expect(t.sumar, 'Azi 2 termene · Luni 1 termen · 1 actualizare · 1 termen care expiră');
    expect(t.linii.first, 'Azi:');
    expect(t.linii[1], '• 09:00 · 2/105/2026 · Trib. Prahova · complet C3');
  });

  test('Vine o dată pe zi, după ora aleasă, doar în zilele lucrătoare', () async {
    SharedPreferences.setMockInitialValues({});
    final s = RezumatService.instance;
    await s.incarca();
    expect(s.eTimpul(DateTime(2026, 11, 13, 7, 0)), isFalse);
    expect(s.eTimpul(DateTime(2026, 11, 13, 7, 45)), isTrue);
    expect(s.eTimpul(DateTime(2026, 11, 14, 8)), isFalse); // sâmbătă
    expect(s.eTimpul(DateTime(2026, 12, 1, 8)), isFalse); // Ziua Națională
    await s.marcheazaTrimis(DateTime(2026, 11, 13, 7, 45));
    expect(s.eTimpul(DateTime(2026, 11, 13, 8, 45)), isFalse);
    expect(s.eTimpul(DateTime(2026, 11, 16, 8)), isTrue);
    // Actualizările de luni se numără de vineri, nu doar de 24 de ore.
    expect(s.actualizariDeLa(DateTime(2026, 11, 16, 8)), DateTime(2026, 11, 13, 7, 45));
  });
}
