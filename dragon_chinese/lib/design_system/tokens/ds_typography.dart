import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/typography.dart';
import 'package:dragon_chinese/design_system/tokens/ds_colors.dart';

class DsTypography {
  DsTypography._();

  static const TextStyle display = DragonTypography.displaySmall;
  static const TextStyle h1 = DragonTypography.headlineLarge;
  static const TextStyle h2 = DragonTypography.headlineMedium;
  static const TextStyle title = DragonTypography.titleLarge;
  static const TextStyle body = DragonTypography.bodyMedium;
  static const TextStyle caption = DragonTypography.bodySmall;
  static const TextStyle label = DragonTypography.labelMedium;

  static const TextStyle hanzi = DragonTypography.hanziMedium;
  static const TextStyle pinyin = DragonTypography.pinyinMedium;
  static const TextStyle translation = DragonTypography.titleLarge;
  static const TextStyle button = DragonTypography.buttonMedium;

  static TextTheme textTheme = TextTheme(
    displayLarge: DragonTypography.displayLarge.copyWith(
      color: DsColors.textPrimary,
    ),
    displayMedium: DragonTypography.displayMedium.copyWith(
      color: DsColors.textPrimary,
    ),
    displaySmall: DragonTypography.displaySmall.copyWith(
      color: DsColors.textPrimary,
    ),
    headlineLarge: DragonTypography.headlineLarge.copyWith(
      color: DsColors.textPrimary,
    ),
    headlineMedium: DragonTypography.headlineMedium.copyWith(
      color: DsColors.textPrimary,
    ),
    headlineSmall: DragonTypography.headlineSmall.copyWith(
      color: DsColors.textPrimary,
    ),
    titleLarge: DragonTypography.titleLarge.copyWith(
      color: DsColors.textPrimary,
    ),
    titleMedium: DragonTypography.titleMedium.copyWith(
      color: DsColors.textPrimary,
    ),
    titleSmall: DragonTypography.titleSmall.copyWith(
      color: DsColors.textPrimary,
    ),
    bodyLarge: DragonTypography.bodyLarge.copyWith(color: DsColors.textPrimary),
    bodyMedium: DragonTypography.bodyMedium.copyWith(
      color: DsColors.textPrimary,
    ),
    bodySmall: DragonTypography.bodySmall.copyWith(
      color: DsColors.textSecondary,
    ),
    labelLarge: DragonTypography.labelLarge.copyWith(
      color: DsColors.textPrimary,
    ),
    labelMedium: DragonTypography.labelMedium.copyWith(
      color: DsColors.textSecondary,
    ),
    labelSmall: DragonTypography.labelSmall.copyWith(color: DsColors.textMuted),
  );
}
