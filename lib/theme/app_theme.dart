import 'package:flutter/material.dart';

/// Culorile din design-ul Figma („Portal Dosare – Design aplicație”,
/// colecția de variabile „Culori”). Numele corespund variabilelor de acolo.
abstract final class AppColors {
  static const primary = Color(0xFF1F3A93);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFE3E9FF);
  static const onPrimaryContainer = Color(0xFF14286B);
  static const surface = Color(0xFFF5F6FA);
  static const card = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFEEF0F6);
  static const outline = Color(0xFFE1E4EC);
  static const onSurface = Color(0xFF121826);
  static const onSurfaceVariant = Color(0xFF5A6273);
  static const accent = Color(0xFFB8892F);
  static const accentContainer = Color(0xFFFBF2DE);
  static const success = Color(0xFF1E7F55);
  static const successContainer = Color(0xFFE2F4EA);
  static const warning = Color(0xFFB4570C);
  static const warningContainer = Color(0xFFFDEBD8);
  static const error = Color(0xFFB3261E);
}

/// Colțuri folosite peste tot în design.
abstract final class AppRadius {
  static const card = 16.0;
  static const input = 12.0;
  static const button = 14.0;
  static const hero = 28.0;
}

/// [fontFamily] e folosit doar la randarea capturilor în teste; pe telefon
/// rămâne fontul sistemului (Roboto pe Android).
ThemeData construiesteTema({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.accent,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.accentContainer,
    onSecondaryContainer: AppColors.accent,
    tertiary: AppColors.success,
    tertiaryContainer: AppColors.successContainer,
    onTertiaryContainer: AppColors.success,
    error: AppColors.error,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outlineVariant: AppColors.outline,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.surfaceVariant,
    surfaceContainerHigh: AppColors.surfaceVariant,
    surfaceContainerHighest: AppColors.surfaceVariant,
    surfaceTint: Colors.transparent,
  );

  final rotunjitInput = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.input),
    borderSide: const BorderSide(color: AppColors.outline),
  );
  final formaButon = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );
  final textButon = TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.7)),
      prefixIconColor: AppColors.onSurfaceVariant,
      border: rotunjitInput,
      enabledBorder: rotunjitInput,
      focusedBorder: rotunjitInput.copyWith(
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: formaButon,
        textStyle: textButon,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: formaButon,
        textStyle: textButon,
        backgroundColor: AppColors.card,
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? AppColors.onPrimaryContainer
              : AppColors.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? AppColors.onSurface
              : AppColors.onSurfaceVariant,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : null,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : null,
      ),
    ),
  );
}
