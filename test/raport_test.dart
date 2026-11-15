import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/raport_export.dart';
import 'package:legal_management_app/services/raport_service.dart';
import 'package:pdf/widgets.dart' as pw;

Sedinta _t(
  DateTime zi, {
  String ora = '09:00',
  String solutie = '',
  String sumar = '',
  String document = '',
  String nr = '',
}) => Sedinta(
  complet: 'C1',
  data: zi,
  ora: ora,
  solutie: solutie,
  solutieSumar: sumar,
  document: document,
  numarDocument: nr,
);

DosarSalvat _s(
  String numar,
  List<Sedinta> sedinte, {
  String institutie = 'TribunalulPRAHOVA',
  List<CaleAtac> caiAtac = const [],
}) => DosarSalvat(
  dosar: Dosar(
    numar: numar,
    data: DateTime(2026, 1, 1),
    institutie: institutie,
    obiect: 'pretenții',
    stadiuProcesual: 'Fond',
    sectie: '',
    categorie: 'Civil',
    parti: const [
      Parte(nume: 'ALFA CONSTRUCT SRL', calitate: 'Reclamant'),
      Parte(nume: 'BETA LOGISTIC SRL', calitate: 'Pârât'),
    ],
    sedinte: sedinte,
    caiAtac: caiAtac,
  ),
  adaugatLa: DateTime(2026, 1, 1),
);

final _dosare = [
  _s('1/105/2026', [
    _t(
      DateTime(2026, 11, 3),
      solutie: 'Amână cauza',
      sumar: 'Amână judecarea cauzei.',
    ),
    _t(
      DateTime(2026, 11, 26),
      solutie: 'Admite în parte',
      sumar: 'Admite în parte acțiunea. Obligă pârâta la plata sumei de 10.000 lei.',
      document: 'Hotarare',
      nr: '1290/2026',
    ),
    _t(DateTime(2026, 12, 8), ora: '10:00'),
  ]),
  _s(
    '2/281/2026',
    [
      _t(
        DateTime(2026, 11, 12),
        solutie: 'Respinge',
        sumar: 'Respinge plângerea ca neîntemeiată.',
      ),
      _t(DateTime(2027, 1, 14)),
    ],
    institutie: 'JudecatoriaPLOIESTI',
    caiAtac: [
      CaleAtac(
        dataDeclarare: DateTime(2026, 11, 20),
        parteDeclaratoare: 'Popescu Andrei',
        tip: 'Apel',
      ),
    ],
  ),
  _s('3/42/2026', [
    _t(
      DateTime(2026, 3, 10),
      solutie: 'Admite',
      sumar: 'Admite acțiunea.',
      document: 'Hotarare',
    ),
  ], institutie: 'CurteadeApelPLOIESTI'),
];

void main() {
  test('Perioadele: săptămâna de luni, luna, anul, cu navigare', () {
    final s = IntervalRaport.pentru(
      PerioadaRaport.saptamanal,
      DateTime(2026, 11, 14),
    );
    expect(s.text, '09.11.2026 – 15.11.2026');
    expect(s.urmator.text, '16.11.2026 – 22.11.2026');
    final l = IntervalRaport.pentru(
      PerioadaRaport.lunar,
      DateTime(2026, 12, 31),
    );
    expect(l.eticheta, 'Decembrie 2026');
    expect(l.urmator.eticheta, 'Ianuarie 2027');
    expect(l.precedent.text, '01.11.2026 – 30.11.2026');
    expect(
      IntervalRaport.pentru(PerioadaRaport.anual, DateTime(2026, 5, 5)).text,
      '01.01.2026 – 31.12.2026',
    );
  });

  test('Felul soluției, cu sau fără diacritice', () {
    expect(
      tipSolutie(_t(DateTime(2026), solutie: 'Admite în parte')),
      TipSolutie.admiteInParte,
    );
    expect(
      tipSolutie(_t(DateTime(2026), sumar: 'Admite in parte cererea')),
      TipSolutie.admiteInParte,
    );
    expect(
      tipSolutie(_t(DateTime(2026), solutie: 'Admisă')),
      TipSolutie.admite,
    );
    expect(
      tipSolutie(_t(DateTime(2026), solutie: 'Respinge')),
      TipSolutie.respinge,
    );
    expect(
      tipSolutie(_t(DateTime(2026), solutie: 'Amână pronunţarea')),
      TipSolutie.amanare,
    );
    expect(esteHotarare(_t(DateTime(2026), solutie: 'Amână cauza')), isFalse);
    expect(
      esteHotarare(
        _t(DateTime(2026), solutie: 'Suspendă', document: 'Incheiere'),
      ),
      isFalse,
    );
    expect(
      esteHotarare(_t(DateTime(2026), solutie: 'Perimă', document: 'Sentinta')),
      isTrue,
    );
  });

  test('Raportul lunar: termene, hotărâri, căi de atac, termene următoare', () {
    final r = construiesteRaport(
      _dosare,
      IntervalRaport.pentru(PerioadaRaport.lunar, DateTime(2026, 11, 1)),
      acum: DateTime(2026, 12, 1, 8),
    );
    expect(
      [for (final t in r.termene) t.dosar.numar],
      ['1/105/2026', '2/281/2026', '1/105/2026'],
    );
    expect(r.amanari, 1);
    expect(
      [for (final h in r.hotarari) h.dosar.numar],
      ['2/281/2026', '1/105/2026'],
    );
    expect(r.hotarari.last.document, 'Hotărâre 1290/2026');
    expect(r.caiAtac.single.cale.tip, 'Apel');
    expect([for (final t in r.urmatoare) t.dataOra], ['08.12.2026, 10:00']);
    expect(
      r.indicatori.map((i) => '${i.$1}=${i.$2}'),
      containsAll([
        'Dosare monitorizate la data întocmirii=3',
        'Hotărâri pronunțate=2',
        'din care: admite în parte=1',
        'din care: respinge=1',
      ]),
    );
    expect(
      r.introducere,
      startsWith(
        'În perioada de referință au fost monitorizate 3 dosare, aflate pe rolul a 3 instanțe.',
      ),
    );
    expect(numeFisierRaport(r, 'pdf'), 'Raport lunar 2026-11.pdf');
  });

  test('„de” după 20: 3 dosare, 42 de dosare, 101 dosare', () {
    expect(numarCu(3, 'dosare'), '3 dosare');
    expect(numarCu(19, 'dosare'), '19 dosare');
    expect(numarCu(42, 'dosare'), '42 de dosare');
    expect(numarCu(101, 'dosare'), '101 dosare');
    expect(numarCu(200, 'dosare'), '200 de dosare');
  });

  test('Raportul anual are repartizarea pe luni și pe instanțe', () {
    final r = construiesteRaport(
      _dosare,
      IntervalRaport.pentru(PerioadaRaport.anual, DateTime(2026)),
    );
    expect(r.peLuni, hasLength(12));
    expect(r.peLuni[10].termene, 3);
    expect(r.peLuni[2].hotarari, 1);
    expect(r.peInstante, hasLength(3));
    expect([for (final t in r.urmatoare) t.dosar.numar], ['2/281/2026']);
    final titluri = [
      for (final b in blocuriRaport(r))
        if (b is TitluBloc) b.text,
    ];
    expect(titluri, [
      'I. Sinteză',
      'II. Repartizarea pe luni',
      'III. Repartizarea pe instanțe',
      'IV. Hotărâri pronunțate',
      'V. Căi de atac declarate',
      'VI. Termene stabilite la începutul anului următor',
      'VII. Mențiuni',
    ]);
  });

  test('Se creează PDF-ul și documentul Word', () async {
    pw.Font font(String n) => pw.Font.ttf(
      File('assets/fonts/LiberationSerif-$n.ttf')
          .readAsBytesSync()
          .buffer
          .asByteData(),
    );
    final fonturi = FonturiRaport(
      font('Regular'),
      font('Bold'),
      font('Italic'),
    );
    final iesire = Platform.environment['RAPORT_IESIRE'];
    for (final perioada in PerioadaRaport.values) {
      final r = construiesteRaport(
        _dosare,
        IntervalRaport.pentru(perioada, DateTime(2026, 11, 12)),
        beneficiar: 'Cabinet de avocat Exemplu',
        acum: DateTime(2026, 12, 1, 8),
      );
      final pdf = await raportPdf(r, fonturi);
      expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
      final docx = raportDocx(r);
      final zip = ZipDecoder().decodeBytes(docx);
      final document = utf8.decode(zip.findFile('word/document.xml')!.content);
      expect(document, contains('privind situația dosarelor monitorizate'));
      expect(document, contains('Cabinet de avocat Exemplu'));
      if (iesire != null) {
        File('$iesire/${numeFisierRaport(r, 'pdf')}').writeAsBytesSync(pdf);
        File('$iesire/${numeFisierRaport(r, 'docx')}').writeAsBytesSync(docx);
      }
    }
  });
}
