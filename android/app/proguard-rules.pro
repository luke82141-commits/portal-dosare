# google_mlkit_text_recognition face referire la toate scripturile OCR
# (chineză, devanagari, japoneză, coreeană), dar aplicația folosește doar
# scriptul latin. Fără aceste reguli, R8 oprește build-ul release.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Fără acestea, R8 strică ML Kit în release: recunoașterea textului
# (LexSnap) cade cu NullPointerException la inițializare.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
