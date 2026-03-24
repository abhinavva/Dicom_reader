import 'package:flutter/material.dart';

/// Dark blue-green / teal palette (tints, shades, accent, complementary).
class AppTheme {
  // —— Base palette (dark blue-green / teal) ——
  /// Darkest shade — main background
  static const Color background = Color(0xFF060D0E);
  /// Slightly lighter — elevated areas
  static const Color backgroundElevated = Color(0xFF0A1819);
  /// Surface (cards, rails)
  static const Color surface = Color(0xFF0F2527);
  /// Surface alternate (panels, metadata)
  static const Color surfaceAlt = Color(0xFF163336);
  /// Primary teal — accent, selected state, primary buttons
  static const Color accent = Color(0xFF3D9B8C);
  /// Lighter teal — secondary emphasis, icons
  static const Color highlight = Color(0xFF6EC4BC);
  /// Text / on-surface (light tint)
  static const Color onSurface = Color(0xFFE8F4F2);
  /// Complementary muted red — errors
  static const Color error = Color(0xFFB85454);

  // —— Glass panels (teal-tinted with alpha) ——
  static const Color glassToolbar = Color(0xCC0F2527);
  static const Color glassRail = Color(0xB00F2527);
  static const Color glassMetadata = Color(0xB0122A2C);
  static const Color glassHud = Color(0xA2142628);
  static const Color glassEmpty = Color(0xB0162A2C);

  // —— Gradient stops for scaffold ——
  static const Color gradientMid = Color(0xFF0A1819);
  static const Color gradientEnd = Color(0xFF081214);

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: accent,
      secondary: highlight,
      surface: surface,
      error: error,
      onPrimary: Color(0xFF041011),
      onSecondary: Color(0xFF041018),
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
        color: onSurface.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withValues(alpha: 0.08),
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceAlt,
        contentTextStyle: base.textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
