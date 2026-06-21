import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/layout/breakpoints.dart';
import 'package:dragon_chinese/design_system/tokens/spacing.dart';

/// Responsive layout wrapper.
/// EVERY primary tab screen MUST wrap its body in AppLayout.
/// Handles max-width constraint + responsive horizontal padding.
class AppLayout extends StatelessWidget {
  const AppLayout({
    required this.child,
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final effectiveMaxWidth =
            maxWidth ?? AppBreakpoints.maxContentWidth(width);
        final horizontalPadding = AppSpacing.pageHorizontal(width);

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
