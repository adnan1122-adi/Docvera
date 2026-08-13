import 'package:flutter/material.dart';

/// The Docvera typography hierarchy.
///
/// A clean platform-default sans-serif (SF Pro on iOS, Roboto on Android,
/// the system font on web). No custom font family is forced so non-Latin
/// scripts — including Arabic — fall back to the correct system typeface
/// rather than inheriting a Latin-only face.
abstract final class AppTypography {
  /// Builds the [TextTheme] used by the app. Colors come from the active
  /// scheme; sizes/weights stay identical in light and dark so screens do
  /// not shift when the theme changes.
  static TextTheme textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final label = scheme.primary;

    return TextTheme(
      // Display — reserved for hero moments only.
      displaySmall: TextStyle(
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: onSurface,
      ),

      // Heading.
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),

      // Section heading.
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),

      // Body.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),

      // Secondary text.
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),

      // Caption.
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: onSurfaceVariant,
      ),

      // Button text.
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: label,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
    );
  }
}
