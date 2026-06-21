import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/radius.dart';
import 'package:dragon_chinese/design_system/tokens/spacing.dart';

enum AppButtonVariant {
  primary, // filled, primary color
  secondary, // tonal/outline
  text, // text only
}

enum AppButtonSize {
  small, // height 40
  medium, // height 48
  large, // height 56
}

class AppButton extends StatelessWidget {
  const AppButton({
    required this.onPressed,
    required this.label,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.fullWidth = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final height = switch (size) {
      AppButtonSize.small => AppSpacing.xl,
      AppButtonSize.medium => AppSpacing.xxl,
      AppButtonSize.large => AppSpacing.xxl + AppSpacing.xxs,
    };
    final iconSize = AppSpacing.sm + AppSpacing.xxxs;

    final textStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );

    final minimumSize = Size(fullWidth ? double.infinity : 0, height);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );

    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize),
              const SizedBox(width: AppSpacing.xxs),
              Text(label),
            ],
          )
        : Text(label);

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          shape: shape,
          textStyle: textStyle,
        ),
        child: child,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: minimumSize,
          shape: shape,
          textStyle: textStyle,
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: minimumSize,
          shape: shape,
          textStyle: textStyle,
        ),
        child: child,
      ),
    };
  }
}
