import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/lexsnap/fisier_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// PDF-ul citit cu PDFium real (pdfrx), nu simulat.
void main() {
  testWidgets('PDF real: textul paginilor și pagina randată ca PNG', (t) async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    await t.runAsync(() async {
      final doc = pw.Document()
        ..addPage(
          pw.Page(
            build: (_) =>
                pw.Text('PROCES-VERBAL conform OG nr. 2/2001 art. 31'),
          ),
        )
        ..addPage(
          pw.Page(build: (_) => pw.Text('Pagina a doua a documentului.')),
        );
      final f = File('${Directory.systemTemp.path}/lexsnap_test.pdf')
        ..writeAsBytesSync(await doc.save());
      final s = await PdfrxSursa.deschide(f.path);
      try {
        expect(await s.numarPagini, 2);
        expect(await s.text(0), contains('OG nr. 2/2001 art. 31'));
        final img = File(await s.imagine(0));
        final antet = img.readAsBytesSync().sublist(1, 4);
        expect(String.fromCharCodes(antet), 'PNG');
        img.deleteSync();
      } finally {
        await s.inchide();
        f.deleteSync();
      }
    });
  });
}
