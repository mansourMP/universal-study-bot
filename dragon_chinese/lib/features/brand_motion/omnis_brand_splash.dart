import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'brand_motion_tokens.dart';
import 'brand_motion_curves.dart';
import 'brand_haptics.dart';
import '../../core/config/motion_debug_config.dart';

class OmnisBrandSplash extends StatefulWidget {
  final VoidCallback onComplete;

  const OmnisBrandSplash({super.key, required this.onComplete});

  @override
  State<OmnisBrandSplash> createState() => _OmnisBrandSplashState();
}

class _OmnisBrandSplashState extends State<OmnisBrandSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _orbitTrace;
  late Animation<double> _nodeTravel;
  late Animation<double> _coreBloom;
  late Animation<double> _lockupScale;
  late Animation<double> _fadeToApp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration:
          BrandMotionTokens.durationLaunch * MotionDebugConfig.timeDilation,
    );

    _setupAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startSequence();
    });
  }

  void _setupAnimations() {
    // 0.0 -> 1.0 total timeline
    // 1. Trace orbits (0.0 - 0.5)
    _orbitTrace = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: BrandMotionCurves.precise),
      ),
    );

    // 2. Nodes travel (0.2 - 0.7)
    _nodeTravel = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.7, curve: BrandMotionCurves.signalEntry),
      ),
    );

    // 3. Core ignite (0.6 - 0.8)
    _coreBloom = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.85, curve: BrandMotionCurves.emphasis),
      ),
    );

    // 4. Lockup stabilization (0.75 - 0.9)
    _lockupScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 0.95, curve: BrandMotionCurves.precise),
      ),
    );

    // 5. Dissolve to app (0.9 - 1.0)
    _fadeToApp = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.85, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  Future<void> _startSequence() async {
    // Accessibility check
    final isReduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    if (isReduced) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      widget.onComplete();
      return;
    }

    // Trigger haptics at key moments
    Future.delayed(
      Duration(
        milliseconds: (BrandMotionTokens.durationLaunch.inMilliseconds * 0.6)
            .round(),
      ),
      BrandHaptics.ignite,
    );

    Future.delayed(
      Duration(
        milliseconds: (BrandMotionTokens.durationLaunch.inMilliseconds * 0.85)
            .round(),
      ),
      BrandHaptics.lockup,
    );

    await _controller.forward();
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandMotionTokens.brandDeepBlue,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // If in last phase, fade out content
          final opacity = 1.0 - _fadeToApp.value;

          return Opacity(
            opacity: opacity,
            child: CustomPaint(
              painter: _OmnisPainter(
                traceProgress: _orbitTrace.value,
                travelProgress: _nodeTravel.value,
                bloomProgress: _coreBloom.value,
                lockupScale: _lockupScale.value,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _OmnisPainter extends CustomPainter {
  final double traceProgress;
  final double travelProgress;
  final double bloomProgress;
  final double lockupScale;

  _OmnisPainter({
    required this.traceProgress,
    required this.travelProgress,
    required this.bloomProgress,
    required this.lockupScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.4;

    // Paints
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = BrandMotionTokens.orbitStrokeWidthThin
      ..color = BrandMotionTokens.brandCoreTeal.withOpacity(0.3);

    final activeOrbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = BrandMotionTokens.orbitStrokeWidthBold
      ..color = BrandMotionTokens.brandCoreTeal
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = BrandMotionTokens.brandSignalWhite;

    final corePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = BrandMotionTokens.brandAccentPurple;

    final bloomPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = BrandMotionTokens.brandCoreTeal.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    // 1. Draw Ghost Orbits (Static background context)
    if (traceProgress > 0.1) {
      canvas.drawCircle(
        center,
        maxRadius * 0.6 * traceProgress,
        orbitPaint
          ..color = BrandMotionTokens.brandGhostGrey.withOpacity(
            0.5 * traceProgress,
          ),
      );
    }

    // 2. Draw Active Orbit (Tracing in)
    // We draw an arc that grows
    final activeRadius = maxRadius * 0.8;
    if (traceProgress > 0) {
      const startAngle = -math.pi / 2; // Top
      final sweepAngle = 2 * math.pi * traceProgress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: activeRadius),
        startAngle,
        sweepAngle,
        false,
        activeOrbitPaint
          ..color = BrandMotionTokens.brandCoreTeal.withOpacity(traceProgress),
      );
    }

    // 3. Draw Traveling Nodes
    // Node 1: Travels along the active orbit
    if (travelProgress > 0) {
      final angle = -math.pi / 2 + (2 * math.pi * travelProgress);
      final nodePos = Offset(
        center.dx + activeRadius * math.cos(angle),
        center.dy + activeRadius * math.sin(angle),
      );

      // Node trail/ghost
      if (travelProgress < 0.9) {
        canvas.drawCircle(
          nodePos,
          BrandMotionTokens.nodeRadius + 4 * (1 - travelProgress),
          Paint()..color = BrandMotionTokens.brandCoreTeal.withOpacity(0.2),
        );
      }

      canvas.drawCircle(nodePos, BrandMotionTokens.nodeRadius, nodePaint);
    }

    // 4. Draw Core (Bloom + Pulse)
    if (bloomProgress > 0) {
      // Bloom
      canvas.drawCircle(
        center,
        BrandMotionTokens.coreBloomRadius * (1.0 + bloomProgress),
        bloomPaint
          ..color = BrandMotionTokens.brandCoreTeal.withOpacity(
            0.4 * (1 - bloomProgress),
          ),
      );

      // Core Nucleus
      final coreRadius = 12.0 * lockupScale;
      canvas.drawCircle(center, coreRadius, corePaint);

      // White inner dot for "Signal Clarity"
      canvas.drawCircle(center, 4.0, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_OmnisPainter oldDelegate) {
    return oldDelegate.traceProgress != traceProgress ||
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.bloomProgress != bloomProgress ||
        oldDelegate.lockupScale != lockupScale;
  }
}
