import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/biblioteca_service.dart';
import 'package:legal_management_app/services/comparator_dosar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dosar dosar({
  String numar = '10/3/2026',
  String institutie = 'TribunalulBUCURESTI',
  String stadiu = 'Fond',
  List<Sedinta> sedinte = const [],
  List<Parte> parti = const [Parte(nume: 'A', calitate: 'Reclamant')],
}) =>
    Dosar(
      numar: numar,
      data: DateTime(2026, 1, 10),
      institutie: institutie,
      obiect: 'pretenții',
      stadiuProcesual: stadiu,
      sectie: 'Secția a III-a Civilă',
      categorie: 'Civil',
      parti: parti,
      sedinte: sedinte,
    );

Sedinta sedinta(int luna, int zi, {String solutie = '', String sumar = '', String ora = '09:00'}) =>
    Sedinta(
      complet: 'C1',
      data: DateTime(2026, luna, zi),
      ora: ora,
      solutie: solutie,
      solutieSumar: sumar,
    );

void main() {
  group('comparaDosare', () {
    test('dosare identice nu produc schimbări', () {
      final d = dosar(sedinte: [sedinta(3, 1, solutie: 'Amână cauza')]);
      expect(comparaDosare(d, Dosar.fromJson(d.toJson())), isEmpty);
    });

    test('pronunțarea la un termen existent este semnalată', () {
      final vechi = dosar(sedinte: [sedinta(3, 1)]);
      final nou = dosar(
        sedinte: [sedinta(3, 1, solutie: 'Admite cererea', sumar: 'Obligă pârâtul.')],
      );
      expect(
        comparaDosare(vechi, nou),
        ['Pronunțare la termenul din 01.03.2026: Admite cererea — Obligă pârâtul.'],
      );
    });

    test('termen nou, oră schimbată, stadiu și părți', () {
      final vechi = dosar(sedinte: [sedinta(3, 1)]);
      final nou = dosar(
        stadiu: 'Apel',
        sedinte: [sedinta(3, 1, ora: '11:30'), sedinta(4, 2)],
        parti: const [
          Parte(nume: 'A', calitate: 'Reclamant'),
          Parte(nume: 'B', calitate: 'Intervenient'),
        ],
      );
      expect(comparaDosare(vechi, nou), [
        'Ora termenului din 01.03.2026: 09:00 → 11:30',
        'Termen nou: 02.04.2026, ora 09:00, complet C1',
        'Stadiu procesual: Fond → Apel',
        'Parte nouă: B (Intervenient)',
      ]);
    });

    test('termen dispărut de pe portal', () {
      final vechi = dosar(sedinte: [sedinta(3, 1), sedinta(4, 2)]);
      final nou = dosar(sedinte: [sedinta(3, 1)]);
      expect(comparaDosare(vechi, nou), ['Termenul din 02.04.2026 nu mai apare pe portal']);
    });
  });

  group('BibliotecaService', () {
    final b = BibliotecaService.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await b.incarca();
    });

    test('salvează, reîncarcă și șterge', () async {
      final d = dosar();
      await b.adauga(d);
      await b.adauga(d);
      expect(b.dosare, hasLength(1));

      await b.incarca();
      expect(b.contine(d.cheie), isTrue);
      expect(b.dosare.single.dosar.instanta, 'Tribunalul București');

      await b.sterge(d.cheie);
      expect(b.dosare, isEmpty);
    });

    test('înregistrează schimbările și le marchează necitite', () async {
      await b.adauga(dosar(sedinte: [sedinta(3, 1)]));
      final nou = dosar(sedinte: [sedinta(3, 1, solutie: 'Respinge cererea')]);

      final rezultate = await b.aplicaActualizari([nou], numereVerificate: {'10/3/2026'});
      expect(rezultate.single.schimbari, hasLength(1));
      expect(b.totalNecitite, 1);
      expect(b.dosare.single.dosar.sedinte.single.solutie, 'Respinge cererea');

      // A doua verificare cu aceleași date nu mai anunță nimic.
      expect(await b.aplicaActualizari([nou], numereVerificate: {'10/3/2026'}), isEmpty);
      expect(b.totalNecitite, 1);

      await b.marcheazaCitit(nou.cheie);
      expect(b.totalNecitite, 0);
      expect(b.dosare.single.modificari, hasLength(1));
    });

    test('dosarul apărut la o instanță nouă este adăugat și anunțat', () async {
      final fond = dosar();
      final apel = dosar(institutie: 'CurteadeApelBUCURESTI', stadiu: 'Apel');
      await b.adauga(fond);

      final rezultate =
          await b.aplicaActualizari([fond, apel], numereVerificate: {'10/3/2026'});
      expect(
        rezultate.single.schimbari.single,
        'Dosarul a fost înregistrat la o nouă instanță: Curtea de Apel București (Apel)',
      );
      expect(b.dosare, hasLength(2));

      // Șters de utilizator: nu mai revine la verificarea următoare.
      await b.sterge(apel.cheie);
      expect(
        await b.aplicaActualizari([fond, apel], numereVerificate: {'10/3/2026'}),
        isEmpty,
      );
      expect(b.dosare, hasLength(1));
    });

    test('un dosar care lipsește din răspuns rămâne neatins', () async {
      final d = dosar(sedinte: [sedinta(3, 1)]);
      await b.adauga(d);
      expect(await b.aplicaActualizari([], numereVerificate: {'10/3/2026'}), isEmpty);
      expect(b.dosare.single.dosar.sedinte, hasLength(1));
    });
  });
}
