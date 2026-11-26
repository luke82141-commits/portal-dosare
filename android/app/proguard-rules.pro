# google_mlkit_text_recognition face referire la toate scripturile OCR
# (chineză, devanagari, japoneză, coreeană), dar aplicația folosește doar
# scriptul latin. Fără aceste reguli, R8 oprește build-ul release.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
