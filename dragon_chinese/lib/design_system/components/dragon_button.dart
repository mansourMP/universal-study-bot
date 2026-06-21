import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/ds_colors.dart';
import 'package:dragon_chinese/design_system/tokens/ds_radii.dart';
import 'package:dragon_chinese/design_system/tokens/ds_spacing.dart';
import 'package:dragon_chinese/design_system/tokens/ds_typography.dart';

enum DragonButtonVariant { primary, secondary, ghost }

class DragonButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final DragonButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  const DragonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = DragonButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(
        Size(fullWidth ? double.infinity : 0, 48),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: DsSpacing.lg,
          vertical: DsSpacing.sm,
        ),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadii.md)),
      ),
      textStyle: WidgetStateProperty.all(
        DsTypography.button.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: DsSpacing.xs),
              Text(label),
            ],
          );

    switch (variant) {
      case DragonButtonVariant.primary:
        return FilledButton(
          onPressed: onPressed,
          style: style.copyWith(
            backgroundColor: WidgetStateProperty.all(DsColors.primary),
            foregroundColor: WidgetStateProperty.all(DsColors.textOnPrimary),
          ),
          child: child,
        );
      case DragonButtonVariant.secondary:
        return OutlinedButton(
          onPressed: onPressed,
          style: style.copyWith(
            foregroundColor: WidgetStateProperty.all(DsColors.primary),
            side: WidgetStateProperty.all(
              const BorderSide(color: DsColors.border),
            ),
          ),
          child: child,
        );
      case DragonButtonVariant.ghost:
        return TextButton(
          onPressed: onPressed,
          style: style.copyWith(
            foregroundColor: WidgetStateProperty.all(DsColors.textSecondary),
            minimumSize: WidgetStateProperty.all(
              Size(fullWidth ? double.infinity : 0, 44),
            ),
          ),
          child: child,
        );
    }
  }
}
