class AppBreakpoints {
  AppBreakpoints._();

  static const double phone = 600.0;
  static const double tablet = 1024.0;
  static const double desktop = 1440.0;

  // Max content width per breakpoint
  static double maxContentWidth(double width) {
    if (width < phone) return 560.0;
    if (width < tablet) return 840.0;
    if (width < desktop) return 1100.0;
    return 1200.0;
  }

  // Device type helpers
  static bool isPhone(double width) => width < phone;
  static bool isTablet(double width) => width >= phone && width < tablet;
  static bool isDesktop(double width) => width >= tablet;
}
