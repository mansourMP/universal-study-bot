import 'package:flutter/material.dart';

/// Design tokens for the Premium Exercise UI (Practice Mode).
///
/// See: docs/EXERCISE_UX_SPEC.md
class ExerciseThemeTokens {
  // Colors - Backgrounds & Surfaces
  static const Color background = Color(0xFFFAFAFA); // Warm neutral
  static const Color surface = Color(0xFFFFFFFF); // Pure white cards
  static const Color surfaceMuted = Color(0xFFF2F4F7); // Wells/placeholders
  static const Color surfaceSubtle = Color(0xFFF8F9FA); // Very subtle headers
  static const Color placeholderGradientStart = Color(0xFFF7F8FA);
  static const Color placeholderGradientEnd = Color(0xFFF0F2F5);
  static const Color transparent = Colors.transparent;

  // Colors - Text
  static const Color textPrimary = Color(0xFF1A1C1E); // Nearly black
  static const Color textSecondary = Color(0xFF5F6368); // Medium grey
  static const Color textMuted = Color(0xFF9AA0A6); // Disabled/Metadata
  static const Color textInverse = Color(0xFFFFFFFF); // White text on dark

  // Colors - Brand / Interactive
  static const Color accent = Color(0xFF4A6EE0); // Royal Blue
  static const Color accentSoft = Color(0xFFEBF1FF); // Selection background
  static const Color accentHover = Color(0xFF3D5BB8);
  static const Color onAccent = Color(0xFFFFFFFF); // Text on accent

  // Colors - Semantic
  static const Color success = Color(0xFF2E7D32);
  static const Color successBg = Color(0xFFE8F5E9);
  static const Color error = Color(0xFFD32F2F);
  static const Color errorBg = Color(0xFFFFEBEE);
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderFocus = Color(0xFFB0BEC5);

  // Spacing & Geometry
  static const double pageMargin = 20.0;
  static const double cardPadding = 16.0;
  static const double gapSmall = 8.0;
  static const double gapMedium = 16.0;
  static const double gapLarge = 24.0;
  static const double optionMinHeight = 56.0;
  static const double mediaMinHeight = 160.0;
  static const double keycapDepth = 3.0;
  static const double keycapDepthLarge = 5.0;
  static const double keycapBaseDarken = 0.10;

  static const double cardRadius = 16.0;
  static const double buttonRadius = 12.0;
  static const double pillRadius = 100.0;
  static const double radiusMd = 12.0; // Standard component radius

  // Typography Styles
  static const TextStyle promptDisplay = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle promptTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle promptBody = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle optionText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: accent,
    letterSpacing: 0.1,
  );

  static const TextStyle ctaText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.2,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textMuted,
  );

  static const TextStyle chipText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textSecondary,
  );

  static const TextStyle feedback = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle displayNumber = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  // Shadows
  static const BoxShadow shadowSm = BoxShadow(
    color: Color(0x0D000000),
    offset: Offset(0, 2),
    blurRadius: 4,
  );

  static const BoxShadow shadowMd = BoxShadow(
    color: Color(0x14000000),
    offset: Offset(0, 4),
    blurRadius: 8,
  );

  // Motion tokens
  static const Duration motionFast = Duration(milliseconds: 180);
  static const Duration motionNormal = Duration(milliseconds: 220);
  static const Curve motionCurve = Curves.easeOutCubic;

  // Motion tokens for keycap press effect
  static const Duration pressDuration = Duration(milliseconds: 80);
  static const Duration releaseDuration = Duration(milliseconds: 150);
  static const Curve pressCurve = Curves.easeIn;
  static const Curve releaseCurve = Curves.easeOutBack;
  static const double pressDepthPx = 3.0;
  static const double pressScale = 0.98;
  static const Color pressedBorderDarken = Color(0xFFBDBDBD);
  static const Color pressedHighlightReduce = Color(0xFFF5F5F5);
}
