import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';

/// A circular node representing a lesson on the path.
class PathNode extends StatelessWidget {
  final int index;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;
  final IconData icon;
  final String type;
  final double size;
  final int ringSlots;
  final double ringProgress;
  final VoidCallback? onTap;

  const PathNode({
    super.key,
    required this.index,
    required this.isLocked,
    required this.isCompleted,
    required this.isCurrent,
    required this.icon,
    this.type = 'learn',
    this.size = 56,
    this.ringSlots = 7,
    this.ringProgress = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Colors based on state
    late final Color faceColor;
    late final Color baseColor;
    late final Color iconColor;
    // Resolve theme based on type
    final theme = _getThemeForType(type);

    if (isLocked) {
      faceColor = const Color(0xFFE5E7EB);
      baseColor = const Color(0xFFD1D5DB);
      iconColor = const Color(0xFF94A3B8);
    } else if (isCompleted) {
      faceColor = const Color(0xFFFFC800); // Gold
      baseColor = const Color(0xFFE5B800);
      iconColor = Colors.white;
    } else {
      // Active / Current nodes - Use vibrant role colors
      faceColor = theme.face;
      baseColor = theme.base;
      iconColor = Colors.white;
    }

    final double clampedSize = size.clamp(44.0, 82.0).toDouble();
    final double iconSize = (clampedSize * (isCurrent ? 0.5 : 0.44)).clamp(
      20.0,
      36.0,
    );

    return SizedBox(
      width: clampedSize,
      height: clampedSize,
      child: PathNodeButton(
        size: clampedSize,
        isLocked: isLocked,
        isActive: isCurrent && !isLocked,
        faceColor: faceColor,
        baseColor: baseColor,
        iconColor: iconColor,
        icon: isCompleted ? Icons.check_rounded : icon,
        iconSize: iconSize,
        ringSlots: ringSlots,
        ringProgress: isCompleted ? 1.0 : ringProgress,
        onTap: onTap,
      ),
    );
  }

  _LessonTheme _getThemeForType(String type) {
    switch (type) {
      case 'speaking':
        return _LessonTheme(
          const Color(0xFF9B51E0),
          const Color(0xFF7B3EC0),
          Icons.mic_rounded,
        );
      case 'listening':
        return _LessonTheme(
          const Color(0xFFEB5757),
          const Color(0xFFC0392B),
          Icons.headphones_rounded,
        );
      case 'story':
        return _LessonTheme(
          const Color(0xFF27AE60),
          const Color(0xFF219150),
          Icons.auto_stories_rounded,
        );
      case 'practice':
        return _LessonTheme(
          const Color(0xFFF2994A),
          const Color(0xFFD35400),
          Icons.fitness_center_rounded,
        );
      case 'checkpoint':
        return _LessonTheme(
          const Color(0xFFF2C94C),
          const Color(0xFFD4AC0D),
          Icons.emoji_events_rounded,
        );
      default: // 'learn'
        return _LessonTheme(
          PathThemeTokens.brandAccent,
          const Color(0xFF3D5BB8),
          Icons.menu_book_rounded,
        );
    }
  }
}

class _LessonTheme {
  final Color face;
  final Color base;
  final IconData icon;
  _LessonTheme(this.face, this.base, this.icon);
}

class PathNodeButton extends StatefulWidget {
  final double size;
  final bool isLocked;
  final bool isActive;
  final Color faceColor;
  final Color baseColor;
  final Color iconColor;
  final IconData icon;
  final double iconSize;
  final int ringSlots;
  final double ringProgress;
  final VoidCallback? onTap;

  const PathNodeButton({
    super.key,
    required this.size,
    required this.isLocked,
    required this.isActive,
    required this.faceColor,
    required this.baseColor,
    required this.iconColor,
    required this.icon,
    required this.iconSize,
    this.ringSlots = 7,
    this.ringProgress = 0,
    this.onTap,
  });

  @override
  State<PathNodeButton> createState() => _PathNodeButtonState();
}

class _PathNodeButtonState extends State<PathNodeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breatheController;
  late final Animation<double> _breatheScale;
  bool _isPressed = false;
  bool _tapLocked = false;
  DateTime? _pressStartedAt;

  static const int _minPressedVisibleMs = 110;
  static const int _postReleaseDelayMs = 45;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _breatheScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    _syncBreatheAnimation();
  }

  @override
  void didUpdateWidget(covariant PathNodeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.isLocked != widget.isLocked) {
      _syncBreatheAnimation();
    }
  }

  void _syncBreatheAnimation() {
    if (widget.isActive && !widget.isLocked) {
      _breatheController.repeat(reverse: true);
    } else {
      _breatheController.stop();
      _breatheController.value = 0;
    }
  }

  Future<void> _handleTapDown(TapDownDetails _) async {
    if (widget.onTap == null || _tapLocked) return;
    _pressStartedAt = DateTime.now();
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() => _isPressed = true);
    }
  }

  Future<void> _handleTapCancel() async {
    if (!mounted) return;
    setState(() => _isPressed = false);
    _pressStartedAt = null;
    _tapLocked = false;
  }

  Future<void> _handleTapUp(TapUpDetails _) async {
    if (widget.onTap == null || _tapLocked) return;
    _tapLocked = true;

    final startedAt = _pressStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remaining = _minPressedVisibleMs - elapsed;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;
    setState(() => _isPressed = false);

    await Future.delayed(const Duration(milliseconds: _postReleaseDelayMs));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    widget.onTap?.call();
    _pressStartedAt = null;
    _tapLocked = false;
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double depth = (widget.size * 0.12).clamp(5.0, 10.0).toDouble();
    final Matrix4 tiltTransform = Matrix4.identity()
      ..setEntry(3, 2, 0.0014)
      ..rotateX(0.42);
    final glowColor = widget.faceColor.withOpacity(
      widget.isLocked ? 0.0 : 0.22,
    );

    return AnimatedBuilder(
      animation: _breatheScale,
      builder: (context, child) {
        const double baseScale = 1.0;

        return Transform.scale(
          scale: baseScale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onTap == null ? null : _handleTapDown,
            onTapUp: widget.onTap == null ? null : _handleTapUp,
            onTapCancel: widget.onTap == null ? null : _handleTapCancel,
            child: Transform(
              alignment: Alignment.center,
              transform: tiltTransform,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: depth,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.baseColor,
                        border: Border.all(
                          color: widget.baseColor.withOpacity(0.78),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: widget.size,
                    height: widget.size,
                    transform: Matrix4.translationValues(
                      0,
                      _isPressed ? depth : 0,
                      0,
                    ),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(
                            Colors.white.withOpacity(
                              widget.isLocked ? 0.05 : 0.14,
                            ),
                            widget.faceColor,
                          ),
                          widget.faceColor,
                        ],
                      ),
                      border: Border.all(
                        color: widget.baseColor.withOpacity(
                          widget.isLocked ? 0.65 : 0.32,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        if (!widget.isLocked)
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              _isPressed ? 0.10 : 0.14,
                            ),
                            blurRadius: _isPressed ? 7 : 11,
                            offset: Offset(0, _isPressed ? 1.5 : 3),
                          ),
                        if (widget.isActive && !_isPressed)
                          BoxShadow(
                            color: glowColor,
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: const Alignment(-0.35, -0.45),
                          child: Container(
                            width: widget.size * 0.42,
                            height: widget.size * 0.26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(
                                    widget.isLocked ? 0.10 : 0.22,
                                  ),
                                  Colors.white.withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Icon(
                          widget.icon,
                          color: widget.iconColor.withOpacity(
                            widget.isLocked ? 0.62 : 1,
                          ),
                          size: widget.iconSize,
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            size: Size(widget.size, widget.size),
                            painter: _SegmentedNodeRingPainter(
                              slots: widget.ringSlots,
                              progress: widget.ringProgress,
                              activeColor: widget.iconColor.withOpacity(
                                widget.isLocked ? 0.28 : 0.95,
                              ),
                              inactiveColor: Colors.white.withOpacity(
                                widget.isLocked ? 0.12 : 0.28,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentedNodeRingPainter extends CustomPainter {
  final int slots;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _SegmentedNodeRingPainter({
    required this.slots,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotCount = slots.clamp(3, 8).toInt();
    final filled = (progress.clamp(0.0, 1.0) * slotCount).round();
    final stroke = (size.width * 0.055).clamp(2.2, 4.2).toDouble();
    final radius = (size.width / 2) - (stroke * 0.9);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    final gap = 0.13; // radians
    final sweepPerSlot = (2 * pi / slotCount) - gap;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    for (var i = 0; i < slotCount; i++) {
      final start = (-pi / 2) + (i * (2 * pi / slotCount)) + (gap / 2);
      paint.color = i < filled ? activeColor : inactiveColor;
      canvas.drawArc(rect, start, sweepPerSlot, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedNodeRingPainter oldDelegate) {
    return oldDelegate.slots != slots ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _StartTooltip extends StatelessWidget {
  final Color color;

  const _StartTooltip({this.color = PathThemeTokens.brandAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PathThemeTokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        "START",
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Painter to draw the curved path connecting nodes.
class PathConnectorPainter extends CustomPainter {
  final int count;
  final double nodeSpacing;
  final double waveAmplitude;

  PathConnectorPainter({
    required this.count,
    this.nodeSpacing = 120.0,
    this.waveAmplitude = 70.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = PathThemeTokens.borderSubtle
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path path = Path();

    // Start from top center
    double centerX = size.width / 2;

    // Logic: Draw a bezier curve between each node point
    // Node positions are calculated same as in layout:
    // x = centerX + sin(i) * amplitude
    // y = i * spacing + offset

    if (count < 2) return;

    for (int i = 0; i < count - 1; i++) {
      final double y1 = i * nodeSpacing + (nodeSpacing / 2); // Center of node i
      final double x1 = centerX + sin(i * 0.8) * waveAmplitude;

      final double y2 =
          (i + 1) * nodeSpacing + (nodeSpacing / 2); // Center of node i+1
      final double x2 = centerX + sin((i + 1) * 0.8) * waveAmplitude;

      if (i == 0) {
        path.moveTo(x1, y1);
      }

      // Control points for smooth curve
      final double controlY = (y1 + y2) / 2;
      final double controlX1 = x1;
      final double controlX2 = x2;

      path.cubicTo(controlX1, controlY, controlX2, controlY, x2, y2);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
