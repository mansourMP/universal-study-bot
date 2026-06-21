import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

class IslandsPathLayout extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? scrollController;
  final double nodeSpacing;
  final double curveWidth;

  const IslandsPathLayout({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
    this.nodeSpacing = 200.0,
    this.curveWidth = 110.0,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final height = (itemCount * nodeSpacing) + 360;

    return SingleChildScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            CustomPaint(
              size: Size(size.width, height),
              painter: _IslandsBackgroundPainter(
                primary: AppColors.primary.withOpacity(0.12),
              ),
            ),
            ...List.generate(itemCount, (index) {
              final offset = _calculateNodeOffset(index, size.width);
              return Positioned(
                top: offset.dy - 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(offset.dx - size.width / 2, 0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size.width - 80),
                      child: itemBuilder(context, index),
                    ),
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
    final xOffset = sin(index * pi / 1.7) * curveWidth;
    return Offset(centerX + xOffset, (index * nodeSpacing) + 150);
  }
}

class _IslandsBackgroundPainter extends CustomPainter {
  final Color primary;

  _IslandsBackgroundPainter({required this.primary});

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = const Color(0xFFF7F9FC);
    canvas.drawRect(Offset.zero & size, sky);

    _drawHill(
      canvas,
      size,
      color: const Color(0xFFEAF1F9),
      heightFactor: 0.28,
      offsetY: size.height * 0.15,
      wiggle: 60,
    );
    _drawHill(
      canvas,
      size,
      color: const Color(0xFFE3EDF7),
      heightFactor: 0.32,
      offsetY: size.height * 0.38,
      wiggle: 70,
    );
    _drawHill(
      canvas,
      size,
      color: primary.withOpacity(0.6),
      heightFactor: 0.36,
      offsetY: size.height * 0.66,
      wiggle: 90,
    );

    final mist = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.25), 80, mist);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.55), 100, mist);
  }

  void _drawHill(
    Canvas canvas,
    Size size, {
    required Color color,
    required double heightFactor,
    required double offsetY,
    required double wiggle,
  }) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(0, offsetY);

    final mid1 = Offset(size.width * 0.3, offsetY - wiggle);
    final mid2 = Offset(size.width * 0.7, offsetY + wiggle * 0.6);
    path.quadraticBezierTo(mid1.dx, mid1.dy, size.width * 0.5, offsetY);
    path.quadraticBezierTo(mid2.dx, mid2.dy, size.width, offsetY);
    path.lineTo(size.width, offsetY + size.height * heightFactor);
    path.lineTo(0, offsetY + size.height * heightFactor);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
