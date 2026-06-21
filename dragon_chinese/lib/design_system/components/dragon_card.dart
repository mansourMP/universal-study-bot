import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/ds_colors.dart';
import 'package:dragon_chinese/design_system/tokens/ds_elevation.dart';
import 'package:dragon_chinese/design_system/tokens/ds_radii.dart';
import 'package:dragon_chinese/design_system/tokens/ds_spacing.dart';

class DragonCard extends StatelessWidget {
  final Widget? header;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const DragonCard({
    super.key,
    this.header,
    required this.child,
    this.padding = const EdgeInsets.all(DsSpacing.md),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: DsSpacing.sm),
          ],
          child,
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: DsColors.surface,
        borderRadius: BorderRadius.circular(DsRadii.lg),
        border: Border.all(color: DsColors.borderSubtle),
        boxShadow: DsElevation.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DsRadii.lg),
        child: onTap == null
            ? content
            : InkWell(
                borderRadius: BorderRadius.circular(DsRadii.lg),
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}
