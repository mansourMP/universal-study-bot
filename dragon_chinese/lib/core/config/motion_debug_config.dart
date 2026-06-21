class MotionDebugConfig {
  static const bool debugOverlay = false;
  static const bool slowMotion =
      false; // Set to true to debug animations at 0.1x speed

  static double get timeDilation => slowMotion ? 10.0 : 1.0;
}
