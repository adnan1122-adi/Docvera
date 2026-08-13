import 'package:flutter/material.dart';

/// Docvera brand and neutral design tokens.
///
/// Blue is the brand color: it is reserved for important actions, active
/// states and branding. Everything else leans on neutral surfaces so the
/// UI reads professional and calm, with the PDF document as the focus.
abstract final class AppColors {
  // -------------------------------------------------------------- brand blue
  /// Primary brand — deep blue. Used for primary actions and emphasis.
  static const Color deepBlue = Color(0xFF123BDA);

  /// Bright blue — secondary actions and hover/pressed states of primary.
  static const Color brightBlue = Color(0xFF1769FF);

  /// Accent blue — tertiary/active accents (active tool, links, focus).
  static const Color accentBlue = Color(0xFF20A4FF);

  /// The dark theme's primary (a slightly softer blue that reads on dark
  /// surfaces without losing contrast).
  static const Color primaryDark = Color(0xFF3D7BFF);

  // ------------------------------------------------------------------ light
  static const Color lightBackground = Color(0xFFF7F9FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF667085);
  static const Color lightBorder = Color(0xFFE5E7EB);

  /// The neutral canvas behind the PDF pages in light mode, so white pages
  /// read as distinct paper sheets.
  static const Color lightCanvas = Color(0xFFE2E7EF);

  // ------------------------------------------------------------------- dark
  static const Color darkBackground = Color(0xFF0B1020);
  static const Color darkSurface = Color(0xFF121A2B);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFAAB4C5);

  /// The canvas behind the PDF pages in dark mode.
  static const Color darkCanvas = Color(0xFF070C18);

  // -------------------------------------------------------------- selection
  /// The wash over a text selection in the viewer (light + dark).
  static const Color selectionLight = Color(0x40176BFF);
  static const Color selectionDark = Color(0x553D8BFF);

  /// The wash over the current search match.
  static const Color searchMatchLight = Color(0x40F5B301);
  static const Color searchMatchDark = Color(0x59F5B301);

  /// The active search result (stronger, brand-tinted).
  static const Color searchCurrentLight = Color(0x60176BFF);
  static const Color searchCurrentDark = Color(0x663D8BFF);

  /// The editing overlay's selection chrome (boxes, handles, marquee).
  static const Color chromeLight = Color(0xFF1769FF);
  static const Color chromeDark = Color(0xFF4F8BFF);
}
