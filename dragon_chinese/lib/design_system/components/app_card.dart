import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/border.dart';
import 'package:dragon_chinese/design_system/tokens/elevation.dart';
import 'package:dragon_chinese/design_system/tokens/radius.dart';
import 'package:dragon_chinese/design_system/tokens/spacing.dart';

enum AppCardVariant {
  standard, // level1 shadow, radius 14
  hero, // level2 shadow, radius 18, stronger border
  flat, // level0, border only
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.variant = AppCardVariant.standard,
    this.padding,
    this.onTap,
    super.key,
  });

  final Widget child;
  final AppCardVariant variant;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final radius = variant == AppCardVariant.hero
        ? AppRadius.heroCard
        : AppRadius.card;

    final elevation = variant == AppCardVariant.flat
        ? AppElevation.level0
        : (variant == AppCardVariant.hero
              ? AppElevation.level2
              : AppElevation.level1);

    final borderColor = variant == AppCardVariant.hero
        ? theme.colorScheme.outline.withValues(alpha: 0.3)
        : theme.colorScheme.outline.withValues(alpha: 0.2);

    final effectivePadding =
        padding ?? const EdgeInsets.all(AppSpacing.cardPadding);

    final content = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: AppBorder.outline(borderColor),
        boxShadow: AppElevation.shadow(elevation),
      ),
      padding: effectivePadding,
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}
