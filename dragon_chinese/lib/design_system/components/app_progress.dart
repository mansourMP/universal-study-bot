import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/tokens/border.dart';
import 'package:dragon_chinese/design_system/tokens/radius.dart';
import 'package:dragon_chinese/design_system/tokens/spacing.dart';

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.height = AppSpacing.xxs,
    super.key,
  });

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(value: value, minHeight: height),
    );
  }
}

class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({this.size = AppSpacing.md, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: AppSpacing.xxxs - AppBorder.width,
      ),
    );
  }
}
