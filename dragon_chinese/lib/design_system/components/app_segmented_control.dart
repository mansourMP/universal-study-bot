import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/radius.dart';
import 'package:dragon_chinese/design_system/tokens/spacing.dart';

class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList(growable: false);
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final selectedIndex = (() {
      final idx = entries.indexWhere((entry) => entry.key == value);
      return idx >= 0 ? idx : 0;
    })();
    const duration = Duration(milliseconds: 240);
    const curve = Curves.easeOutCubic;
    final containerRadius = BorderRadius.circular(AppRadius.button);
    final itemRadius = BorderRadius.circular(AppRadius.sm);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: containerRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.xxxs),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
            return Row(
              children: entries
                  .map((entry) {
                    final isSelected = entry.key == value;
                    return Expanded(
                      child: _SegmentButton(
                        label: entry.value,
                        isSelected: isSelected,
                        onTap: () => onChanged(entry.key),
                      ),
                    );
                  })
                  .toList(growable: false),
            );
          }

          final segmentWidth = constraints.maxWidth / entries.length;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: selectedIndex * segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: itemRadius,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: entries
                    .map((entry) {
                      final isSelected = entry.key == value;
                      return Expanded(
                        child: _SegmentButton(
                          label: entry.value,
                          isSelected: isSelected,
                          onTap: () => onChanged(entry.key),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: isSelected ? 1 : 0.98,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: theme.textTheme.labelMedium!.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
