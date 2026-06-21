import 'package:dragon_chinese/design_system/layout/breakpoints.dart';

/// Spacing scale for the app.
/// DO NOT use raw double values in UI code - always reference these tokens.
class AppSpacing {
  AppSpacing._();

  // Base scale (4pt grid)
  static const double xxxs = 4.0;
  static const double xxs = 8.0;
  static const double xs = 12.0;
  static const double sm = 16.0;
  static const double md = 24.0;
  static const double lg = 32.0;
  static const double xl = 40.0;
  static const double xxl = 48.0;

  // Semantic tokens
  static const double cardPadding = sm; // 16
  static const double sectionGap = md; // 24
  static const double listItemGap = xxs; // 8

  // Responsive page padding (use via AppLayout)
  static double pageHorizontal(double width) {
    return width >= AppBreakpoints.tablet ? md : sm;
  }
}
