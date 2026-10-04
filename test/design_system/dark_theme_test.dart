import 'dart:io';
import 'dart:math' as math;

import 'package:box/design_system/app_theme.dart';
import 'package:box/design_system/app_theme_controller.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 深色外壳的护栏。
///
/// 「看着不对劲」这类改动不会让任何现有用例变红，所以深浅两套的判据得自己钉：
///
/// 1. **对比度**（真撞色检测）：拿 WCAG 的对比度公式算，而不是人眼看截图 ——
///    我看不到屏幕，而"深色下这段字看不清"正是最典型的失败。
/// 2. **每色都有深色变体**：漏改一个色值 = 深色下那块还是白的。
/// 3. **判据只有一份**：档位 + 系统亮度 → 是否深色，设置页与系统栏都读它。
/// 4. **不许回退**：表面/文字色再写成 `static const Color` 就会红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppThemeController.instance.resetForTest();
  });

  /// WCAG 相对对比度。
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 在指定亮度下取一组 token 值。
  ///
  /// 注意：**不能用 `AppTheme.forBrightness`** —— 它在 `finally` 里把 tokens 复原，
  /// 所以调用完再读只会拿到切换前的值（第一版就是这么写的，结果两档读到同一套
  /// 颜色，对比度用例全绿但其实什么都没验）。这里直接切、读、切回来。
  Map<String, Color> paletteOf(Brightness brightness) {
    AppTokens.setDark(brightness == Brightness.dark);
    return <String, Color>{
      'background': AppTokens.background,
      'surface': AppTokens.surface,
      'surfaceMuted': AppTokens.surfaceMuted,
      'textPrimary': AppTokens.textPrimary,
      'textSecondary': AppTokens.textSecondary,
      'textTertiary': AppTokens.textTertiary,
      'divider': AppTokens.divider,
      'primaryBlue': AppTokens.primaryBlue,
    };
  }

  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? '深色' : '浅色';

    test('$name 配色：文字在底上的对比度都达标（正文 4.5 / 次要 3.0 / 三级 2.0）', () {
      final p = paletteOf(brightness);
      void check(String label, Color fg, Color bg, double min) {
        final value = contrast(fg, bg);
        expect(
          value,
          greaterThanOrEqualTo(min),
          reason: '$name：$label 对比度只有 ${value.toStringAsFixed(2)}，低于 $min',
        );
      }

      check('textPrimary/surface', p['textPrimary']!, p['surface']!, 4.5);
      check('textPrimary/background', p['textPrimary']!, p['background']!, 4.5);
      check('textSecondary/surface', p['textSecondary']!, p['surface']!, 3.0);
      check('textSecondary/background', p['textSecondary']!, p['background']!, 3.0);
      check('textTertiary/surface', p['textTertiary']!, p['surface']!, 2.0);
      // 主题色要当"可点文字 / 图标"用，至少 3.0。
      check('primaryBlue/surface', p['primaryBlue']!, p['surface']!, 3.0);
    });

    test('$name 配色：卡片与页面底色分得开（避免深色下糊成一片）', () {
      final p = paletteOf(brightness);
      expect(
        contrast(p['surface']!, p['background']!),
        greaterThan(1.05),
        reason: '$name：卡片底与页面底几乎同色，卡片会看不出边界',
      );
      expect(
        contrast(p['surfaceMuted']!, p['surface']!),
        greaterThan(1.02),
        reason: '$name：输入框/次级面与卡片分不开',
      );
    });
  }

  test('表面与文字色：深浅两套都有，且必须不同', () {
    Map<String, Color> snapshot(bool dark) {
      AppTokens.setDark(dark);
      return {
        'background': AppTokens.background,
        'surface': AppTokens.surface,
        'surfaceMuted': AppTokens.surfaceMuted,
        'surfaceTint': AppTokens.surfaceTint,
        'textPrimary': AppTokens.textPrimary,
        'textSecondary': AppTokens.textSecondary,
        'textTertiary': AppTokens.textTertiary,
        'divider': AppTokens.divider,
        'cardBorder': AppTokens.cardBorder,
        'pageGradientTop': AppTokens.pageGradientTop,
        'pageGradientMid': AppTokens.pageGradientMid,
        'pageGradientBottom': AppTokens.pageGradientBottom,
      };
    }

    final light = snapshot(false);
    final dark = snapshot(true);
    for (final key in light.keys) {
      expect(
        dark[key],
        isNot(equals(light[key])),
        reason: '$key 在深浅两档取值相同 —— 多半是漏了深色变体',
      );
      expect(dark[key]!.a, 1.0, reason: '$key 的深色值不该是半透明的');
    }
    // 方向也要对：深色档的表面确实比浅色档暗，文字比浅色档亮。
    expect(
      light['surface']!.computeLuminance(),
      greaterThan(dark['surface']!.computeLuminance()),
    );
    expect(
      light['background']!.computeLuminance(),
      greaterThan(dark['background']!.computeLuminance()),
    );
    expect(
      dark['textPrimary']!.computeLuminance(),
      greaterThan(light['textPrimary']!.computeLuminance()),
    );
    AppTokens.setDark(false);
  });

  test('AppTheme.forBrightness 构建完要复原全局深浅（否则污染后续构建）', () {
    AppTokens.setDark(false);
    AppTheme.forBrightness(Brightness.dark);
    expect(AppTokens.isDark, isFalse, reason: '构建深色主题后必须复原');
    AppTokens.setDark(true);
    AppTheme.forBrightness(Brightness.light);
    expect(AppTokens.isDark, isTrue, reason: '构建浅色主题后必须复原');
    AppTokens.setDark(false);
  });

  test('tokens：表面/文字色不许再写成 static const（写成常量就切不动深浅）', () {
    final source = _read('lib/design_system/app_tokens.dart');
    const mustBeDynamic = [
      'background',
      'surface',
      'surfaceMuted',
      'surfaceTint',
      'textPrimary',
      'textSecondary',
      'textTertiary',
      'divider',
      'cardBorder',
      'pageGradientTop',
      'pageGradientMid',
      'pageGradientBottom',
    ];
    for (final token in mustBeDynamic) {
      expect(
        RegExp('static const Color $token\\b').hasMatch(source),
        isFalse,
        reason: '$token 被写回了 const —— 深色下它会一直是亮色值',
      );
      expect(
        RegExp('static Color get $token\\b').hasMatch(source),
        isTrue,
        reason: '$token 没有 getter 形态',
      );
    }
    // 品牌色与状态色应该保持常量（它们深浅通用）。
    expect(RegExp(r'static const Color primaryBlue\b').hasMatch(source), isTrue);
  });

  test('判据只有一份：档位 + 系统亮度 → 是否深色', () {
    final controller = AppThemeController.instance;

    controller.resetForTest(
      preference: AppThemePreference.system,
      platformBrightness: Brightness.dark,
    );
    expect(controller.isDark, isTrue, reason: '跟随系统 + 系统深色 = 深色');
    expect(AppTokens.isDark, isTrue, reason: 'tokens 必须同步切过去');

    controller.resetForTest(
      preference: AppThemePreference.system,
      platformBrightness: Brightness.light,
    );
    expect(controller.isDark, isFalse);

    controller.resetForTest(
      preference: AppThemePreference.light,
      platformBrightness: Brightness.dark,
    );
    expect(controller.isDark, isFalse, reason: '一直亮要压过系统深色');

    controller.resetForTest(
      preference: AppThemePreference.dark,
      platformBrightness: Brightness.light,
    );
    expect(controller.isDark, isTrue, reason: '一直暗要压过系统亮色');
    expect(controller.themeMode, ThemeMode.dark);
  });

  test('三档都有中文名（设置页与用例读同一份）', () {
    expect(AppThemePreference.system.label, '跟随系统');
    expect(AppThemePreference.light.label, '一直亮');
    expect(AppThemePreference.dark.label, '一直暗');
    expect(AppThemePreference.fromCode('dark'), AppThemePreference.dark);
    expect(
      AppThemePreference.fromCode('不认识的值'),
      AppThemePreference.system,
      reason: '坏值要退化为跟随系统，不能崩',
    );
  });

  test('档位会落盘，重启读得回来', () async {
    final controller = AppThemeController.instance;
    await controller.setPreference(AppThemePreference.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppThemeController.storageKey), 'dark');

    // 冷启动：重置内存状态后从盘里读回来。
    controller.resetForTest();
    expect(controller.preference, AppThemePreference.system);
    await controller.load();
    expect(controller.preference, AppThemePreference.dark);
    expect(controller.isDark, isTrue);
    AppTokens.setDark(false);
  });

  test('主题切换后系统状态栏图标亮度跟着变（写死就看不见了）', () {
    final source = _read('lib/app/app_bootstrap.dart');
    expect(
      source.contains('AppTokens.isDark'),
      isTrue,
      reason: '系统栏样式必须读当前深浅，而不是写死图标亮度',
    );
    expect(
      RegExp(r'statusBarIconBrightness:\s*Brightness\.(dark|light),')
          .hasMatch(source),
      isFalse,
      reason: '状态栏图标亮度被写死了 —— 深色下会看不见',
    );
  });

  testWidgets('设置页真的能切：点「深色模式」→「一直暗」后全局变深，且回显档位', (tester) async {
    final controller = AppThemeController.instance;
    controller.resetForTest(platformBrightness: Brightness.light);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('深色模式'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget, reason: '右侧应回显当前档位');

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    // 三个档位都在弹层里
    for (final option in AppThemePreference.values) {
      expect(find.text(option.label), findsWidgets, reason: '缺档位「${option.label}」');
    }

    await tester.tap(find.text('一直暗').last);
    await tester.pumpAndSettle();

    expect(controller.preference, AppThemePreference.dark);
    expect(controller.isDark, isTrue);
    expect(AppTokens.isDark, isTrue, reason: 'tokens 要同步，否则页面还是亮色');
    expect(find.text('一直暗'), findsOneWidget, reason: '设置页要回显新档位');

    // 收尾：把在途的 SnackBar/日志定时器推完，避免 Pending timers 假红。
    await tester.pump(const Duration(seconds: 4));
    AppTokens.setDark(false);
  });

  testWidgets('themeMode=dark 时页面真的是深色底（接线端到端）', (tester) async {
    AppTokens.setDark(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(
      scaffold.backgroundColor,
      AppTokens.background,
      reason: '深色档下页面底色应当就是深色的 background',
    );
    expect(
      scaffold.backgroundColor!.computeLuminance(),
      lessThan(0.2),
      reason: '页面底色应当是暗的（白底说明 tokens 没切过去）',
    );
    AppTokens.setDark(false);
  });

  test('App 顶层把深浅两套都交给 MaterialApp（只给 theme 的话对话框还是亮的）', () {
    final source = _read('lib/app/app.dart');
    expect(source.contains('darkTheme: AppTheme.dark()'), isTrue);
    expect(
      RegExp(r'themeMode:\s*_theme\.themeMode').hasMatch(source),
      isTrue,
      reason: 'themeMode 要读控制器，否则设置页切了外壳不动',
    );
    expect(
      source.contains('didChangePlatformBrightness'),
      isTrue,
      reason: '要跟随系统亮度变化',
    );
  });

  test('主题级的配对（SnackBar 底/字）也要过对比度，两档都不能是深字配深底', () {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.forBrightness(brightness);
      final snack = theme.snackBarTheme;
      final bg = snack.backgroundColor!;
      final fg = snack.contentTextStyle!.color!;
      final value = contrast(fg, bg);
      expect(
        value,
        greaterThanOrEqualTo(4.5),
        reason: '${brightness == Brightness.dark ? "深色" : "浅色"}档 SnackBar 的'
            '文字/底色对比度只有 ${value.toStringAsFixed(2)}，提示会看不见',
      );
    }
    AppTokens.setDark(false);
  });

  test('外壳面板底色必须来自 tokens（写死白色 = 深色下的白条/白面板）', () {
    for (final file in ['lib/app/app_shell.dart', 'lib/app_drawer.dart']) {
      final source = _read(file);
      expect(
        RegExp(r'Colors\.white\.withValues\(alpha: 0\.9').hasMatch(source),
        isFalse,
        reason: '$file 里还有写死的白色面板底色（深色下会是一块亮块），要用 AppTokens.surface',
      );
      expect(
        RegExp(r'AppTokens\.surface\.withValues\(alpha: 0\.9').hasMatch(source),
        isTrue,
        reason: '$file 的悬浮面板底色应来自 tokens',
      );
    }
  });

  test('「主题配色」仍如实标着暂不可用（换主色与深浅是两件事）', () {
    final source = _read('lib/features/settings/presentation/settings_page.dart');
    expect(
      RegExp(r'主题配色[\s\S]{0,120}暂不可用').hasMatch(source),
      isTrue,
      reason: '主题配色没开放就还要标出来，不能删了字样让用户以为能用',
    );
  });
}

String _read(String relative) {
  return File(relative).readAsStringSync();
}
