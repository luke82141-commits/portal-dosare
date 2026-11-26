import 'dart:io';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'ocr_service.dart';

/// LexSnap din fișiere: PDF sau imagini (JPG, JPEG, PNG...).
///
/// La PDF luăm întâi textul din fișier (documentele generate pe calculator
/// îl au exact, fără greșeli de OCR); paginile fără text (scanate) le
/// randăm ca imagine și le citim cu ML Kit, tot pe telefon.

/// Extensiile acceptate la încărcare.
const extensiiImagini = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'];
const extensiiFisiere = ['pdf', ...extensiiImagini];

/// Câte pagini citim cel mult dintr-un PDF (OCR-ul unei pagini durează
/// câteva secunde; trimiterile la lege sunt de obicei la început).
const maxPaginiPdf = 15;

/// O pagină are text propriu dacă are măcar atâtea litere / cifre; altfel e
/// scanată (sau are doar un antet) și o citim cu OCR.
const _minCaractere = 40;

/// Progresul: pagina curentă (de la 1) din total.
typedef ProgresPagini = void Function(int pagina, int total);

/// Accesul la un PDF, separat ca să poată fi simulat în teste.
abstract class SursaPdf {
  Future<int> get numarPagini;

  /// Textul paginii [i] (de la 0), cum e în fișier; gol la paginile scanate.
  Future<String> text(int i);

  /// Pagina [i] randată ca imagine, salvată temporar; întoarce calea.
  Future<String> imagine(int i);

  Future<void> inchide();
}

typedef DeschidePdf = Future<SursaPdf> Function(String cale);

class RezultatFisier {
  final String text;
  final int pagini;

  /// Câte pagini au fost citite cu OCR (scanate).
  final int paginiOcr;

  /// PDF-ul avea mai multe pagini decât [maxPaginiPdf].
  final bool trunchiat;

  const RezultatFisier(
    this.text, {
    this.pagini = 1,
    this.paginiOcr = 0,
    this.trunchiat = false,
  });
}

bool estePdf(String cale) => cale.toLowerCase().endsWith('.pdf');

int _caractereUtile(String s) =>
    RegExp(r'[0-9A-Za-zĂÂÎȘŞȚŢăâîșşțţ]').allMatches(s).length;

class CititorFisiere {
  final OcrService ocr;
  final DeschidePdf deschidePdf;

  CititorFisiere({OcrService? ocr, DeschidePdf? deschidePdf})
    : ocr = ocr ?? MlKitOcrService.instance,
      deschidePdf = deschidePdf ?? PdfrxSursa.deschide;

  /// Textul fișierului de la [cale]: PDF (text + OCR la paginile scanate)
  /// sau imagine (OCR).
  Future<RezultatFisier> citeste(String cale, {ProgresPagini? progres}) async {
    if (!estePdf(cale)) {
      progres?.call(1, 1);
      return RezultatFisier(await ocr.citeste(cale));
    }
    final pdf = await deschidePdf(cale);
    try {
      final total = await pdf.numarPagini;
      final deCitit = total < maxPaginiPdf ? total : maxPaginiPdf;
      final pagini = <String>[];
      var cuOcr = 0;
      for (var i = 0; i < deCitit; i++) {
        progres?.call(i + 1, deCitit);
        var t = (await pdf.text(i)).trim();
        if (_caractereUtile(t) < _minCaractere) {
          final img = await pdf.imagine(i);
          try {
            final citit = (await ocr.citeste(img)).trim();
            if (_caractereUtile(citit) > _caractereUtile(t)) t = citit;
            cuOcr++;
          } finally {
            try {
              File(img).deleteSync();
            } catch (_) {}
          }
        }
        if (t.isNotEmpty) pagini.add(t);
      }
      return RezultatFisier(
        pagini.join('\n\n'),
        pagini: deCitit,
        paginiOcr: cuOcr,
        trunchiat: total > deCitit,
      );
    } finally {
      await pdf.inchide();
    }
  }
}

/// PDF prin pdfrx (PDFium), pe telefon.
class PdfrxSursa implements SursaPdf {
  final PdfDocument _doc;
  PdfrxSursa._(this._doc);

  static Future<SursaPdf> deschide(String cale) async {
    await pdfrxFlutterInitialize();
    return PdfrxSursa._(await PdfDocument.openFile(cale));
  }

  @override
  Future<int> get numarPagini async => _doc.pages.length;

  @override
  Future<String> text(int i) async {
    final t = await _doc.pages[i].loadStructuredText(ensureLoaded: true);
    return t.fullText;
  }

  @override
  Future<String> imagine(int i) async {
    final pagina = _doc.pages[i];
    // ~2000 px pe lățime (≈ 240 dpi la A4): destul pentru OCR, fără să
    // umple memoria.
    final scara = 2000 / pagina.width;
    final randat = await pagina.render(
      fullWidth: pagina.width * scara,
      fullHeight: pagina.height * scara,
      backgroundColor: 0xffffffff,
    );
    if (randat == null) throw StateError('Pagina ${i + 1} nu poate fi randată');
    final ui.Image img;
    try {
      img = await randat.createImage();
    } finally {
      randat.dispose();
    }
    try {
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File(
        '${Directory.systemTemp.path}/lexsnap_${DateTime.now().microsecondsSinceEpoch}_$i.png',
      );
      await f.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      return f.path;
    } finally {
      img.dispose();
    }
  }

  @override
  Future<void> inchide() => _doc.dispose();
}
