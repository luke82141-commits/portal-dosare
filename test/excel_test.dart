import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/client_service.dart';
import 'package:legal_management_app/services/excel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sedinta _t(
  DateTime zi, {
  String solutie = '',
  String sumar = '',
  String doc = '',
  String nr = '',
}) => Sedinta(
  complet: 'C1',
  data: zi,
  ora: '09:00',
  solutie: solutie,
  solutieSumar: sumar,
  document: doc,
  numarDocument: nr,
);

Dosar _d(String institutie, String stadiu, List<Parte> parti, List<Sedinta> sedinte) => Dosar(
  numar: '4512/281/2025',
  data: stadiu == 'Fond' ? DateTime(2025, 3, 4) : DateTime(2026, 2, 1),
  institutie: institutie,
  obiect: 'pretenții',
  stadiuProcesual: stadiu,
  sectie: 'Civil',
  categorie: 'Civil',
  parti: parti,
  sedinte: sedinte,
);

final _fond = _d(
  'JudecatoriaPLOIESTI',
  'Fond',
  const [
    Parte(nume: 'ALFA CONSTRUCT SRL', calitate: 'Reclamant'),
    Parte(nume: 'BETA LOGISTIC SRL', calitate: 'Pârât'),
  ],
  [
    _t(DateTime(2025, 6, 3), solutie: 'Amână cauza', sumar: 'Amână judecarea cauzei.'),
    _t(
      DateTime(2025, 9, 9),
      solutie: 'Respinge',
      sumar: 'Respinge acțiunea.',
      doc: 'Hotarare',
      nr: '7104/2025',
    ),
  ],
);
final _apel = _d(
  'TribunalulPRAHOVA',
  'Apel',
  const [
    Parte(nume: 'Alfa Construct SRL', calitate: 'Apelant Reclamant'),
    Parte(nume: 'BETA LOGISTIC SRL', calitate: 'Intimat Pârât'),
  ],
  [
    _t(
      DateTime(2026, 3, 10),
      solutie: 'Admite',
      sumar: 'Admite apelul. Schimbă în tot sentința.',
      doc: 'Decizie',
      nr: '388/2026',
    ),
    _t(DateTime(2026, 12, 9)),
  ],
);

DosarSalvat _s(Dosar d) => DosarSalvat(dosar: d, adaugatLa: DateTime(2026));

void main() {
  test('Poziția clientului și rezultatul hotărârii', () {
    expect(pozitie('Apelant Reclamant'), Pozitie.initiator);
    expect(pozitie('Intimat Reclamant'), Pozitie.aparare);
    expect(pozitie('Pârât'), Pozitie.aparare);
    expect(pozitie('Petent'), Pozitie.initiator);
    expect(pozitie('Debitor'), Pozitie.necunoscuta);
    const reclamant = Parte(nume: 'X', calitate: 'Reclamant');
    const parat = Parte(nume: 'Y', calitate: 'Pârât');
    final admite = _t(DateTime(2026), solutie: 'Admite');
    final respinge = _t(DateTime(2026), solutie: 'Respinge');
    expect(rezultatPentruClient(reclamant, admite), 'Favorabil');
    expect(rezultatPentruClient(reclamant, respinge), 'Nefavorabil');
    expect(rezultatPentruClient(parat, respinge), 'Favorabil');
    expect(rezultatPentruClient(parat, _t(DateTime(2026), solutie: 'Admite în parte')), 'Parțial');
    expect(rezultatPentruClient(null, admite), '');
  });

  test('Clientul ales rămâne același în toate fazele', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ClientService.instance;
    await c.incarca();
    await c.comuta(_fond.numar, _fond.parti.first);
    expect(c.parteaClientului(_apel)?.calitate, 'Apelant Reclamant');
    await c.incarca();
    expect(c.esteClient(_apel.numar, _apel.parti.first), isTrue);
  });

  test('Situația dosarelor: un rând pe dosar, soluții pe faze, rezultat', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ClientService.instance;
    await c.incarca();
    await c.comuta(_fond.numar, _fond.parti.first);
    final f = situatiaDosarelor([_s(_fond), _s(_apel)], c, acum: DateTime(2026, 11, 14));
    expect(f.randuri, hasLength(1));
    final r = {for (final (i, h) in f.antet.indexed) h: f.randuri.single[i]};
    expect(r['Nr. crt.'], 1);
    expect(r['Instanța'], 'Tribunalul Prahova');
    expect(r['Stadiul procesual'], 'Apel');
    expect(r['Data înregistrării'], DateTime(2025, 3, 4));
    expect(r['Clientul meu'], 'Alfa Construct SRL (Apelant Reclamant)');
    expect(r['Soluția pe fond'], 'Respinge acțiunea. (Hotărâre 7104/2025 din 09.09.2025)');
    expect(
      r['Soluția în apel'],
      'Admite apelul. Schimbă în tot sentința. (Decizie 388/2026 din 10.03.2026)',
    );
    expect(r['Soluția în recurs'], '');
    expect(r['Rezultat pentru client'], 'Favorabil');
    expect(r['Următorul termen'], DateTime(2026, 12, 9));
  });

  test('Situația termenelor: un rând pe termen, termenul următor la amânare', () {
    final toate = situatiaTermenelor([_s(_fond), _s(_apel)]);
    expect(toate.randuri, hasLength(4));
    final prima = {for (final (i, h) in toate.antet.indexed) h: toate.randuri.first[i]};
    expect(prima['Data termenului'], DateTime(2025, 6, 3));
    expect(prima['Tipul soluției'], 'Amânare');
    expect(prima['Termenul următor (la amânare)'], DateTime(2025, 9, 9));
    expect(situatiaTermenelor([_s(_fond), _s(_apel)], an: 2026).randuri, hasLength(2));
  });

  test('Fișierul .xlsx are cele două foi', () async {
    SharedPreferences.setMockInitialValues({});
    await ClientService.instance.incarca();
    await ClientService.instance.comuta(_fond.numar, _fond.parti.first);
    final date = xlsx([
      situatiaDosarelor([_s(_fond), _s(_apel)], ClientService.instance),
      situatiaTermenelor([_s(_fond), _s(_apel)]),
    ]);
    final zip = ZipDecoder().decodeBytes(date);
    final carte = utf8.decode(zip.findFile('xl/workbook.xml')!.content);
    expect(carte, contains('name="Situația dosarelor"'));
    expect(carte, contains('name="Situația termenelor"'));
    final foaie = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content);
    expect(foaie, contains('Alfa Construct SRL (Apelant Reclamant)'));
    final iesire = Platform.environment['EXCEL_IESIRE'];
    if (iesire != null) File(iesire).writeAsBytesSync(date);
  });
}
