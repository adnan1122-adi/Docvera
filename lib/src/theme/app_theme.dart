import 'package:flutter/material.dart';

/// Design tokens for the PDF editor chrome.
abstract final class AppTokens {
  static const double railWidth = 64;
  static const double bottomBarHeight = 44;
  static const double radius = 12;
  static const double radiusSmall = 8;

  static const Duration pageAnim = Duration(milliseconds: 220);

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);

  /// Neutral page background that sits behind the canvas so white PDF
  /// pages read as distinct "paper" sheets.
  static const Color canvasLight = Color(0xFFE9EDF3);
  static const Color canvasDark = Color(0xFF101316);
}

/// Application themes. A light and a dark Material 3 theme sharing the same
/// component styling so chrome stays consistent whichever mode is active.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF7AA9FF) : AppTokens.primary,
      surface: isDark ? const Color(0xFF1C1F23) : Colors.white,
      surfaceContainerLowest: isDark ? const Color(0xFF14171A) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF191C20) : const Color(0xFFF3F5F8),
      surfaceContainer: isDark ? const Color(0xFF1F2328) : const Color(0xFFECF0F5),
      surfaceContainerHigh: isDark ? const Color(0xFF262B31) : const Color(0xFFE3E8EF),
      surfaceContainerHighest: isDark ? const Color(0xFF2E343B) : const Color(0xFFD9E0E8),
      outline: isDark ? const Color(0xFF4A525C) : const Color(0xFFB8C2CE),
      outlineVariant: isDark ? const Color(0xFF333A42) : const Color(0xFFE0E6EC),
      onSurfaceVariant: isDark ? const Color(0xFFB6C0CB) : const Color(0xFF4B5563),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor:
          isDark ? AppTokens.canvasDark : AppTokens.canvasLight,
    );

    final hairline = isDark ? const Color(0xFF2A2F36) : const Color(0xFFE3E8EE);

    return base.copyWith(
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: Border(
          bottom: BorderSide(color: hairline, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        showDragHandle: true,
        modalBarrierColor: Colors.black54,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2E343B) : const Color(0xFF22303F),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A414A) : const Color(0xFF2B3440),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
