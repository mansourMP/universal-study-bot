import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

class TimelinePathLayout extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? scrollController;

  const TimelinePathLayout({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final bool isFirst = index == 0;
        final bool isLast = index == itemCount - 1;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: double.infinity,
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      isFirst: isFirst,
                      isLast: isLast,
                      lineColor: AppColors.primary.withOpacity(0.35),
                      dotColor: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: itemBuilder(context, index)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
  final Color dotColor;

  _TimelinePainter({
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY - 8), linePaint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(centerX, centerY + 8), Offset(centerX, size.height), linePaint);
    }

    final outer = Paint()..color = dotColor.withOpacity(0.15);
    final inner = Paint()..color = dotColor;

    canvas.drawCircle(Offset(centerX, centerY), 12, outer);
    canvas.drawCircle(Offset(centerX, centerY), 6, inner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
