import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/border.dart';
import 'package:dragon_chinese/design_system/tokens/elevation.dart';
import 'package:dragon_chinese/design_system/tokens/radius.dart';

BoxDecoration standardCard(BuildContext context) {
  final theme = Theme.of(context);
  return BoxDecoration(
    color: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(AppRadius.card),
    border: AppBorder.outline(
      theme.colorScheme.outline.withValues(alpha: 0.2),
    ),
    boxShadow: AppElevation.shadow(AppElevation.level1),
  );
}
