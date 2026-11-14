import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/formatare.dart';
import 'raport_service.dart';

// Raportul e descris o singură dată, ca blocuri (titluri, paragrafe,
// tabele), apoi aceleași blocuri se scriu în PDF și în Word. Așa cele două
// fișiere au mereu același conținut.

sealed class Bloc {
  const Bloc();
}

/// Titlu de secțiune: „I. Sinteză”.
class TitluBloc extends Bloc {
  final String text;
  const TitluBloc(this.text);
}

enum StilParagraf { normal, mic, nota }

class ParagrafBloc extends Bloc {
  final String text;
  final StilParagraf stil;

  /// Rămâne pe aceeași pagină cu tabelul de după.
  final bool cuUrmatorul;
  const ParagrafBloc(this.text, {this.stil = StilParagraf.normal, this.cuUrmatorul = false});
}

class TabelBloc extends Bloc {
  final List<String> antet;
  final List<List<String>> randuri;

  /// Lățimile coloanelor, în centimetri (împreună, cel mult 17).
  final List<double> latimi;
  final double marimeText;
  const TabelBloc(this.antet, this.randuri, this.latimi, {this.marimeText = 8.5});
}

const _romane = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
const _indent = '    ';

String titluRaport(Raport r) => 'RAPORT';
String subtitluRaport(Raport r) => 'privind situația dosarelor monitorizate';

/// Rândul de jos al fiecărei pagini.
String subsolRaport(Raport r) =>
    'Portal Dosare · Raport ${r.interval.adjectiv} · ${r.interval.text} · pagina ';

/// Antetul: rândurile de sub titlu.
List<String> detaliiRaport(Raport r) => [
  'Raport ${r.interval.adjectiv} · perioada de referință: ${r.interval.text}',
  'Data întocmirii: ${formateazaData(r.intocmitLa)}, ora '
      '${r.intocmitLa.hour.toString().padLeft(2, '0')}:${r.intocmitLa.minute.toString().padLeft(2, '0')}',
  if (r.beneficiar.isNotEmpty) 'Beneficiar: ${r.beneficiar}',
];

List<Bloc> blocuriRaport(Raport r) {
  final blocuri = <Bloc>[];
  var n = 0;
  void titlu(String t) => blocuri.add(TitluBloc('${_romane[n++]}. $t'));
  void gol(String t) => blocuri.add(ParagrafBloc(t));

  titlu('Sinteză');
  blocuri.add(ParagrafBloc(r.introducere, cuUrmatorul: true));
  blocuri.add(
    TabelBloc(
      ['Indicator', 'Valoare'],
      [
        for (final (eticheta, valoare, sub) in r.indicatori)
          [sub ? '$_indent$eticheta' : eticheta, valoare],
      ],
      [12.5, 4.5],
      marimeText: 10,
    ),
  );

  if (r.anual) {
    titlu('Repartizarea pe luni');
    blocuri.add(
      TabelBloc(
        ['Luna', 'Termene de judecată', 'Hotărâri pronunțate'],
        [
          for (final l in r.peLuni) [l.eticheta, '${l.termene}', '${l.hotarari}'],
          ['Total', '${r.termene.length}', '${r.hotarari.length}'],
        ],
        [7, 5, 5],
        marimeText: 9.5,
      ),
    );
    titlu('Repartizarea pe instanțe');
    blocuri.add(
      TabelBloc(
        ['Instanța', 'Dosare', 'Termene', 'Hotărâri'],
        [
          for (final i in r.peInstante)
            [i.eticheta, '${i.dosare}', '${i.termene}', '${i.hotarari}'],
        ],
        [8.5, 2.8, 2.8, 2.9],
        marimeText: 9.5,
      ),
    );
  } else {
    titlu('Termene de judecată în perioada de referință');
    if (r.termene.isEmpty) {
      gol('În perioada de referință nu au existat termene de judecată în dosarele monitorizate.');
    } else {
      blocuri.add(
        const ParagrafBloc(
          'Termenele sunt prezentate în ordine cronologică, cu soluția pronunțată la fiecare '
          'termen, potrivit mențiunilor publicate de instanță.',
          cuUrmatorul: true,
        ),
      );
      blocuri.add(
        TabelBloc(
          ['Data / ora', 'Nr. dosar', 'Instanța', 'Obiect', 'Părți', 'Soluția la termen'],
          [
            for (final t in r.termene)
              [
                t.dataOra.replaceFirst(', ', '\n'),
                t.dosar.numar,
                t.dosar.instanta,
                scurteaza(t.dosar.obiect, 80),
                t.parti.join('\n'),
                t.sedinta.arePronuntare ? t.solutie : '—',
              ],
          ],
          [2.1, 2.6, 2.6, 2.6, 3.6, 3.5],
        ),
      );
    }
  }

  titlu('Hotărâri pronunțate');
  if (r.hotarari.isEmpty) {
    gol('În perioada de referință nu au fost pronunțate hotărâri în dosarele monitorizate.');
  } else {
    blocuri.add(
      const ParagrafBloc(
        'Termenul de exercitare a căii de atac se calculează potrivit legii, de regulă de la '
        'comunicarea hotărârii.',
        cuUrmatorul: true,
      ),
    );
    blocuri.add(
      TabelBloc(
        ['Data', 'Nr. dosar', 'Instanța', 'Soluția pe scurt', 'Document'],
        [
          for (final h in r.hotarari)
            [
              formateazaData(h.dataHotarare),
              h.dosar.numar,
              h.dosar.instanta,
              h.solutie,
              h.document,
            ],
        ],
        [2.1, 2.8, 3.0, 6.6, 2.5],
      ),
    );
  }

  if (r.caiAtac.isNotEmpty) {
    titlu('Căi de atac declarate');
    blocuri.add(
      TabelBloc(
        ['Data declarării', 'Nr. dosar', 'Instanța', 'Calea de atac', 'Partea declarantă'],
        [
          for (final c in r.caiAtac)
            [
              formateazaData(c.cale.dataDeclarare),
              c.dosar.numar,
              c.dosar.instanta,
              c.cale.tip,
              c.cale.parteDeclaratoare,
            ],
        ],
        [2.5, 2.8, 3.2, 3.5, 5.0],
      ),
    );
  }

  titlu(switch (r.interval.perioada) {
    PerioadaRaport.saptamanal => 'Termene stabilite în săptămâna următoare',
    PerioadaRaport.lunar => 'Termene stabilite în luna următoare',
    PerioadaRaport.anual => 'Termene stabilite la începutul anului următor',
  });
  if (r.urmatoare.isEmpty) {
    gol('Până la data întocmirii nu au fost publicate termene pentru această perioadă.');
  } else {
    blocuri.add(
      TabelBloc(
        ['Data / ora', 'Nr. dosar', 'Instanța', 'Stadiu procesual', 'Complet'],
        [
          for (final t in r.urmatoare)
            [
              t.dataOra,
              t.dosar.numar,
              t.dosar.instanta,
              t.dosar.stadiuProcesual,
              t.sedinta.complet,
            ],
        ],
        [3.4, 3.0, 4.6, 3.2, 2.8],
        marimeText: 9,
      ),
    );
  }

  titlu('Mențiuni');
  for (final m in mentiuniRaport) {
    blocuri.add(ParagrafBloc(m, stil: StilParagraf.mic));
  }
  return blocuri;
}

// ───────────────────────────── PDF ─────────────────────────────

const _primar = PdfColor.fromInt(0xFF1F3A93);
const _auriu = PdfColor.fromInt(0xFFB8892F);
const _gri = PdfColor.fromInt(0xFF5A6273);
const _dunga = PdfColor.fromInt(0xFFF2F4F9);

/// Fonturile PDF-ului; în aplicație vin din assets/fonts (au diacritice).
class FonturiRaport {
  final pw.Font normal;
  final pw.Font bold;
  final pw.Font italic;
  const FonturiRaport(this.normal, this.bold, this.italic);
}

Future<Uint8List> raportPdf(Raport r, FonturiRaport f) {
  final doc = pw.Document(
    title: 'Raport ${r.interval.adjectiv} ${r.interval.text}',
    author: 'Portal Dosare',
  );
  const cm = PdfPageFormat.cm;

  pw.Widget bloc(Bloc b) => switch (b) {
    TitluBloc(:final text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: f.bold, fontSize: 12.5, color: _primar),
      ),
    ),
    ParagrafBloc(:final text, :final stil) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.justify,
        style: pw.TextStyle(fontSize: stil == StilParagraf.normal ? 11 : 10, lineSpacing: 1.5),
      ),
    ),
    TabelBloc(:final antet, :final randuri, :final latimi, :final marimeText) => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
      columnWidths: {for (final (i, w) in latimi.indexed) i: pw.FixedColumnWidth(w * cm)},
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _primar),
          children: [
            for (final h in antet)
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(font: f.bold, fontSize: marimeText, color: PdfColors.white),
                ),
              ),
          ],
        ),
        for (final (k, rand) in randuri.indexed)
          pw.TableRow(
            decoration: k.isOdd ? const pw.BoxDecoration(color: _dunga) : null,
            children: [
              for (final c in rand)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(c, style: pw.TextStyle(fontSize: marimeText)),
                ),
            ],
          ),
      ],
    ),
  };

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 2 * cm,
          marginRight: 2 * cm,
          marginTop: 1.8 * cm,
          marginBottom: 1.8 * cm,
        ),
        theme: pw.ThemeData.withFont(base: f.normal, bold: f.bold, italic: f.italic),
      ),
      footer: (context) => pw.Center(
        child: pw.Text(
          '${subsolRaport(r)}${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 8, color: _gri),
        ),
      ),
      build: (context) => [
        pw.Text(
          'PORTAL DOSARE',
          style: pw.TextStyle(font: f.bold, fontSize: 9, color: _auriu),
        ),
        pw.Text(
          titluRaport(r),
          style: pw.TextStyle(font: f.bold, fontSize: 20, color: _primar),
        ),
        pw.Text(
          subtitluRaport(r),
          style: pw.TextStyle(font: f.bold, fontSize: 14, color: _primar),
        ),
        pw.SizedBox(height: 4),
        for (final d in detaliiRaport(r)) pw.Text(d, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        for (final b in blocuriRaport(r)) bloc(b),
      ],
    ),
  );
  return doc.save();
}

// ───────────────────────────── Word ─────────────────────────────

String _x(String s) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(s).replaceAll('"', '&quot;');

String _run(
  String text, {
  bool bold = false,
  bool italic = false,
  double size = 11,
  String? culoare,
}) {
  final linii = text.split('\n');
  final continut = [
    for (final (i, l) in linii.indexed)
      '${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${_x(l)}</w:t>',
  ].join();
  return '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
      '${culoare != null ? '<w:color w:val="$culoare"/>' : ''}'
      '<w:sz w:val="${(size * 2).round()}"/><w:szCs w:val="${(size * 2).round()}"/></w:rPr>'
      '$continut</w:r>';
}

String _par(
  String runs, {
  String align = 'left',
  int dupa = 4,
  int inainte = 0,
  bool cuUrmatorul = false,
}) =>
    '<w:p><w:pPr>${cuUrmatorul ? '<w:keepNext/>' : ''}'
    '<w:spacing w:before="${inainte * 20}" w:after="${dupa * 20}"/><w:jc w:val="$align"/></w:pPr>$runs</w:p>';

String _tabel(TabelBloc t) {
  int tw(double cm) => (cm * 567).round();
  String celula(String text, double latime, {bool antet = false, bool dunga = false}) {
    final fond = antet ? '1F3A93' : (dunga ? 'F2F4F9' : null);
    return '<w:tc><w:tcPr><w:tcW w:w="${tw(latime)}" w:type="dxa"/>'
        '${fond != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fond"/>' : ''}</w:tcPr>'
        '${_par(_run(text, bold: antet, size: t.marimeText, culoare: antet ? 'FFFFFF' : null), dupa: 1)}</w:tc>';
  }

  final b = StringBuffer()
    ..write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>')
    ..write('<w:jc w:val="center"/><w:tblLayout w:type="fixed"/><w:tblBorders>')
    ..write(
      [
        for (final s in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'])
          '<w:$s w:val="single" w:sz="4" w:space="0" w:color="808080"/>',
      ].join(),
    )
    ..write('</w:tblBorders></w:tblPr><w:tblGrid>')
    ..write([for (final w in t.latimi) '<w:gridCol w:w="${tw(w)}"/>'].join())
    ..write('</w:tblGrid>')
    ..write('<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>')
    ..write([for (final (i, h) in t.antet.indexed) celula(h, t.latimi[i], antet: true)].join())
    ..write('</w:tr>');
  for (final (k, rand) in t.randuri.indexed) {
    b
      ..write('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
      ..write([for (final (i, c) in rand.indexed) celula(c, t.latimi[i], dunga: k.isOdd)].join())
      ..write('</w:tr>');
  }
  b.write('</w:tbl>');
  return b.toString();
}

const _ns =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

Uint8List raportDocx(Raport r) {
  final corp = StringBuffer()
    ..write(_par(_run('PORTAL DOSARE', bold: true, size: 9, culoare: 'B8892F'), dupa: 0))
    ..write(_par(_run(titluRaport(r), bold: true, size: 20, culoare: '1F3A93'), dupa: 0))
    ..write(_par(_run(subtitluRaport(r), bold: true, size: 14, culoare: '1F3A93'), dupa: 4));
  for (final d in detaliiRaport(r)) {
    corp.write(_par(_run(d), dupa: 0));
  }
  for (final b in blocuriRaport(r)) {
    corp.write(switch (b) {
      TitluBloc(:final text) => _par(
        _run(text, bold: true, size: 12.5, culoare: '1F3A93'),
        inainte: 14,
        dupa: 6,
        cuUrmatorul: true,
      ),
      ParagrafBloc(:final text, :final stil, :final cuUrmatorul) => _par(
        _run(text, size: stil == StilParagraf.normal ? 11 : 10),
        align: 'both',
        cuUrmatorul: cuUrmatorul,
      ),
      TabelBloc() => _tabel(b),
    });
  }

  final document =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document $_ns><w:body>$corp'
      '<w:sectPr><w:footerReference w:type="default" r:id="rIdSubsol"/>'
      '<w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1021" w:right="1134" w:bottom="1021" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  final subsol =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr $_ns><w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '${_run(subsolRaport(r), size: 8, culoare: '5A6273')}'
      '<w:r><w:rPr><w:color w:val="5A6273"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:rPr><w:color w:val="5A6273"/><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:rPr><w:color w:val="5A6273"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:rPr><w:color w:val="5A6273"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r>'
      '<w:r><w:rPr><w:color w:val="5A6273"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>'
      '</w:p></w:ftr>';

  const stiluri =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="ro-RO"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
      '</w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
      '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/>'
      '<w:tblPr><w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
      '<w:bottom w:w="40" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
      '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/></w:style>'
      '</w:styles>';

  const tipuri =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '</Types>';

  const relatii =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  const relatiiDocument =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStiluri" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rIdSubsol" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
      '</Relationships>';

  final arhiva = Archive();
  void adauga(String cale, String text) {
    final date = utf8.encode(text);
    arhiva.addFile(ArchiveFile(cale, date.length, date));
  }

  adauga('[Content_Types].xml', tipuri);
  adauga('_rels/.rels', relatii);
  adauga('word/document.xml', document);
  adauga('word/styles.xml', stiluri);
  adauga('word/footer1.xml', subsol);
  adauga('word/_rels/document.xml.rels', relatiiDocument);
  return Uint8List.fromList(ZipEncoder().encode(arhiva));
}
