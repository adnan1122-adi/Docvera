/// Spacing scale for the Docvera design system.
///
/// Keep paddings, gaps and card insets on this scale so spacing stays
/// consistent across every screen instead of ad-hoc magic numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal padding for a page (mobile first; wider breakpoints may
  /// center the content instead of growing the inset).
  static const double page = lg;

  /// Corner radius for cards, panels and dialogs.
  static const double radius = 12;

  /// Corner radius for small controls (chips, buttons, popovers).
  static const double radiusSmall = 10;

  /// Corner radius for pills and input fields.
  static const double radiusPill = 24;
}
