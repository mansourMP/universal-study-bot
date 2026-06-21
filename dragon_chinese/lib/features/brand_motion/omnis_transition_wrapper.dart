import 'package:flutter/material.dart';
import 'brand_motion_curves.dart';
import 'brand_motion_tokens.dart';

class OmnisTransitionWrapper extends StatelessWidget {
  final Widget child;
  final bool animateEntry;

  const OmnisTransitionWrapper({
    super.key,
    required this.child,
    this.animateEntry = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!animateEntry) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: BrandMotionTokens.durationSM,
      curve: BrandMotionCurves.signalEntry,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
