import 'package:flutter/material.dart';

class AppBorder {
  AppBorder._();

  static const double width = 1.0;
  static const double widthFocus = 2.0;

  static Border outline(Color color) =>
      Border.all(color: color, width: width);

  static Border focus(Color color) =>
      Border.all(color: color, width: widthFocus);
}
