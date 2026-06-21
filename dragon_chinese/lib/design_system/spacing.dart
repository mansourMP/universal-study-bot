/// Dragon Chinese Spacing System
/// Consistent spacing values throughout the app
///
/// Deprecated for new UI code:
/// prefer `AppSpacing` from `design_system/tokens/spacing.dart`.
class DragonSpacing {
  DragonSpacing._();

  // === Base Unit: 4px ===
  static const double unit = 4.0;

  // === Named Sizes ===
  static const double xxs = 4.0;   // unit * 1
  static const double xs = 8.0;    // unit * 2
  static const double sm = 12.0;   // unit * 3
  static const double md = 16.0;   // unit * 4
  static const double lg = 24.0;   // unit * 6
  static const double xl = 32.0;   // unit * 8
  static const double xxl = 48.0;  // unit * 12
  static const double xxxl = 64.0; // unit * 16

  // === Component Specific ===
  static const double cardPadding = 16.0;
  static const double screenPadding = 20.0;
  static const double buttonPadding = 16.0;
  static const double listItemSpacing = 12.0;
  static const double sectionSpacing = 24.0;

  // === Border Radius ===
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusXxl = 24.0;
  static const double radiusFull = 999.0;
}
