import 'dart:math';
import 'package:flutter/material.dart';

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final bool shake;
  final Duration duration;
  final double offset;

  const ShakeWidget({
    super.key,
    required this.child,
    required this.shake,
    this.duration = const Duration(milliseconds: 400),
    this.offset = 8.0,
  });

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_controller);
  }

  @override
  void didUpdateWidget(covariant ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !oldWidget.shake) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final double sineValue =
            sin(4 * pi * _animation.value); // 2 shakes
        return Transform.translate(
          offset: Offset(sineValue * widget.offset, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PulseWidget extends StatefulWidget {
  final Widget child;
  final bool pulse;
  final Duration duration;
  final double scale;

  const PulseWidget({
    super.key,
    required this.child,
    required this.pulse,
    this.duration = const Duration(milliseconds: 300),
    this.scale = 1.05,
  });

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: widget.scale)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: widget.scale, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant PulseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !oldWidget.pulse) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}
