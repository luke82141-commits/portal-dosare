import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'act_structura.dart';
import 'legislatie_service.dart';

// Actul normativ ca PDF și Word, cu aceeași așezare ca în aplicație:
// titlurile și capitolele centrate, articolele cu denumirea îngroșată,
// alineatele cu numărul îngroșat, notele de modificare mici și cursive.

const _primar = PdfColor.fromInt(0xFF1F3A93);
const _gri = PdfColor.fromInt(0xFF5A6273);

String numeFisierAct(ActNormativ a, String extensie) {
  final baza = fataDiacritice(a.denumireScurta)
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${baza.isEmpty ? 'Act normativ' : baza}.$extensie';
}

List<String> _detalii(ActNormativ a) => [
  if (a.emitent.isNotEmpty) 'Emitent: ${a.emitent}',
  if (a.publicatie.isNotEmpty) 'Publicat în: ${a.publicatie}',
  if (a.dataVigoare != null)
    'În vigoare din: ${a.dataVigoare!.day.toString().padLeft(2, '0')}.'
        '${a.dataVigoare!.month.toString().padLeft(2, '0')}.${a.dataVigoare!.year}',
  if (a.linkHtml.isNotEmpty) 'Sursa: ${a.linkHtml}',
];

const _avertisment =
    'Text preluat din Portalul Legislativ al Ministerului Justiției (legislatie.just.ro). '
    'Are caracter informativ; forma oficială este cea publicată în Monitorul Oficial.';

/// PDF-ul actului. Fonturile (cu diacritice) se dau ca octeți, ca funcția să
/// poată rula în alt isolate.
Future<Uint8List> actPdf(
  ActNormativ a,
  List<BlocAct> blocuri, {
  required Uint8List fontNormal,
  required Uint8List fontBold,
  required Uint8List fontItalic,
}) {
  final normal = pw.Font.ttf(ByteData.sublistView(fontNormal));
  final bold = pw.Font.ttf(ByteData.sublistView(fontBold));
  final italic = pw.Font.ttf(ByteData.sublistView(fontItalic));
  final doc = pw.Document(title: a.denumireScurta, author: 'Portal Dosare');
  const cm = PdfPageFormat.cm;
  const corp = pw.TextStyle(fontSize: 11, lineSpacing: 2);

  pw.Widget bloc(BlocAct b) => switch (b.tip) {
    TipBloc.structura => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Column(
        children: [
          pw.Text(
            b.eticheta,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 12.5, color: _primar),
          ),
          if (b.titlu.isNotEmpty)
            pw.Text(
              b.titlu,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 12, color: _primar),
            ),
        ],
      ),
    ),
    TipBloc.articol => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: b.eticheta,
              style: pw.TextStyle(font: bold, fontSize: 11.5, color: _primar),
            ),
            if (b.titlu.isNotEmpty)
              pw.TextSpan(
                text: ' - ${b.titlu}',
                style: pw.TextStyle(font: bold, fontSize: 11.5, color: _primar),
              ),
          ],
        ),
      ),
    ),
    TipBloc.alineat || TipBloc.litera => pw.Padding(
      padding: pw.EdgeInsets.only(
        left: b.tip == TipBloc.litera ? 16 : 0,
        bottom: 3,
      ),
      child: pw.RichText(
        textAlign: pw.TextAlign.justify,
        text: pw.TextSpan(
          style: corp,
          children: [
            pw.TextSpan(
              text: '${b.eticheta} ',
              style: pw.TextStyle(font: bold),
            ),
            pw.TextSpan(text: b.text),
          ],
        ),
      ),
    ),
    TipBloc.nota => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Paragraph(
        text: b.text,
        style: pw.TextStyle(font: italic, fontSize: 9, color: _gri),
        margin: pw.EdgeInsets.zero,
      ),
    ),
    TipBloc.text => pw.Paragraph(
      text: b.text,
      textAlign: pw.TextAlign.justify,
      style: corp,
      margin: const pw.EdgeInsets.only(bottom: 3),
    ),
  };

  doc.addPage(
    pw.MultiPage(
      maxPages: 5000,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 2 * cm,
          marginRight: 2 * cm,
          marginTop: 1.8 * cm,
          marginBottom: 1.8 * cm,
        ),
        theme: pw.ThemeData.withFont(base: normal, bold: bold, italic: italic),
      ),
      footer: (context) => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              a.denumireScurta,
              style: const pw.TextStyle(fontSize: 8, color: _gri),
            ),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _gri),
          ),
        ],
      ),
      build: (context) => [
        pw.Text(
          a.titlu.isEmpty ? a.denumireScurta : a.titlu,
          style: pw.TextStyle(
            font: bold,
            fontSize: 15,
            color: _primar,
            lineSpacing: 2,
          ),
        ),
        pw.SizedBox(height: 6),
        for (final d in _detalii(a))
          pw.Text(d, style: const pw.TextStyle(fontSize: 9.5, color: _gri)),
        pw.SizedBox(height: 4),
        pw.Text(
          _avertisment,
          style: pw.TextStyle(font: italic, fontSize: 8.5, color: _gri),
        ),
        pw.Divider(color: _primar, thickness: 0.8),
        for (final b in blocuri) bloc(b),
      ],
    ),
  );
  return doc.save();
}

// ───────────────────────────── Word ─────────────────────────────

String _x(String s) =>
    const HtmlEscape(HtmlEscapeMode.element)
        .convert(s)
        .replaceAll('"', '&quot;');

String _run(
  String text, {
  bool bold = false,
  bool italic = false,
  double size = 11,
  String? culoare,
}) =>
    '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
    '${culoare != null ? '<w:color w:val="$culoare"/>' : ''}'
    '<w:sz w:val="${(size * 2).round()}"/><w:szCs w:val="${(size * 2).round()}"/></w:rPr>'
    '<w:t xml:space="preserve">${_x(text)}</w:t></w:r>';

String _par(
  String runs, {
  String align = 'left',
  int dupa = 4,
  int inainte = 0,
  int indent = 0,
  bool cuUrmatorul = false,
}) =>
    '<w:p><w:pPr>${cuUrmatorul ? '<w:keepNext/>' : ''}'
    '<w:spacing w:before="${inainte * 20}" w:after="${dupa * 20}"/>'
    '${indent > 0 ? '<w:ind w:left="${indent * 20}"/>' : ''}<w:jc w:val="$align"/></w:pPr>$runs</w:p>';

const _ns =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

Uint8List actDocx(ActNormativ a, List<BlocAct> blocuri) {
  final c = StringBuffer()
    ..write(
      _par(
        _run(
          a.titlu.isEmpty ? a.denumireScurta : a.titlu,
          bold: true,
          size: 15,
          culoare: '1F3A93',
        ),
        dupa: 6,
      ),
    );
  for (final d in _detalii(a)) {
    c.write(_par(_run(d, size: 9.5, culoare: '5A6273'), dupa: 0));
  }
  c.write(
    _par(
      _run(_avertisment, italic: true, size: 8.5, culoare: '5A6273'),
      inainte: 4,
      dupa: 10,
    ),
  );
  for (final b in blocuri) {
    c.write(switch (b.tip) {
      TipBloc.structura =>
        _par(
              _run(b.eticheta, bold: true, size: 12.5, culoare: '1F3A93'),
              align: 'center',
              inainte: 14,
              dupa: b.titlu.isEmpty ? 6 : 0,
              cuUrmatorul: true,
            ) +
            (b.titlu.isEmpty
                ? ''
                : _par(
                    _run(b.titlu, size: 12, culoare: '1F3A93'),
                    align: 'center',
                    dupa: 6,
                    cuUrmatorul: true,
                  )),
      TipBloc.articol => _par(
        _run(b.eticheta, bold: true, size: 11.5, culoare: '1F3A93') +
            (b.titlu.isEmpty
                ? ''
                : _run(
                    ' - ${b.titlu}',
                    bold: true,
                    size: 11.5,
                    culoare: '1F3A93',
                  )),
        inainte: 10,
        dupa: 3,
        cuUrmatorul: true,
      ),
      TipBloc.alineat || TipBloc.litera => _par(
        _run('${b.eticheta} ', bold: true) + _run(b.text),
        align: 'both',
        indent: b.tip == TipBloc.litera ? 16 : 0,
        dupa: 3,
      ),
      TipBloc.nota => _par(
        _run(b.text, italic: true, size: 9, culoare: '5A6273'),
        dupa: 3,
      ),
      TipBloc.text => _par(_run(b.text), align: 'both', dupa: 3),
    });
  }

  final subsol =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr $_ns><w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '${_run('${a.denumireScurta} · pagina ', size: 8, culoare: '5A6273')}'
      '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r>'
      '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>'
      '</w:p></w:ftr>';

  final fisiere = {
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/_rels/document.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStiluri" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rIdSubsol" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
        '</Relationships>',
    'word/styles.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
        '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="ro-RO"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '</w:styles>',
    'word/footer1.xml': subsol,
    'word/document.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_ns><w:body>$c'
        '<w:sectPr><w:footerReference w:type="default" r:id="rIdSubsol"/>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1021" w:right="1134" w:bottom="1021" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>',
  };
  final arhiva = Archive();
  fisiere.forEach((cale, text) {
    final date = utf8.encode(text);
    arhiva.addFile(ArchiveFile(cale, date.length, date));
  });
  return Uint8List.fromList(ZipEncoder().encode(arhiva));
}

// Funcții de nivel superior: ce trimitem altui isolate nu trebuie să prindă
// ecranul (State-ul nu se poate trimite).
Future<Uint8List> actPdfInFundal(
  ActNormativ a,
  List<BlocAct> blocuri,
  Uint8List normal,
  Uint8List bold,
  Uint8List italic,
) => Isolate.run(
  () => actPdf(
    a,
    blocuri,
    fontNormal: normal,
    fontBold: bold,
    fontItalic: italic,
  ),
);

Future<Uint8List> actDocxInFundal(ActNormativ a, List<BlocAct> blocuri) =>
    Isolate.run(() => actDocx(a, blocuri));

Future<List<BlocAct>> structureazaInFundal(String text) async =>
    text.length > 20000
    ? Isolate.run(() => structureazaAct(text))
    : structureazaAct(text);
