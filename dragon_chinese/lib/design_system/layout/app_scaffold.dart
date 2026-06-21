import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/layout/app_layout.dart';

/// Standard scaffold with responsive AppBar + layout wrapper.
/// USE THIS for all primary screens to enforce consistency.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.titleWidget,
    this.actions,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleWidget ??
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        centerTitle: false,
        actions: actions,
      ),
      body: SafeArea(child: AppLayout(child: body)),
      floatingActionButton: floatingActionButton,
    );
  }
}
