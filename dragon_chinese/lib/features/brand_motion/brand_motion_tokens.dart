import 'dart:ui';

class BrandMotionTokens {
  static const Duration durationXS = Duration(milliseconds: 200);
  static const Duration durationSM = Duration(milliseconds: 350);
  static const Duration durationMD = Duration(milliseconds: 600);
  static const Duration durationLG = Duration(milliseconds: 800);
  static const Duration durationLaunch = Duration(milliseconds: 1800);

  // Brand Colors - Cyberpunk/Futuristic
  static const Color brandDeepBlue = Color(0xFF0A0F1E);
  static const Color brandCoreTeal = Color(0xFF00E5FF);
  static const Color brandAccentPurple = Color(0xFF7B61FF);
  static const Color brandSignalWhite = Color(0xFFFFFFFF);
  static const Color brandGhostGrey = Color(0xFF2A2F3E);

  // Gradient Stops
  static const List<Color> backgroundGradient = [
    brandDeepBlue,
    Color(0xFF050810),
  ];

  // Visuals
  static const double orbitStrokeWidthThin = 1.0;
  static const double orbitStrokeWidthBold = 2.5;
  static const double nodeRadius = 4.0;
  static const double coreBloomRadius = 20.0;
}
