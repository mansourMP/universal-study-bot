import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/colors.dart';
import 'package:dragon_chinese/design_system/spacing.dart';
import 'package:dragon_chinese/design_system/typography.dart';

class PathThemeTokens {
  PathThemeTokens._();

  static const bool kDenseMode = false;

  static const Color ink900 = Color(0xFF0B0D10);
  static const Color ink700 = Color(0xFF23262B);
  static const Color ink500 = Color(0xFF4B5563);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF6F7F9);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color accentRed = Color(0xFFC03A2B);
  static const Color accentGold = Color(0xFFD4B06A);
  static const Color successEmerald = Color(0xFF3C9F7A);
  static const Color warningMuted = Color(0xFFB5914A);
  static const Color errorMuted = Color(0xFFCE4A4A);

  static const Color borderSubtle = Color(0xFFE6E8EC);
  static const Color headerTint = Color(0xFFF9F4F2);

  static const Color background = surfaceSubtle;
  static const Color surface = surfaceLight;
  static const Color surfaceMuted = Color(0xFFF1F2F4);
  static const Color brandAccent = accentRed;
  static const Color brandAccentSoft = Color(0xFFF7E6E1);
  static const Color highlight = Color(0xFFE8D6B1);
  static const Color ink = textPrimary;
  static const Color inkMuted = textSecondary;
  static const Color accent = brandAccent;
  static const Color accentMuted = brandAccentSoft;
  static const Color primary = accentRed;
  static const Color primaryDark = Color(0xFF8C2A1F);
  static const Color success = successEmerald;
  static const Color warning = AppColors.warning;
  static const Color error = errorMuted;
  static const Color shadowColor = Color(0x0A000000);

  static const BoxShadow shadowSm = BoxShadow(
    color: shadowColor,
    blurRadius: 8,
    offset: Offset(0, 4),
  );
  static const BoxShadow shadowMd = BoxShadow(
    color: Color(0x12000000),
    blurRadius: 12,
    offset: Offset(0, 6),
  );
  static const Color border = borderSubtle;

  static const double cardRadius = DragonSpacing.radiusLg;
  static const double pillRadius = 999;
  static const double thumbSize = 44;
  static const double railNodeSize = 16;

  static double get cardPaddingY => kDenseMode ? 10 : 10;
  static double get cardPaddingX => 16;
  static double get cardBottomPadding => kDenseMode ? 8 : 8;
  static double get railSpacing => kDenseMode ? 44 : 48;
  static double get railTopOffset =>
      cardPaddingY + (thumbSize - railNodeSize) / 2;

  static TextStyle get title =>
      DragonTypography.titleLarge.copyWith(
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );
  static TextStyle get subtitle => DragonTypography.bodyMedium.copyWith(
        color: textSecondary,
      );
  static TextStyle get sectionLabel =>
      DragonTypography.titleSmall.copyWith(
        letterSpacing: 0.3,
        color: textSecondary,
      );
  static TextStyle get chipText =>
      DragonTypography.bodySmall.copyWith(fontWeight: FontWeight.w700);
}
