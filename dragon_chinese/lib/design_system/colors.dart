import 'package:flutter/material.dart';

/// App Theme Colors
/// Dynamic color system that adapts to the target language
class AppColors {
  AppColors._();

  // === Default / Fallback Theme (Universal Brand) ===
  static const Color brandPrimary = Color(
    0xFF58CC02,
  ); // Duolingo-style Green (Safe, Growth)
  static const Color brandSecondary = Color(0xFFCE82FF); // Purple
  static const Color brandTertiary = Color(0xFFFF4B4B); // Red

  // === Neutral Scale (Ink) ===
  static const Color ink = Color(0xFF2D2D2D);
  static const Color inkLight = Color(0xFF4A4A4A);
  static const Color inkLighter = Color(0xFF6B6B6B);

  // === Background & Surface ===
  static const Color background = Color(0xFFF7F7F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0F0F0);

  // === Text Colors ===
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textTertiary = Color(0xFFA0A0A0);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // === Feedback Colors ===
  static const Color success = Color(0xFF58CC02);
  static const Color successDark = Color(0xFF46A302);

  static const Color error = Color(0xFFFF4B4B);
  static const Color errorDark = Color(0xFFD33333);

  static const Color warning = Color(0xFFFFC800);
  static const Color warningDark = Color(0xFFC79D00);

  // === Imperial Palette (Premium) ===
  static const Color imperialRed = Color(0xFFC03A2B); // China Red
  static const Color imperialRedDark = Color(0xFF8C2A1F);
  static const Color imperialGold = Color(0xFFFFD700); // Premium Gold
  static const Color imperialGoldDark = Color(0xFFC5A000);

  static const Color midnightInk = Color(0xFF1A1A2E); // Deep Navy/Ink
  static const Color midnightInkLight = Color(0xFF16213E);

  static const Color jadeLight = Color(0xFF58A55C);
  static const Color jadeDark = Color(0xFF2E7D32);

  // === Gradients ===
  static const LinearGradient imperialGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2C3E50), // Midnight
      Color(0xFF000000), // Black
    ],
  );

  static const LinearGradient redGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
  );

  // === Language Specific Themes ===
  static const mandarinTheme = LanguageTheme(
    primary: Color(0xFFC03A2B), // China Red
    primaryDark: Color(0xFF8C2A1F),
    secondary: Color(0xFF58A55C), // Jade Green
    secondaryDark: Color(0xFF3D7B40),
  );

  static const spanishTheme = LanguageTheme(
    primary: Color(0xFFFFC107), // Spain Yellow
    primaryDark: Color(0xFFFFA000),
    secondary: Color(0xFFD32F2F), // Spain Red
    secondaryDark: Color(0xFFC62828),
  );

  static const frenchTheme = LanguageTheme(
    primary: Color(0xFF002395), // France Blue
    primaryDark: Color(0xFF001560),
    secondary: Color(0xFFED2939), // France Red
    secondaryDark: Color(0xFFB01020),
  );

  /* === CONVENIENCE PROXIES (Defaulting to Mandarin for MVP) === */
  // Keep these const to allow usage inside const widget trees.
  static const Color primary = Color(0xFFC03A2B);
  static const Color primaryDark = Color(0xFF8C2A1F);
  static const Color primaryLight = Color(0xFFE85D4E); // Calculated
  static const Color secondary = Color(0xFF58A55C);

  static const Color jade = Color(0xFF58A55C); // Keep for compatibility
  static const Color gold = Color(0xFFFFB61A);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE85D4E), Color(0xFFC03A2B)],
  );

  static const Color border = Color(0xFFD4D4D4);
}

class LanguageTheme {
  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color secondaryDark;

  const LanguageTheme({
    required this.primary,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryDark,
  });
}
