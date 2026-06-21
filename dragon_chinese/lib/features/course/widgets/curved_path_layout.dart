import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

class CurvedPathLayout extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double nodeSpacing;
  final double curveWidth;
  final ScrollController? scrollController;
  final Color? pathColor;

  const CurvedPathLayout({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.nodeSpacing = 160.0, // Increased spacing for grandeur
    this.curveWidth = 100.0, // Wider curve
    this.scrollController,
    this.pathColor,
  });

  @override
  Widget build(BuildContext context) {
    final height = (itemCount * nodeSpacing) + 400;
    final screenWidth = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // 1. The Winding Path Line (Behind everything)
            CustomPaint(
              size: Size(screenWidth, height),
              painter: _PathPainter(
                itemCount: itemCount,
                nodeSpacing: nodeSpacing,
                curveWidth: curveWidth,
                color: pathColor ?? Colors.white.withOpacity(0.3),
              ),
            ),

            // 2. The Nodes
            ...List.generate(itemCount, (index) {
              final offset = _calculateNodeOffset(index, screenWidth);

              // Helper to center the node (assuming node size ~100)
              // We'll pass the center position to the builder?
              // Or just position top-left relative to center.
              // Let's position the CENTER of the widget at the calculated offset.

              return Positioned(
                top: offset.dy - 60, // approximate half height
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(offset.dx - screenWidth / 2, 0),
                    child: itemBuilder(context, index),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Offset _calculateNodeOffset(int index, double screenWidth) {
    final centerX = screenWidth / 2;
    // oscillation
    final xOffset =
        sin(index * pi / 1.8) * curveWidth; // Slower curve frequency
    return Offset(centerX + xOffset, (index * nodeSpacing) + 120);
  }
}

class _PathPainter extends CustomPainter {
  final int itemCount;
  final double nodeSpacing;
  final double curveWidth;
  final Color color;

  _PathPainter({
    required this.itemCount,
    required this.nodeSpacing,
    required this.curveWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Solid Gold Ink Stroke (No blur)
    final paint = Paint()
      ..color = AppColors.imperialGold.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..strokeCap = StrokeCap.round;

    // Optional: Subtle inner glow instead of blurry outer glow
    final glowPaint = Paint()
      ..color = AppColors.imperialGold.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0;
    // Removed MaskFilter.blur for sharper look

    final path = Path();
    final centerX = size.width / 2;

    // Start
    path.moveTo(centerX, 80); // Lower start point to be under first node

    for (int i = 0; i < itemCount; i++) {
      final x = centerX + sin(i * pi / 1.8) * curveWidth;
      final y = (i * nodeSpacing) + 120;

      if (i == 0) {
        path.lineTo(x, y);
      } else {
        // Bezier to next point
        final prevX = centerX + sin((i - 1) * pi / 1.8) * curveWidth;
        final prevY = ((i - 1) * nodeSpacing) + 120;

        final midY = (prevY + y) / 2;

        // Control points for smooth curve
        path.cubicTo(
          prevX,
          midY, // Control point 1 (vertical down from prev)
          x,
          midY, // Control point 2 (vertical up from curr)
          x,
          y,
        );
      }
    }

    // Draw glow first
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
