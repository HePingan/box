// 四个主页面（首页/工具/内容/扩展）共用同一套外壳排版契约。
//
// 悬浮胶囊导航栏（app_shell.dart _buildMobileLayout）不占布局高度，
// AppPageScaffold 的 safeBottom 默认 false，因此底部避让必须由页面显式提供，
// 且必须随机型手势区（viewPadding.bottom）变化 —— 写成常量的页面在大手势区
// 机型上留白相对不足，在小手势区机型上又过度留白。
//
// 这组测试锁三件事：
//   1. AppTokens.shellBottomInset 是唯一的避让算法，且真的跟随 viewPadding
//   2. 四个页面都不再出现「pageBottomPadding + 常量」式的裸底部留白
//   3. 四个页面水平 gutter 一致、hero 卡规格一致
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/design_system/app_tokens.dart';

/// 胶囊导航栏在屏幕底部实际吃掉的高度。
/// margin bottom 6 + 内容 ~49（图标 28 + gap 2 + 文字 ~15 + 竖 padding 4）
double _navOccupied(double viewPaddingBottom) => viewPaddingBottom + 6 + 49;

const _pages = <String, String>{
  '首页': 'lib/features/home/presentation/home_page.dart',
  '工具': 'lib/features/tools/presentation/tool_page.dart',
  '内容': 'lib/features/content/presentation/warehouse_tab.dart',
  '扩展': 'lib/features/extensions/presentation/plugin_tab.dart',
};

/// 读源码并剥掉 `//` 行注释 —— 否则解释性注释里出现的常量名会被误判成用法。
String _read(String path) {
  return File(path)
      .readAsLinesSync()
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
}

void main() {
  group('shellBottomInset 契约', () {
    testWidgets('随手势区变化，且始终大于导航栏实占高度', (tester) async {
      for (final vp in <double>[0, 24, 34, 48]) {
        late double inset;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: vp)),
            child: Builder(
              builder: (context) {
                inset = AppTokens.shellBottomInset(context);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(
          inset,
          greaterThan(_navOccupied(vp)),
          reason: 'viewPadding=$vp 时避让高度必须超过导航栏实占',
        );
      }
    });

    testWidgets('extra 参数可为编辑态等场景加高', (tester) async {
      late double base;
      late double raised;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 24)),
          child: Builder(
            builder: (context) {
              base = AppTokens.shellBottomInset(context);
              raised = AppTokens.shellBottomInset(context, extra: 96);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(raised, greaterThan(base));
      expect(raised - base, 96 - AppTokens.shellBottomInsetExtra);
    });
  });

  group('四个主页面排版一致性', () {
    test('都不再使用 pageBottomPadding 作为底部留白', () {
      final offenders = <String>[];
      _pages.forEach((name, path) {
        if (_read(path).contains('pageBottomPadding')) {
          offenders.add('$name ($path)');
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '底部留白必须走 AppTokens.shellBottomInset，'
            'pageBottomPadding 是不跟随手势区的常量：$offenders',
      );
    });

    test('都通过 AppPageScaffold 统一下发底部避让', () {
      final missing = <String>[];
      _pages.forEach((name, path) {
        final src = _read(path);
        // B 阶段后页面不再自行调用 shellBottomInset，而是
        // shellInset: true 由 scaffold 下发 + bottomInsetOf 读取。
        final ok = src.contains('shellInset: true') &&
            src.contains('AppPageScaffold.bottomInsetOf');
        if (!ok) missing.add('$name ($path)');
      });
      expect(missing, isEmpty, reason: '缺少统一底部避让：$missing');
    });

    test('水平 gutter 统一为 shellPageGutter', () {
      final missing = <String>[];
      _pages.forEach((name, path) {
        if (!_read(path).contains('shellPageGutter')) {
          missing.add('$name ($path)');
        }
      });
      expect(missing, isEmpty, reason: '水平边距未统一：$missing');
    });

    test('四页都设置统一的 maxContentWidth（B 阶段）', () {
      final missing = <String>[];
      _pages.forEach((name, path) {
        if (!_read(path).contains('shellMaxContentWidth')) {
          missing.add('$name ($path)');
        }
      });
      expect(missing, isEmpty, reason: '桌面断点下内容宽度未统一：$missing');
    });
  });

  group('hero 卡规格统一', () {
    const heroCards = <String, String>{
      '工具': 'lib/features/tools/presentation/tool_page.dart',
      '内容': 'lib/features/content/presentation/widgets/warehouse_widgets.dart',
      '扩展':
          'lib/features/extensions/presentation/widgets/extension_management_widgets.dart',
    };

    test('不再出现游离的 0xFFE9EEF7 边框色', () {
      final offenders = <String>[];
      heroCards.forEach((name, path) {
        if (_read(path).contains('0xFFE9EEF7')) {
          offenders.add('$name ($path)');
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '卡片边框统一 AppTokens.cardBorder(0xFFE7ECF5)：$offenders',
      );
    });

    test('radiusMd 为 18，作为 hero 卡统一圆角', () {
      expect(AppTokens.radiusMd, 18);
    });
  });
}
