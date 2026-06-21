import 'package:flutter/services.dart';

class BrandHaptics {
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  // Brand specific moments
  static Future<void> ignite() async {
    await HapticFeedback.mediumImpact();
    // Simulate a double pulse if platform allows (manual delay)
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  static Future<void> lockup() async {
    await HapticFeedback.heavyImpact();
  }
}
