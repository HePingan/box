import 'package:flutter/material.dart';

/// Centralized design tokens for the Box app.
///
/// Keep raw color/spacing/radius/elevation values here so feature pages can
/// move toward a shared visual language without duplicating magic numbers.
class AppTokens {
  const AppTokens._();

  // Brand colors.
  static const Color seed = Color(0xFF2563EB);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color violet = Color(0xFF7C3AED);
  static const Color emerald = Color(0xFF10B981);
  static const Color rose = Color(0xFFF43F5E);
  static const Color amber = Color(0xFFF59E0B);
  static const Color orange = Color(0xFFFF7A45);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkDark = Color(0xFF111827);

  // ─── 表面与文字：随深浅切换 ───
  //
  // 深色外壳走「同一个名字、值随亮度变」这条路（而不是 ThemeExtension +
  // `AppTokens.of(context)`）：tokens 被引用 1421 次 / 93 个文件，逐个改成带
  // context 的取法等于重写整个设计系统的调用面；这里只把**表面与文字**改成
  // getter，引用点一行都不用动。
  //
  // 代价是它们不再是编译期常量：原先写在 `const` 构造里的调用要去掉 `const`。
  // 品牌色与状态色（primaryBlue / success / danger…）深浅两套通用，仍是 `static const`。
  static bool _dark = false;

  /// 当前是否深色外壳。由 `AppThemeController` 在构建前设置。
  static bool get isDark => _dark;

  /// 切换深浅。调用方负责在切换后重建（`AppThemeController` 会 notifyListeners）。
  static void setDark(bool value) {
    _dark = value;
  }

  static const Color _backgroundLight = Color(0xFFF4F7FB);
  static const Color _backgroundDark = Color(0xFF0E1116);
  static Color get background => _dark ? _backgroundDark : _backgroundLight;

  static const Color _pageGradientTopLight = Color(0xFFF0F5FF);
  static const Color _pageGradientTopDark = Color(0xFF151A22);
  static Color get pageGradientTop =>
      _dark ? _pageGradientTopDark : _pageGradientTopLight;

  static const Color _pageGradientMidLight = Color(0xFFF8FAFD);
  static const Color _pageGradientMidDark = Color(0xFF11151B);
  static Color get pageGradientMid =>
      _dark ? _pageGradientMidDark : _pageGradientMidLight;

  static const Color _pageGradientBottomLight = Color(0xFFF6F8FC);
  static const Color _pageGradientBottomDark = Color(0xFF0E1116);
  static Color get pageGradientBottom =>
      _dark ? _pageGradientBottomDark : _pageGradientBottomLight;

  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _surfaceDark = Color(0xFF171B22);
  static Color get surface => _dark ? _surfaceDark : _surfaceLight;

  static const Color _surfaceMutedLight = Color(0xFFF1F5F9);
  static const Color _surfaceMutedDark = Color(0xFF1F242D);
  static Color get surfaceMuted => _dark ? _surfaceMutedDark : _surfaceMutedLight;

  static const Color _surfaceTintLight = Color(0xFFEFF6FF);
  static const Color _surfaceTintDark = Color(0xFF1B2436);
  static Color get surfaceTint => _dark ? _surfaceTintDark : _surfaceTintLight;

  static const Color _textPrimaryLight = Color(0xFF101828);
  static const Color _textPrimaryDark = Color(0xFFE9ECF3);
  static Color get textPrimary => _dark ? _textPrimaryDark : _textPrimaryLight;

  static const Color _textSecondaryLight = Color(0xFF667085);
  static const Color _textSecondaryDark = Color(0xFFA6AEBD);
  static Color get textSecondary =>
      _dark ? _textSecondaryDark : _textSecondaryLight;

  static const Color _textTertiaryLight = Color(0xFF98A2B3);
  static const Color _textTertiaryDark = Color(0xFF7C8595);
  static Color get textTertiary =>
      _dark ? _textTertiaryDark : _textTertiaryLight;

  static const Color _dividerLight = Color(0xFFE6EAF2);
  static const Color _dividerDark = Color(0xFF272D38);
  static Color get divider => _dark ? _dividerDark : _dividerLight;
  static const Color success = Color(0xFF12B76A);
  static const Color warning = Color(0xFFF79009);
  static const Color danger = Color(0xFFF04438);
  static const Color info = Color(0xFF2E90FA);

  // Spacing.
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;
  static const double space2Xl = 32;

  // Radius.
  //
  // 首页改版时发现原阶梯缺 14/16 两档，导致卡片各写各的字面量
  // （实测出现过 9/10/14/15/16/28 六种野值）。补齐后卡片类圆角
  // 统一走 radiusCard(16)，卡内小图标走 radiusChip(10)。
  static const double radiusXs = 8;
  static const double radiusChip = 10;
  static const double radiusSm = 12;
  static const double radiusInner = 14;
  static const double radiusCard = 16;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 30;
  static const double radius2Xl = 34;
  static const double radiusPill = 999;

  // Shell layout.
  static const double shellBottomNavHeight = 68;
  static const double pageBottomPadding = 96;

  /// 卡片统一描边色。此前四个主页面混用 0xFFE7ECF5 / 0xFFE9EEF7 两个值。
  static const Color _cardBorderLight = Color(0xFFE7ECF5);
  static const Color _cardBorderDark = Color(0xFF272D38);
  static Color get cardBorder => _dark ? _cardBorderDark : _cardBorderLight;

  /// 四个主页面（首页/工具/内容/扩展）共用的水平边距。
  static const double shellPageGutter = 14;

  /// 桌面/平板断点下四个主页面共用的内容最大宽度。
  /// 移动端不触发（宽度不足时 SizedBox 仍为全宽）。
  static const double shellMaxContentWidth = 720;

  /// [shellBottomInset] 的默认额外留白。
  static const double shellBottomInsetExtra = 28;

  /// 主页面滚动内容的底部避让高度。
  ///
  /// 底部导航是**悬浮胶囊**（见 `app_shell.dart` 的 `_buildMobileLayout`），
  /// 不占布局高度，且 [AppPageScaffold] 的 `safeBottom` 默认为 false，
  /// 所以避让必须由页面自己给，并且**必须叠加 viewPadding.bottom**：
  /// 写成常量（如 `pageBottomPadding + 32`）的页面在手势区大的机型上留白
  /// 相对不足，在传统导航键机型上又过度留白，四个页面之间还会差出几十像素。
  ///
  /// [extra] 用于编辑态等底部另有浮层的场景加高。
  static double shellBottomInset(
    BuildContext context, {
    double extra = shellBottomInsetExtra,
  }) {
    return shellBottomNavHeight + MediaQuery.viewPaddingOf(context).bottom + extra;
  }

  static const double elevationLow = 0.5;
  static const double elevationNone = 0;

  static const LinearGradient blueGradient = LinearGradient(
    colors: [primaryBlue, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 页面底色渐变。三个色值随深浅切换，所以这里只能是 getter。
  static LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [pageGradientTop, pageGradientMid, pageGradientBottom],
    stops: const [0, 0.36, 1],
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [Color(0xFF0F172A), violet, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunriseGradient = LinearGradient(
    colors: [rose, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetGradient = LinearGradient(
    colors: [violet, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [emerald, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [orange, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOceanGradient = LinearGradient(
    colors: [Color(0xFF0F172A), primaryBlue, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonVioletGradient = LinearGradient(
    colors: [Color(0xFF111827), violet, rose],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> cardShadow({Color color = ink, double alpha = 0.08}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.03),
        blurRadius: 1,
        offset: const Offset(0, 0),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.05),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ];
  }

  static List<BoxShadow> shadowSm({Color color = ink}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.02),
        blurRadius: 1,
        offset: const Offset(0, 0),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.03),
        blurRadius: 3,
        offset: const Offset(0, 1.5),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.03),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> shadowMd({Color color = ink}) {
    return cardShadow(color: color);
  }

  static List<BoxShadow> shadowLg({Color color = ink}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.04),
        blurRadius: 2,
        offset: const Offset(0, 0),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.06),
        blurRadius: 6,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> heroShadow({Color color = primaryBlue}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.24),
        blurRadius: 30,
        offset: const Offset(0, 16),
      ),
    ];
  }
}
