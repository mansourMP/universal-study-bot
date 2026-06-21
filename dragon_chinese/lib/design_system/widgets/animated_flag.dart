import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:dragon_chinese/core/constants/languages.dart';

class AnimatedFlag extends StatefulWidget {
  final String targetLang; // e.g., 'zh'
  final String? nativeLang; // e.g., 'en', null to hide
  final double size;
  final bool showNativeOverlay;

  const AnimatedFlag({
    super.key,
    this.targetLang = 'zh',
    this.nativeLang,
    this.size = 40,
    this.showNativeOverlay = true,
  });

  @override
  State<AnimatedFlag> createState() => _AnimatedFlagState();
}

class _AnimatedFlagState extends State<AnimatedFlag> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Subtle wave/pulse animation
        final double scale = 1.0 + (_controller.value * 0.05);
        
        return Container(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Flag (Target)
              Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.size * 0.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.size * 0.2),
                    child: _buildFlagPainter(widget.targetLang),
                  ),
                ),
              ),
              
              // Native Overlay (at bottom right)
              if (widget.showNativeOverlay && widget.nativeLang != null)
                Positioned(
                  right: -widget.size * 0.1,
                  bottom: -widget.size * 0.1,
                  child: Container(
                    width: widget.size * 0.5,
                    height: widget.size * 0.5,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        AppLanguages.getByCode(widget.nativeLang!)['flag'] ?? '?',
                        style: TextStyle(fontSize: widget.size * 0.3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlagPainter(String langCode) {
    if (langCode == 'zh') {
      return CustomPaint(
        painter: _ChineseFlagPainter(),
      );
    }
    // Fallback to emoji or simple color for other future targeted languages
    return Container(
      color: Colors.red,
      child: Center(
        child: Text(
          AppLanguages.getByCode(langCode)['flag'] ?? '?',
          style: TextStyle(fontSize: widget.size * 0.6),
        ),
      ),
    );
  }
}

class _ChineseFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFFEE1C25); // Chinese Red
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Gold Stars
    final starPaint = Paint()..color = const Color(0xFFFFFF00); // Chinese Gold
    
    // Large Star
    _drawStar(canvas, Offset(size.width * 0.25, size.height * 0.3), size.width * 0.15, starPaint);
    
    // 4 Small Stars in arc
    final double smallStarSize = size.width * 0.05;
    _drawStar(canvas, Offset(size.width * 0.45, size.height * 0.15), smallStarSize, starPaint, rotation: -math.pi / 10);
    _drawStar(canvas, Offset(size.width * 0.55, size.height * 0.25), smallStarSize, starPaint, rotation: math.pi / 10);
    _drawStar(canvas, Offset(size.width * 0.55, size.height * 0.4), smallStarSize, starPaint);
    _drawStar(canvas, Offset(size.width * 0.45, size.height * 0.5), smallStarSize, starPaint, rotation: -math.pi / 10);
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint, {double rotation = 0}) {
    final Path path = Path();
    final int points = 5;
    final double innerRadius = radius * 0.4;
    final double angleStep = (2 * math.pi) / points;

    for (int i = 0; i < points; i++) {
      double outerAngle = (i * angleStep) - (math.pi / 2) + rotation;
      double innerAngle = outerAngle + (angleStep / 2);

      if (i == 0) {
        path.moveTo(
          center.dx + radius * math.cos(outerAngle),
          center.dy + radius * math.sin(outerAngle),
        );
      } else {
        path.lineTo(
          center.dx + radius * math.cos(outerAngle),
          center.dy + radius * math.sin(outerAngle),
        );
      }

      path.lineTo(
        center.dx + innerRadius * math.cos(innerAngle),
        center.dy + innerRadius * math.sin(innerAngle),
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
