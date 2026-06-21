import 'package:flutter/material.dart';

enum DsBreakpoint { compact, medium, expanded }

class DsBreakpoints {
  DsBreakpoints._();

  static DsBreakpoint of(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1024) return DsBreakpoint.expanded;
    if (width >= 600) return DsBreakpoint.medium;
    return DsBreakpoint.compact;
  }
}

class DsLayout {
  DsLayout._();

  static double pageMaxWidth(BuildContext context) {
    switch (DsBreakpoints.of(context)) {
      case DsBreakpoint.compact:
        return double.infinity;
      case DsBreakpoint.medium:
        return 720;
      case DsBreakpoint.expanded:
        return 960;
    }
  }

  static EdgeInsets pagePadding(BuildContext context) {
    switch (DsBreakpoints.of(context)) {
      case DsBreakpoint.compact:
        return const EdgeInsets.symmetric(horizontal: 16);
      case DsBreakpoint.medium:
        return const EdgeInsets.symmetric(horizontal: 24);
      case DsBreakpoint.expanded:
        return const EdgeInsets.symmetric(horizontal: 32);
    }
  }
}

class DsPage extends StatelessWidget {
  final Widget child;

  const DsPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final maxWidth = DsLayout.pageMaxWidth(context);
    final padding = DsLayout.pagePadding(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
