import 'package:flutter/material.dart';

class BrandMotionCurves {
  // Aggressive entry, soft landing
  static const Curve signalEntry = Cubic(0.1, 0.9, 0.2, 1.0);

  // Standard material-ish emphasis
  static const Curve emphasis = Cubic(0.2, 0.0, 0.0, 1.0);

  // Robotic/Mechanical precise movement
  static const Curve precise = Cubic(0.4, 0.0, 0.2, 1.0);

  // Slow drift for background elements
  static const Curve drift = Curves.easeInOutSine;
}
