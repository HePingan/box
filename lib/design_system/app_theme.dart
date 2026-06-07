import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Shared Material theme for the app.
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seed,
      brightness: Brightness.light,
    );

    final baseTextTheme = Typography.material2021().black.apply(
      bodyColor: AppTokens.textPrimary,
      displayColor: AppTokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppTokens.background,
      textTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: AppTokens.elevationNone,
        scrolledUnderElevation: AppTokens.elevationLow,
        backgroundColor: AppTokens.surface,
        foregroundColor: AppTokens.textPrimary,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: AppTokens.elevationLow,
        margin: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        color: AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppTokens.divider,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          borderSide: BorderSide(color: AppTokens.seed),
        ),
      ),
    );
  }
}
