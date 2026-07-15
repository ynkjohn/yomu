import 'package:flutter/material.dart';

import 'yomu_tokens.dart';

ThemeData buildYomuTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      surface: YomuTokens.surface,
      primary: YomuTokens.accent,
      onPrimary: Colors.white,
      secondary: YomuTokens.accent,
      onSurface: YomuTokens.text,
      error: YomuTokens.danger,
    ),
    scaffoldBackgroundColor: YomuTokens.bg,
    fontFamily: 'Segoe UI',
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: YomuTokens.text,
          displayColor: YomuTokens.text,
          fontFamily: 'Segoe UI',
        )
        .copyWith(
          headlineSmall: const TextStyle(
            color: YomuTokens.text,
            fontSize: 24,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleLarge: const TextStyle(
            color: YomuTokens.text,
            fontSize: 20,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleMedium: const TextStyle(
            color: YomuTokens.text,
            fontSize: 15,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          titleSmall: const TextStyle(
            color: YomuTokens.text,
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: const TextStyle(
            color: YomuTokens.text,
            fontSize: 14,
            height: 1.45,
          ),
          bodyMedium: const TextStyle(
            color: YomuTokens.textMuted,
            fontSize: 13,
            height: 1.45,
          ),
          bodySmall: const TextStyle(
            color: YomuTokens.textSubtle,
            fontSize: 11,
            height: 1.4,
          ),
          labelLarge: const TextStyle(
            color: YomuTokens.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          labelMedium: const TextStyle(
            color: YomuTokens.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: const TextStyle(
            color: YomuTokens.textSubtle,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: YomuTokens.bg,
      foregroundColor: YomuTokens.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: YomuTokens.surface.withValues(alpha: 0.92),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
        side: const BorderSide(color: YomuTokens.border),
      ),
    ),
    dividerColor: YomuTokens.border,
    dividerTheme: const DividerThemeData(color: YomuTokens.border, space: 1),
    listTileTheme: ListTileThemeData(
      textColor: YomuTokens.text,
      iconColor: YomuTokens.textMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: YomuTokens.surface,
      hintStyle: const TextStyle(color: YomuTokens.textSubtle),
      labelStyle: const TextStyle(color: YomuTokens.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
        borderSide: const BorderSide(color: YomuTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
        borderSide: const BorderSide(color: YomuTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
        borderSide: const BorderSide(color: YomuTokens.focus, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        backgroundColor: YomuTokens.accentStrong,
        foregroundColor: Colors.white,
        disabledBackgroundColor: YomuTokens.surface3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: Color(0xFF6F86E9)),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: const Color(0xFFD4DAEA),
        backgroundColor: YomuTokens.surface2,
        side: const BorderSide(color: YomuTokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: YomuTokens.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: YomuTokens.textMuted,
        backgroundColor: YomuTokens.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: YomuTokens.border),
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: YomuTokens.accent,
      linearTrackColor: YomuTokens.surface3,
      circularTrackColor: YomuTokens.surface3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : YomuTokens.textSubtle,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? YomuTokens.accentStrong
            : YomuTokens.surface3,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: YomuTokens.surfaceRaised,
      contentTextStyle: const TextStyle(color: YomuTokens.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
        side: const BorderSide(color: YomuTokens.borderStrong),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
