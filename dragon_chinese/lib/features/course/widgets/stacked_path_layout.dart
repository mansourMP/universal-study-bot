import 'package:flutter/material.dart';

class StackedPathLayout extends StatelessWidget {
  final List<Widget> items;

  const StackedPathLayout({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxVisible = items.length.clamp(1, 6);
    final stackHeight = 160 + (maxVisible - 1) * 26;

    return SizedBox(
      height: stackHeight.toDouble(),
      child: Stack(
        alignment: Alignment.topCenter,
        children: List.generate(maxVisible, (index) {
          final depth = (maxVisible - 1) - index;
          final double scale = 1 - (depth * 0.03);
          final double yOffset = depth * 26;
          final double xOffset = depth.isEven ? 8 : -8;
          final double rotation = (depth.isEven ? -1 : 1) * 0.01;
          final double opacity = 1 - (depth * 0.08);

          return Positioned(
            top: yOffset,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: opacity.clamp(0.6, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(xOffset, 0.0)
                  ..scale(scale)
                  ..rotateZ(rotation),
                child: items[index],
              ),
            ),
          );
        }),
      ),
    );
  }
}
