import 'package:flutter/material.dart';

import 'yomu_tokens.dart';

ThemeData buildYomuTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      surface: YomuTokens.surface,
      primary: YomuTokens.accent,
      error: YomuTokens.danger,
    ),
    scaffoldBackgroundColor: YomuTokens.bg,
    fontFamily: 'Segoe UI',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: YomuTokens.surface,
      foregroundColor: YomuTokens.text,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: YomuTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radius),
        side: const BorderSide(color: YomuTokens.border),
      ),
    ),
    dividerColor: YomuTokens.border,
    listTileTheme: const ListTileThemeData(
      textColor: YomuTokens.text,
      iconColor: YomuTokens.textMuted,
    ),
  );
}
