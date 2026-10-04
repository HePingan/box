import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Shared Material theme for the app.
///
/// 深浅两套都从这里出：`_build` 读的是 `AppTokens` 的**当前**色值，
/// 而 `AppTokens` 的当前值由 `AppThemeController` 决定。`MaterialApp` 会同时
/// 持有 `theme` 与 `darkTheme`，所以 [forBrightness] 在构建前把 tokens 临时切到
/// 那一档、构建完立刻复原 —— 否则两套主题会共用同一个调色板，
/// 出现「底色变深了、对话框还是白的」。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => forBrightness(Brightness.light);

  static ThemeData dark() => forBrightness(Brightness.dark);

  /// 按指定亮度构建一套完整主题（不受当前全局深浅影响）。
  static ThemeData forBrightness(Brightness brightness) {
    final wasDark = AppTokens.isDark;
    AppTokens.setDark(brightness == Brightness.dark);
    try {
      return _build(brightness);
    } finally {
      AppTokens.setDark(wasDark);
    }
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seed,
      brightness: brightness,
    );

    final typography = Typography.material2021();
    final baseTextTheme = (isDark ? typography.white : typography.black).apply(
      bodyColor: AppTokens.textPrimary,
      displayColor: AppTokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppTokens.background,
      canvasColor: AppTokens.surface,
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
      cardTheme: CardThemeData(
        elevation: AppTokens.elevationLow,
        margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        color: AppTokens.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppTokens.surfaceMuted : AppTokens.inkDark,
        // 两档的底都是深的，所以文字都得是浅色：第一版写成 textPrimary，
        // 浅色档就成了「深字配深底」（对比度 1.0，等于看不见）。
        contentTextStyle: TextStyle(
          color: isDark ? AppTokens.textPrimary : Colors.white,
        ),
      ),
      dividerTheme: DividerThemeData(
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surfaceMuted,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusMd)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppTokens.radiusMd),
          ),
          borderSide: BorderSide(color: AppTokens.seed),
        ),
      ),
    );
  }
}
