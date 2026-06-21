import 'package:flutter/material.dart';

/// Shared card entrance for hub grids (Vocabulary, Listening, etc.).
/// Keeps timing/curve identical across hubs.
class HubCardEntrance extends StatelessWidget {
  const HubCardEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const int _baseMs = 180;
  static const int _stepMs = 18;
  static const int _maxExtraMs = 160;

  @override
  Widget build(BuildContext context) {
    final int extraMs = (index * _stepMs).clamp(0, _maxExtraMs);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: _baseMs + extraMs),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, animatedChild) {
        final opacity = value.clamp(0.0, 1.0);
        final dy = (1 - value) * 8;
        final scale = 0.99 + (0.01 * value);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: animatedChild),
          ),
        );
      },
    );
  }
}
