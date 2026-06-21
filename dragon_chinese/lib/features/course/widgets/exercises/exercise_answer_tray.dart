import 'package:flutter/material.dart';

/// Shared bottom-docked answer area used by selection exercises.
/// Keeps options close to the footer CTA and only scrolls when needed.
class ExerciseAnswerTray extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool forceScrollable;
  final int maxVisibleItemsWithoutScroll;
  final double estimatedChildHeight;
  final double heightSlackPx;
  final MainAxisAlignment mainAxisAlignment;

  const ExerciseAnswerTray({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.forceScrollable = false,
    this.maxVisibleItemsWithoutScroll = 4,
    this.estimatedChildHeight = 56,
    this.heightSlackPx = 20,
    this.mainAxisAlignment = MainAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );

        if (!constraints.maxHeight.isFinite) {
          return content;
        }

        final estimatedItemsHeight = children.length * estimatedChildHeight;
        final shouldScroll =
            forceScrollable || children.length > maxVisibleItemsWithoutScroll;
        final mustScrollForHeight =
            estimatedItemsHeight > (constraints.maxHeight + heightSlackPx);
        final useScroll = shouldScroll || mustScrollForHeight;

        return SingleChildScrollView(
          // Keep tray stable when content fits, but always allow overflow
          // fallback scrolling on smaller devices to prevent RenderFlex errors.
          physics: useScroll
              ? const BouncingScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }
}
