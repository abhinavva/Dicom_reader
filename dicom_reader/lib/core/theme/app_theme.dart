import 'package:flutter/material.dart';

/// Minimal monochrome palette with frosted-glass accents.
class AppTheme {
  // —— Base palette (neutral greys) ——
  /// Darkest — main background
  static const Color background = Color(0xFF0A0A0A);
  /// Slightly lighter — elevated areas
  static const Color backgroundElevated = Color(0xFF111111);
  /// Surface (cards, rails)
  static const Color surface = Color(0xFF161616);
  /// Surface alternate (panels, metadata)
  static const Color surfaceAlt = Color(0xFF1C1C1C);
  /// Accent — selected state, primary buttons (cool grey-white)
  static const Color accent = Color(0xFFB0B0B0);
  /// Lighter emphasis — secondary icons
  static const Color highlight = Color(0xFF8A8A8A);
  /// Text / on-surface
  static const Color onSurface = Color(0xFFE8E8E8);
  /// Muted red — errors
  static const Color error = Color(0xFFA85050);

  // —— Glass panels (monochrome with alpha) ——
  static const Color glassToolbar = Color.fromARGB(180, 16, 16, 16);
  static const Color glassRail = Color.fromARGB(155, 18, 18, 18);
  static const Color glassMetadata = Color.fromARGB(155, 20, 20, 20);
  static const Color glassHud = Color.fromARGB(140, 14, 14, 14);
  static const Color glassEmpty = Color.fromARGB(155, 22, 22, 22);

  // —— Gradient stops for scaffold ——
  static const Color gradientMid = Color(0xFF0D0D0D);
  static const Color gradientEnd = Color(0xFF080808);

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: accent,
      secondary: highlight,
      surface: surface,
      error: error,
      onPrimary: Color(0xFF0A0A0A),
      onSecondary: Color(0xFF0A0A0A),
      onSurface: onSurface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Segoe UI',
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: onSurface.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withValues(alpha: 0.06),
        space: 1,
        thickness: 1,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      iconTheme: const IconThemeData(color: onSurface),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: onSurface.withValues(alpha: 0.10),
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: onSurface.withValues(alpha: 0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: onSurface.withValues(alpha: 0.10),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceAlt,
        contentTextStyle: base.textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
