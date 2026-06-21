import 'package:flutter/material.dart';

class AppElevation {
  AppElevation._();

  // Level 0: Flat with border only (no shadow)
  static const double level0 = 0.0;

  // Level 1: Subtle shadow for standard cards
  static const double level1 = 1.0;

  // Level 2: Hero cards and modals only
  static const double level2 = 4.0;

  // BoxShadow definitions
  static List<BoxShadow> shadow(double level) {
    if (level == level0) return const [];
    if (level == level1) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
    }
    // level2
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
