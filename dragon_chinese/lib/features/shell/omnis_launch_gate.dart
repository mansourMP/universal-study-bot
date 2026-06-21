import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/colors.dart';

class OmnisLaunchGate extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const OmnisLaunchGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1700),
  });

  @override
  State<OmnisLaunchGate> createState() => _OmnisLaunchGateState();
}

class _OmnisLaunchGateState extends State<OmnisLaunchGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();

    Future<void>.delayed(widget.duration, () {
      if (!mounted) return;
      setState(() => _showApp = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showApp
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : ColoredBox(
              key: const ValueKey('splash'),
              color: const Color(0xFFF7F9FC),
              child: SafeArea(
                child: Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t = _controller.value;
                        final ringProgress = Curves.easeOutCubic.transform(
                          (t / 0.42).clamp(0.0, 1.0),
                        );
                        final orbitProgress = Curves.easeInOutCubic.transform(
                          ((t - 0.20) / 0.58).clamp(0.0, 1.0),
                        );
                        final pulseProgress = Curves.easeOutBack.transform(
                          ((t - 0.58) / 0.36).clamp(0.0, 1.0),
                        );
                        return CustomPaint(
                          painter: _OmnisLaunchPainter(
                            ringProgress: ringProgress,
                            orbitProgress: orbitProgress,
                            pulseProgress: pulseProgress,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _OmnisLaunchPainter extends CustomPainter {
  final double ringProgress;
  final double orbitProgress;
  final double pulseProgress;

  const _OmnisLaunchPainter({
    required this.ringProgress,
    required this.orbitProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.31;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF9DB5DE);

    final ringStart = -math.pi / 2;
    final ringSweep = (2 * math.pi * ringProgress).clamp(0.0, 2 * math.pi);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      ringStart,
      ringSweep,
      false,
      ringPaint,
    );

    final nodeAngle = ringStart + (2 * math.pi * (0.06 + 0.84 * orbitProgress));
    final node = Offset(
      center.dx + math.cos(nodeAngle) * radius,
      center.dy + math.sin(nodeAngle) * radius,
    );

    final nodePaint = Paint()..color = AppColors.primary;
    canvas.drawCircle(node, 7, nodePaint);

    final pulseOuter = 14 + 8 * pulseProgress;
    final pulseAlpha = (0.20 * (1 - pulseProgress)).clamp(0.0, 0.20);
    final pulsePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.primary.withValues(alpha: pulseAlpha);
    canvas.drawCircle(center, pulseOuter, pulsePaint);

    final coreScale = (0.94 + 0.16 * pulseProgress).clamp(0.94, 1.10);
    final corePaint = Paint()..color = const Color(0xFF4E6FAE);
    canvas.drawCircle(center, 10 * coreScale, corePaint);

    final innerPaint = Paint()..color = const Color(0xFFDCE8FF);
    canvas.drawCircle(center, 4.2 * coreScale, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _OmnisLaunchPainter oldDelegate) {
    return oldDelegate.ringProgress != ringProgress ||
        oldDelegate.orbitProgress != orbitProgress ||
        oldDelegate.pulseProgress != pulseProgress;
  }
}
