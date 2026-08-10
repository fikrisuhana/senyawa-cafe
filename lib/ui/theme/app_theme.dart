import 'package:flutter/material.dart';

class AppTheme {
  // Google Material 3 Light Mode Palette
  static const Color primary = Color(0xFF1A73E8);            // Google Blue
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFE8F0FE);   // Soft Blue Container
  static const Color onPrimaryContainer = Color(0xFF174EA6);

  static const Color secondary = Color(0xFF0F9D58);          // Emerald Green Accent
  static const Color secondaryContainer = Color(0xFFE6F4EA);
  static const Color onSecondaryContainer = Color(0xFF137333);

  static const Color tertiary = Color(0xFF6F4E37);           // Coffee Touch Accent
  static const Color tertiaryContainer = Color(0xFFFBE9E7);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFF8F9FA);
  static const Color surfaceContainerHigh = Color(0xFFF1F3F4);

  static const Color onSurface = Color(0xFF1F1F1F);          // Deep Dark Charcoal for maximum contrast
  static const Color onSurfaceVariant = Color(0xFF5F6368);   // Medium Neutral
  static const Color outline = Color(0xFFBDC1C6);
  static const Color outlineVariant = Color(0xFFE0E0E0);      // Crisp border

  static ThemeData lightTheme(double fontScale) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineVariant, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F3F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        selectedColor: primaryContainer,
        labelStyle: TextStyle(fontSize: 12 * fontScale, fontWeight: FontWeight.bold, color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: outlineVariant)),
      ),
    );
  }

  // High-Contrast Google OLED Dark Mode Theme
  static ThemeData darkTheme(double fontScale) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4796FF),            // Google Electric Blue
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFF1E3A5F),   // Dark Blue Container
        onPrimaryContainer: Color(0xFFD2E3FC),
        secondary: Color(0xFF81C995),          // Emerald Soft Green
        secondaryContainer: Color(0xFF0D3822),
        onSecondaryContainer: Color(0xFFCEEAD6),
        surface: Color(0xFF1E1E1E),            // Dark Card Surface
        onSurface: Color(0xFFFFFFFF),          // Pure White Text for High Contrast!
        onSurfaceVariant: Color(0xFFC4C7C5),
        outline: Color(0xFF444746),
        outlineVariant: Color(0xFF2D2D2D),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212), // Deep OLED Dark Background
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF444746)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF444746)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2A2A2A),
        selectedColor: const Color(0xFF1E3A5F),
        labelStyle: TextStyle(fontSize: 12 * fontScale, fontWeight: FontWeight.bold, color: const Color(0xFFFFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF444746))),
      ),
    );
  }
}
