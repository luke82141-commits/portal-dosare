import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// LexSnap, pasul 1: textul unei fotografii, citit pe telefon.
///
/// Google ML Kit (modelul pentru alfabetul latin, cu diacriticele românești)
/// rulează local, fără internet și fără cost: fotografia nu pleacă de pe
/// telefon.
abstract class OcrService {
  /// Textul din imaginea de la [cale], pe rânduri, în ordinea citirii.
  Future<String> citeste(String cale);
}

class MlKitOcrService implements OcrService {
  static OcrService instance = MlKitOcrService();

  @override
  Future<String> citeste(String cale) async {
    final recunoastere = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final rezultat = await recunoastere.processImage(
        InputImage.fromFilePath(cale),
      );
      // Blocurile vin de sus în jos; rândurile din bloc, în ordine.
      return [
        for (final b in rezultat.blocks) b.lines.map((l) => l.text).join('\n'),
      ].join('\n\n');
    } finally {
      await recunoastere.close();
    }
  }
}
