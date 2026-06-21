import 'package:flutter/material.dart';

class ParallaxLayer {
  final String assetPath;
  final double speed; // 0.0 = fixed, 1.0 = moves with scroll
  final double scale; // Slight scaling for depth effect
  final Alignment alignment;

  const ParallaxLayer({
    required this.assetPath,
    this.speed = 0.5,
    this.scale = 1.0,
    this.alignment = Alignment.bottomCenter,
  });
}

class ParallaxBackground extends StatelessWidget {
  final ScrollController scrollController;
  final List<ParallaxLayer> layers;
  final double height;

  const ParallaxBackground({
    super.key,
    required this.scrollController,
    required this.layers,
    this.height = 2000, // Total scrollable height
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        final double scrollOffset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;

        return SizedBox(
          height: MediaQuery.of(context).size.height, // Fill screen
          width: double.infinity,
          child: Stack(
            children: layers.map((layer) {
              // Calculate offset based on speed
              // speed 0.1 = far background (moves slow)
              // speed 1.0 = foreground (moves fast)
              double yPos = -(scrollOffset * layer.speed);

              // Simplistic repetition logic could be added here

              return Positioned(
                top: yPos,
                left: 0,
                right: 0,
                bottom: layer.speed == 0 ? 0 : null, // Fixed bg needs bottom 0
                height: layer.speed == 0
                    ? null
                    : height, // Scrolling layers need height
                child: Image.asset(
                  layer.assetPath,
                  fit: BoxFit.cover,
                  alignment: layer.alignment,
                  errorBuilder: (c, e, s) => Container(
                    color: Colors
                        .primaries[layers.indexOf(layer) %
                            Colors.primaries.length]
                        .withOpacity(0.2),
                    child: Center(
                      child: Text(
                        'Layer ${layers.indexOf(layer)}',
                        style: TextStyle(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
