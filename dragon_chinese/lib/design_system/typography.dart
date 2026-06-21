import 'package:flutter/material.dart';

/// Dragon Chinese Typography System
/// Optimized for Chinese characters with fallback to system fonts
class DragonTypography {
  DragonTypography._();

  // === Font Families ===
  static const String primaryFont = 'Inter';
  static const String chineseFont = 'NotoSansSC';

  // === Display (Headlines) ===
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.25,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // === Headline ===
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // === Title ===
  static const TextStyle titleLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  // === Body ===
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // === Label ===
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.5,
  );

  // === Chinese Character Styles (汉字样式) ===
  static const TextStyle hanziLarge = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const TextStyle hanziMedium = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const TextStyle hanziSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  // === Pinyin Styles (拼音样式) ===
  static const TextStyle pinyinLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontStyle: FontStyle.italic,
  );

  static const TextStyle pinyinMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontStyle: FontStyle.italic,
  );

  static const TextStyle pinyinSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontStyle: FontStyle.italic,
  );

  // === Button Text ===
  static const TextStyle buttonLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.25,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.25,
  );
}
