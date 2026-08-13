import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfScrollbarThemeData;
import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// The Docvera design system.
///
/// Two Material 3 themes (light and dark) built from a single set of brand
/// and neutral tokens ([AppColors]) and component themes, so the whole app —
/// including the dart_pdf_editor chrome, which reads `colorScheme` — follows
/// the same visual language.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// The neutral canvas behind the PDF pages.
  static Color canvasColor(BuildContext context) =>
      isDark(context) ? AppColors.darkCanvas : AppColors.lightCanvas;

  /// Scrollbar styling shared by the viewer and the sidebars.
  static PdfScrollbarThemeData scrollbarTheme(bool dark) {
    return PdfScrollbarThemeData(
      thumbColor: dark ? const Color(0xFF5B6B8C) : const Color(0xFFB7C2D6),
      thumbActiveColor: dark ? const Color(0xFF7B8BAB) : const Color(0xFF8C9AB4),
      outlineColor: dark ? const Color(0x66000000) : const Color(0x00000000),
      trackColor: dark ? const Color(0x1AFFFFFF) : const Color(0x0A000000),
      trackActiveColor: dark ? const Color(0x26FFFFFF) : const Color(0x14000000),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = _colorScheme(dark);

    final hairline = dark ? const Color(0xFF26324F) : AppColors.lightBorder;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      textTheme: AppTypography.textTheme(scheme),
    );

    return base.copyWith(
      // ------------------------------------------------------------ app bar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        shape: Border(bottom: BorderSide(color: hairline, width: 1)),
      ),

      // ------------------------------------------------------- bottom sheets
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        showDragHandle: true,
        modalBarrierColor: Colors.black54,
      ),

      // -------------------------------------------------------------- dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
      ),

      // ---------------------------------------------------------------- cards
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // -------------------------------------------------------------- buttons
      // Primary buttons = [FilledButton] (blue background, white text).
      // Tonal buttons = [FilledButton.tonal] (secondary-container tint).
      // Geometry is themed here; the fill colours are left to the Material
      // defaults so primary/tonal variants keep their distinct colours and
      // the stock disabled states stay intact.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return scheme.onSurface;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(color: scheme.primary);
            }
            return BorderSide(color: scheme.outline);
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.1);
            }
            return null;
          }),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return scheme.primary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.1);
            }
            return null;
          }),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      // ---------------------------------------------------------- icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.32);
            }
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.onSurfaceVariant;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
          ),
        ),
      ),

      // ------------------------------------------------------------- inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),

      // -------------------------------------------------------------- popups
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: TextStyle(fontSize: 14, color: scheme.onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------- dividers
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // -------------------------------------------------------------- snackbar
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF2A3550) : const Color(0xFF24314A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
      ),

      // ------------------------------------------------------------ tooltip
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A3550) : const Color(0xFF24314A),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),

      // ------------------------------------------------------------ progress
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
        circularTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),

      // ------------------------------------------------------------- selects
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return scheme.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return scheme.onSurfaceVariant;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: scheme.primary);
            }
            return BorderSide(color: scheme.outline);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
        ),
      ),

      // --------------------------------------------------------------- lists
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------
  // ColorScheme
  // ------------------------------------------------------------------------

  static ColorScheme _colorScheme(bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.deepBlue,
      brightness: dark ? Brightness.dark : Brightness.light,
    );

    if (dark) {
      return scheme.copyWith(
        primary: AppColors.primaryDark,
        onPrimary: const Color(0xFF081433),
        primaryContainer: const Color(0xFF1C2E63),
        onPrimaryContainer: const Color(0xFFC9D6FF),
        secondary: AppColors.brightBlue,
        onSecondary: const Color(0xFF081433),
        secondaryContainer: const Color(0xFF1A2A54),
        onSecondaryContainer: const Color(0xFFD3DFFF),
        tertiary: const Color(0xFFE0A63C),
        onTertiary: const Color(0xFF2A2200),
        tertiaryContainer: const Color(0xFF3E3214),
        onTertiaryContainer: const Color(0xFFFFE2A8),
        error: const Color(0xFFE5534F),
        onError: const Color(0xFF3B0F0D),
        errorContainer: const Color(0xFF4A1A18),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        surfaceContainerLowest: AppColors.darkBackground,
        surfaceContainerLow: const Color(0xFF172038),
        surfaceContainer: const Color(0xFF1B2640),
        surfaceContainerHigh: const Color(0xFF202C49),
        surfaceContainerHighest: const Color(0xFF263353),
        onSurfaceVariant: AppColors.darkTextSecondary,
        outline: const Color(0xFF3E4A68),
        outlineVariant: const Color(0xFF2A3550),
        scrim: const Color(0xCC000000),
      );
    }

    return scheme.copyWith(
      primary: AppColors.deepBlue,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE1E7FF),
      onPrimaryContainer: const Color(0xFF0A1B66),
      secondary: AppColors.brightBlue,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE3EAFB),
      onSecondaryContainer: const Color(0xFF0E2E7A),
      tertiary: const Color(0xFF8A5A00),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFE7B3),
      onTertiaryContainer: const Color(0xFF4A3200),
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF1F4F9),
      surfaceContainer: const Color(0xFFEDF1F7),
      surfaceContainerHigh: const Color(0xFFE6EBF3),
      surfaceContainerHighest: const Color(0xFFDEE4EE),
      onSurfaceVariant: AppColors.lightTextSecondary,
      outline: const Color(0xFFC2C9D4),
      outlineVariant: AppColors.lightBorder,
      scrim: const Color(0xCC000000),
    );
  }
}
