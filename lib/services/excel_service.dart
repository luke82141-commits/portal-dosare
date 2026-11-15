import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import 'client_service.dart';
import 'raport_service.dart';
import 'statistici_service.dart' show numeSolutie;

// ───────────────────── Conținutul celor două foi ─────────────────────

/// O foaie de calcul: antet, rânduri (text, număr întreg, dată sau null) și
/// lățimea coloanelor (în caractere).
class Foaie {
  final String nume;
  final List<String> antet;
  final List<List<Object?>> randuri;
  final List<double> latimi;
  const Foaie(this.nume, this.antet, this.randuri, this.latimi);
}

enum Faza { fond, apel, recurs, alta }

String _fara(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ăâ]'), 'a')
    .replaceAll('î', 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't');

Faza fazaDosar(Dosar d) {
  final s = _fara(d.stadiuProcesual);
  if (s.contains('recurs')) return Faza.recurs;
  if (s.contains('apel')) return Faza.apel;
  if (s.contains('fond')) return Faza.fond;
  return Faza.alta;
}

/// Ultima hotărâre a dosarului (într-o fază), dacă există.
Sedinta? ultimaHotarare(Dosar d) {
  Sedinta? h;
  for (final s in d.sedinte) {
    if (!esteHotarare(s)) continue;
    final z = s.dataPronuntare ?? s.data;
    final hz = h?.dataPronuntare ?? h?.data;
    if (h == null || (z != null && (hz == null || z.isAfter(hz)))) h = s;
  }
  return h;
}

/// „Admite în parte. Obligă pârâta… (Hotărâre 1290/2026 din 26.11.2026)”.
String descriereHotarare(Sedinta h) {
  final text = h.solutieSumar.isNotEmpty ? h.solutieSumar : h.solutie;
  final doc = documentSedinta(h);
  final data = formateazaData(h.dataPronuntare ?? h.data);
  final detalii = [if (doc.isNotEmpty) doc, if (data.isNotEmpty) 'din $data'].join(' ');
  return [scurteaza(text, 300), if (detalii.isNotEmpty) '($detalii)'].join(' ');
}

String _parti(Dosar d) =>
    [for (final p in d.parti) p.calitate.isEmpty ? p.nume : '${p.calitate}: ${p.nume}'].join('\n');

/// Foaia „Situația dosarelor”: un rând pentru fiecare dosar (după număr),
/// cu soluțiile din fiecare fază urmărită.
Foaie situatiaDosarelor(List<DosarSalvat> salvate, ClientService clienti, {DateTime? acum}) {
  final grupuri = <String, List<Dosar>>{};
  for (final s in salvate) {
    grupuri.putIfAbsent(s.dosar.numar, () => []).add(s.dosar);
  }
  final randuri = <List<Object?>>[];
  var nr = 0;
  for (final g in grupuri.values) {
    // Faza cea mai avansată dă instanța, stadiul și părțile de pe rând.
    g.sort((a, b) => fazaDosar(a).index.compareTo(fazaDosar(b).index));
    final curent =
        [
          for (final d in g)
            if (fazaDosar(d) != Faza.alta) d,
        ].lastOrNull ??
        g.last;
    String solutie(Faza f) {
      for (final d in g.reversed) {
        if (fazaDosar(d) == f || (f == Faza.fond && fazaDosar(d) == Faza.alta)) {
          final h = ultimaHotarare(d);
          if (h != null) return descriereHotarare(h);
        }
      }
      return '';
    }

    // Rezultatul pentru client: după ultima hotărâre, în faza cea mai avansată.
    var rezultat = '';
    for (final d in g.reversed) {
      final h = ultimaHotarare(d);
      if (h == null) continue;
      rezultat = rezultatPentruClient(clienti.parteaClientului(d), h);
      break;
    }
    final client = clienti.parteaClientului(curent);
    final inregistrat = [
      for (final d in g)
        if (d.data != null) d.data!,
    ]..sort();
    final urmator = [
      for (final d in g)
        if (urmatorulTermenDin(d, acum: acum) case final t?) t,
    ]..sort();

    randuri.add([
      ++nr,
      curent.numar,
      inregistrat.firstOrNull,
      curent.instanta,
      curent.sectie,
      curent.categorie,
      curent.obiect,
      curent.stadiuProcesual,
      _parti(curent),
      client == null
          ? ''
          : '${client.nume}${client.calitate.isEmpty ? '' : ' (${client.calitate})'}',
      solutie(Faza.fond),
      solutie(Faza.apel),
      solutie(Faza.recurs),
      rezultat,
      urmator.firstOrNull,
    ]);
  }
  return Foaie(
    'Situația dosarelor',
    const [
      'Nr. crt.',
      'Nr. dosar',
      'Data înregistrării',
      'Instanța',
      'Secția',
      'Materia',
      'Obiectul',
      'Stadiul procesual',
      'Părțile',
      'Clientul meu',
      'Soluția pe fond',
      'Soluția în apel',
      'Soluția în recurs',
      'Rezultat pentru client',
      'Următorul termen',
    ],
    randuri,
    const [7, 16, 12, 24, 14, 12, 28, 14, 36, 24, 40, 40, 40, 13, 12],
  );
}

DateTime? urmatorulTermenDin(Dosar d, {DateTime? acum}) {
  final azi = acum ?? DateTime.now();
  final zi = DateTime(azi.year, azi.month, azi.day);
  final viitoare = [
    for (final s in d.sedinte)
      if (s.data != null && !s.data!.isBefore(zi) && !s.arePronuntare) s.data!,
  ]..sort();
  return viitoare.firstOrNull;
}

/// Foaia „Situația termenelor”: un rând pentru fiecare termen. [an] null =
/// toate termenele.
Foaie situatiaTermenelor(List<DosarSalvat> salvate, {int? an}) {
  final termene = <(Dosar, Sedinta)>[];
  for (final s in salvate) {
    for (final t in s.dosar.sedinte) {
      if (t.data == null || (an != null && t.data!.year != an)) continue;
      termene.add((s.dosar, t));
    }
  }
  termene.sort((a, b) => RandTermen(a.$1, a.$2).moment.compareTo(RandTermen(b.$1, b.$2).moment));

  DateTime? termenUlterior(Dosar d, Sedinta t) {
    final dupa = [
      for (final s in d.sedinte)
        if (s.data != null && s.data!.isAfter(t.data!)) s.data!,
    ]..sort();
    return dupa.firstOrNull;
  }

  return Foaie(
    'Situația termenelor',
    const [
      'Nr. crt.',
      'Data termenului',
      'Ora',
      'Nr. dosar',
      'Instanța',
      'Părțile',
      'Complet',
      'Tipul soluției',
      'Soluția pe scurt',
      'Termenul următor (la amânare)',
    ],
    [
      for (final (i, (d, t)) in termene.indexed)
        [
          i + 1,
          t.data,
          t.ora,
          d.numar,
          d.instanta,
          _parti(d),
          t.complet,
          t.arePronuntare ? numeSolutie(tipSolutie(t)) : '',
          scurteaza(t.solutieSumar.isNotEmpty ? t.solutieSumar : t.solutie, 300),
          tipSolutie(t) == TipSolutie.amanare ? termenUlterior(d, t) : null,
        ],
    ],
    const [7, 12, 7, 16, 24, 36, 9, 15, 50, 14],
  );
}

// ───────────────────────────── XLSX ─────────────────────────────

String _x(String s) =>
    const HtmlEscape(HtmlEscapeMode.element)
        .convert(s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''))
        .replaceAll('"', '&quot;');

String _coloana(int i) {
  var n = i + 1, s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Zilele de la 30.12.1899, cum ține Excel datele.
int _serialData(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;

// Stiluri (cellXfs): 0 implicit, 1 antet, 2 text, 3 dată, 4 număr.
const _stiluri =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd.mm.yyyy"/></numFmts>'
    '<fonts count="2">'
    '<font><sz val="10"/><name val="Calibri"/></font>'
    '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="3"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF1F3A93"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2"><border/>'
    '<border><left style="thin"><color rgb="FFD0D4DE"/></left><right style="thin"><color rgb="FFD0D4DE"/></right>'
    '<top style="thin"><color rgb="FFD0D4DE"/></top><bottom style="thin"><color rgb="FFD0D4DE"/></bottom></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment vertical="center" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
    '<alignment vertical="top" wrapText="1"/></xf>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center" vertical="top"/></xf>'
    '<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center" vertical="top"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String _foaieXml(Foaie f) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
    ..write('<sheetViews><sheetView workbookViewId="0">')
    ..write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>')
    ..write('</sheetView></sheetViews><cols>');
  for (final (i, w) in f.latimi.indexed) {
    b.write('<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>');
  }
  b.write('</cols><sheetData>');

  void rand(int r, List<Object?> valori, {bool antet = false}) {
    b.write('<row r="$r"${antet ? ' ht="30" customHeight="1"' : ''}>');
    for (final (i, v) in valori.indexed) {
      final ref = '${_coloana(i)}$r';
      if (antet) {
        b.write('<c r="$ref" s="1" t="inlineStr"><is><t>${_x('$v')}</t></is></c>');
      } else if (v is int) {
        b.write('<c r="$ref" s="4"><v>$v</v></c>');
      } else if (v is DateTime) {
        b.write('<c r="$ref" s="3"><v>${_serialData(v)}</v></c>');
      } else if (v == null || (v is String && v.isEmpty)) {
        b.write('<c r="$ref" s="2"/>');
      } else {
        b.write(
          '<c r="$ref" s="2" t="inlineStr"><is><t xml:space="preserve">${_x('$v')}</t></is></c>',
        );
      }
    }
    b.write('</row>');
  }

  rand(1, f.antet, antet: true);
  for (final (k, r) in f.randuri.indexed) {
    rand(k + 2, r);
  }
  final ultima = _coloana(f.antet.length - 1);
  b
    ..write('</sheetData>')
    ..write('<autoFilter ref="A1:$ultima${f.randuri.length + 1}"/>')
    ..write(
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>',
    )
    ..write('<pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/>')
    ..write('</worksheet>');
  return b.toString();
}

/// Fișierul .xlsx cu foile date.
Uint8List xlsx(List<Foaie> foi) {
  final arhiva = Archive();
  void adauga(String cale, String text) {
    final date = utf8.encode(text);
    arhiva.addFile(ArchiveFile(cale, date.length, date));
  }

  adauga(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= foi.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  adauga(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  adauga(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (final (i, f) in foi.indexed) '<sheet name="${_x(f.nume)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets>'
        '<definedNames>${[for (final (i, f) in foi.indexed) '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" hidden="1">\'${_x(f.nume)}\'!\$A\$1:\$${_coloana(f.antet.length - 1)}\$${f.randuri.length + 1}</definedName>'].join()}</definedNames>'
        '</workbook>',
  );
  adauga(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= foi.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rIdStiluri" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
  );
  adauga('xl/styles.xml', _stiluri);
  for (final (i, f) in foi.indexed) {
    adauga('xl/worksheets/sheet${i + 1}.xml', _foaieXml(f));
  }
  return Uint8List.fromList(ZipEncoder().encode(arhiva));
}
