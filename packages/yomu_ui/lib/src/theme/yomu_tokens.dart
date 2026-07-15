import 'package:flutter/material.dart';

/// Desktop visual tokens sourced from the production design reference.
abstract final class YomuTokens {
  static const Color bg = Color(0xFF07090E);
  static const Color sidebar = Color(0xFF0D1017);
  static const Color surface = Color(0xFF0F131B);
  static const Color surface2 = Color(0xFF161B25);
  static const Color surface3 = Color(0xFF1C2330);
  static const Color surfaceRaised = Color(0xFF222A39);
  static const Color text = Color(0xFFF4F6FB);
  static const Color textMuted = Color(0xFFA9B2C4);
  static const Color textSubtle = Color(0xFF818CA1);
  static const Color border = Color(0xFF293141);
  static const Color borderStrong = Color(0xFF3C475D);
  static const Color accent = Color(0xFF91A5FF);
  static const Color accentStrong = Color(0xFF5068CF);
  static const Color focus = Color(0xFFB5C2FF);
  static const Color success = Color(0xFF65D19E);
  static const Color warning = Color(0xFFF2BD67);
  static const Color danger = Color(0xFFFF7F8B);

  static const Color screenDivider = Color(0x0CFFFFFF);
  static const Color cardWash = Color(0x06FFFFFF);
  static const Color cardBorder = Color(0x0FFFFFFF);
  static const Color progressTrack = Color(0xFF29303E);
  static const Color linkHover = Color(0xFFBDC8FF);
  static const Color secondaryText = Color(0xFFD4DAEA);
  static const Color accentText = Color(0xFFCBD4FF);

  // Kept as an alias for existing presentation code.
  static const Color surfaceHover = surfaceRaised;

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double radiusSm = 9;
  static const double radiusMd = 13;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
  static const double radius = radiusSm;

  static const double screenPaddingX = 28;
  static const double screenHeaderTop = 22;
  static const double screenHeaderBottom = 14;
  static const double screenScrollTop = 18;
  static const double screenScrollBottom = 30;
  static const double controlHeight = 40;
  static const double iconButtonSize = 36;
  static const double minimumHitTarget = 44;

  static const Duration durationFast = Duration(milliseconds: 140);
  static const Duration durationMedium = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 420);
}
