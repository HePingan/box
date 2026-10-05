import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/design_system/app_theme.dart';
import 'package:box/design_system/app_theme_controller.dart';
import 'package:box/design_system/app_theme_scope.dart';
import 'package:box/design_system/app_tokens.dart';

/// 深浅切换必须**当场生效** —— 不能"退出重进才变"。
///
/// 背景：`AppTokens` 的颜色是 static getter（深色批次 1 的路线 B），已经建好的
/// 页面不会因为静态值变了而重建。所以外壳与每个路由入口都用 [AppThemeRebuild]
/// 包了一层。下面把"包了会变 / 不包不变"两条都钉住 —— 后半条是**负向对照**，
/// 防止有人觉得那层包装多余而删掉。
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('probe'),
      color: AppTokens.surface,
      width: 20,
      height: 20,
    );
  }
}

Color _probeColor(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(const ValueKey('probe'))).color!;

Future<void> _pump(
  WidgetTester tester,
  AppThemeController controller, {
  required bool wrapped,
}) async {
  await tester.pumpWidget(
    AppThemeScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // 注意两侧的 `_Probe()` 都**不能写 const**：写 const 会返回同一个
        // canonical 实例，Element 会短路掉重建 —— 那正是"改了要退出重进"的
        // 成因，包装层也就白包了。
        home: wrapped
            ? AppThemeRebuild(builder: (context) => _Probe())
            : _Probe(),
      ),
    ),
  );
}

String _read(String relative) => File(relative).readAsStringSync();

void main() {
  final AppThemeController theme = AppThemeController.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    theme.resetForTest();
  });

  tearDown(() => theme.resetForTest());

  testWidgets('包了 AppThemeRebuild 的页面：切深浅当场换色（不用重启）', (tester) async {
    await _pump(tester, theme, wrapped: true);
    expect(_probeColor(tester), AppTokens.surface);

    await theme.setPreference(AppThemePreference.dark);
    await tester.pump();

    final Color after = _probeColor(tester);
    expect(after, const Color(0xFF171B22),
        reason: '切换后页面没换成深色 —— AppThemeRebuild 那一层没生效');
  });

  testWidgets('负向对照：同一个页面不包 AppThemeRebuild 就不会换色（"要退出重进"）',
      (tester) async {
    await _pump(tester, theme, wrapped: false);
    final Color before = _probeColor(tester);

    await theme.setPreference(AppThemePreference.dark);
    await tester.pump();

    expect(
      _probeColor(tester),
      before,
      reason: '这条是负向对照：若不包那层也会换色，说明机制变了，'
          'AppThemeRebuild 的设计理由与注释都要重写。',
    );
  });

  testWidgets('跟随系统档：系统亮度变化时也当场换色', (tester) async {
    await _pump(tester, theme, wrapped: true);
    expect(_probeColor(tester), AppTokens.surface);

    theme.updatePlatformBrightness(Brightness.dark);
    await tester.pump();

    expect(_probeColor(tester), const Color(0xFF171B22));
  });

  test('App 顶层挂了 AppThemeScope，路由与 home 都包了 AppThemeRebuild', () {
    final String src = _read('lib/app/app.dart');
    expect(src.contains('AppThemeScope('), isTrue,
        reason: 'app.dart 没挂 AppThemeScope，路由里的页面拿不到依赖，切换不会重建');
    expect(src.contains('AppThemeRebuild(builder: entry.value)'), isTrue,
        reason: '路由入口没包 AppThemeRebuild —— 进二级页面再切深浅不会变');
    expect(src.contains('home: AppThemeRebuild('), isTrue,
        reason: 'home（外壳）没包 AppThemeRebuild —— 首页要下拉刷新才变暗');
  });

  test('页面构造不许写 const（写了深浅切换就会被 Element 短路）', () {
    final RegExp constPage =
        RegExp(r'=> const [A-Z]\w*(Page|Screen|View|Tab|Sheet|Dialog)\b');
    final List<String> bad = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (constPage.hasMatch(lines[i])) {
          bad.add('${e.path}:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: '这些地方用 const 构造页面，深浅切换时页面不会重建：\n${bad.join('\n')}\n'
          '→ 去掉 const（见 lib/app/app_routes.dart 顶部与 analysis_options.yaml 的说明）',
    );
  });

  test('外壳：四个页签用 builder 构建、抽屉不许写 const', () {
    final String src = _read('lib/app/app_shell.dart');
    expect(src.contains('tab.builder()'), isTrue,
        reason: '页签还在用现成的 widget 实例，切换时页面不会重建');
    expect(src.contains('tab.widget'), isFalse,
        reason: '还有 tab.widget 的用法，会绕过重建');
    expect(src.contains('drawer: const AppDrawer()'), isFalse,
        reason: '抽屉写了 const —— 复用同一实例，切换后抽屉保持旧配色');
  });
}
