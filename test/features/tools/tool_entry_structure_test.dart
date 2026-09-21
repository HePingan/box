// 工具页 B2：结构契约 —— 可用能力平铺置顶，未接线条目降级进折叠区。
//
// 背景（A 阶段之后仍然存在的结构问题）：
// 目录里 112 个条目只有 15 个真的能用，但页面把两者混在同一批分类卡片里，
// 按「日常/系统/图片…」分组折叠。用户要点开 10 张卡片、在 112 个 chip 里
// 逐个看徽标才能找出哪 15 个是活的。首屏最显眼的位置给了「扬声器清灰」
// 「舔狗日记」这类占位条目，而真正实现了的图书搜索/英文词典藏在第 4 张卡里。
//
// 同时页面顶部另有一条手写的快捷 chip 行（二维码/Mock用户/头像/占位图/API清单），
// 把 5 个 registry id 又抄了一遍 —— 同一个能力两个入口，且这份名单和
// kToolTargets 各自漂移。
//
// 所以本文件断言的结构契约是：
//   1. 目录条目升级成 ToolEntry 模型（名字 + 分类归属 + 去向），可用性由 target
//      派生，不再由 UI 各自 where(isToolAvailable) 现算。
//   2. 可用条目平铺在首屏，无需展开任何分组即可看到全部 15 个。
//   3. 未接线条目整体收进一个默认折叠的「计划中」区，点开才展开。
//   4. 可用区在计划区之上。
//   5. 页面里不再有第二份手抄的快捷入口名单。
library;

import 'dart:io';

import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/features/tools/domain/custom_site_store.dart';
import 'package:box/features/tools/presentation/tool_page.dart';
import 'package:box/features/tools/presentation/widgets/planned_tools_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 去掉 `//` 行注释，避免源码扫描断言被解释性注释误伤。
String _stripLineComments(String src) => src
    .split('\n')
    .map((line) {
      final idx = line.indexOf('//');
      return idx == -1 ? line : line.substring(0, idx);
    })
    .join('\n');

/// 独立算一遍「按目录顺序展开的全部条目名」，用于和被测 API 对账。
List<String> _catalogOrderNames() {
  final names = <String>[];
  for (final category in createDefaultToolCategories()) {
    names.addAll(category.tools);
  }
  return names;
}

Future<void> _pumpToolPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: ToolPage()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // 「我的收藏」区块走 SharedPreferences 钩子，测试环境没有平台实现。
    CustomSiteStore.readRaw = () async => null;
    CustomSiteStore.writeRaw = (_) async {};
  });

  tearDown(CustomSiteStore.resetHooksForTest);

  group('ToolEntry 模型：条目自带分类归属与去向', () {
    test('allToolEntries 覆盖目录全部条目，顺序与目录一致', () {
      final entries = allToolEntries();
      expect(
        entries.map((e) => e.name).toList(),
        equals(_catalogOrderNames()),
        reason: '条目列表应是目录的忠实展开，顺序不能被 Map 的键序打乱',
      );
    });

    test('每个条目都带非空分类归属，平铺后仍能显示它来自哪一类', () {
      for (final entry in allToolEntries()) {
        expect(
          entry.category.trim(),
          isNotEmpty,
          reason: '${entry.name} 没有分类归属，平铺网格里就没法标注来源',
        );
      }
    });

    test('available 完全由 target 派生，不是另存一份布尔值', () {
      for (final entry in allToolEntries()) {
        expect(
          entry.available,
          entry.target != null,
          reason: '${entry.name} 的 available 与 target 不一致',
        );
        expect(
          entry.available,
          isToolAvailable(entry.name),
          reason: '${entry.name} 的可用性和 kToolTargets 漂移了',
        );
      }
    });

    test('availableToolEntries 就是目录顺序下所有已接线条目', () {
      final expected = _catalogOrderNames().where(isToolAvailable).toList();

      final actual = availableToolEntries();
      expect(actual.map((e) => e.name).toList(), equals(expected));
      expect(actual, isNotEmpty);
      expect(
        actual.length,
        kToolTargets.length,
        reason: '映射表里有 ${kToolTargets.length} 个已接线工具，平铺区必须一个不漏',
      );
      for (final entry in actual) {
        expect(entry.target, isNotNull);
      }
    });

    test('plannedToolCategories 只装未接线条目，且不留空分类', () {
      final planned = plannedToolCategories();
      expect(planned, isNotEmpty);

      for (final category in planned) {
        expect(
          category.tools,
          isNotEmpty,
          reason: '${category.title} 变成空分类了，折叠区里不该出现空壳',
        );
        for (final name in category.tools) {
          expect(
            isToolAvailable(name),
            isFalse,
            reason: '$name 已接线，不该再出现在「计划中」里 —— 一个能力两个入口',
          );
        }
      }
    });

    test('可用平铺 + 计划折叠 = 目录全集，无重复无遗漏', () {
      final flattened = <String>[
        ...availableToolEntries().map((e) => e.name),
        ...plannedToolCategories().expand((c) => c.tools),
      ];

      expect(
        flattened.toSet().length,
        flattened.length,
        reason: '同一个条目同时出现在两个区里',
      );
      expect(
        flattened.toSet(),
        equals(_catalogOrderNames().toSet()),
        reason: '重排之后有条目丢了，用户到不了',
      );
    });
  });

  group('首屏结构：可用能力平铺置顶', () {
    testWidgets('无需展开任何分组，首屏就能看到全部已接线工具', (tester) async {
      await _pumpToolPage(tester);

      for (final entry in availableToolEntries()) {
        expect(
          find.text(entry.name),
          findsOneWidget,
          reason: '${entry.name} 已接线，必须平铺在首屏而不是藏在折叠分组里',
        );
      }
    });

    testWidgets('未接线条目默认收起，不占首屏', (tester) async {
      await _pumpToolPage(tester);

      // 「每日早报」「在线翻译」属于旧结构里默认展开的「日常工具」分类，
      // 拿它们才能证明折叠区真的生效 —— 只挑本来就折叠的分类等于不测。
      for (final name in ['每日早报', '在线翻译', '扬声器清灰', '舔狗日记', '扫雷']) {
        expect(isToolAvailable(name), isFalse, reason: '$name 应是未接线条目');
        expect(
          find.text(name),
          findsNothing,
          reason: '$name 还没做，默认展开只会把可用能力推到屏幕外',
        );
      }
    });

    testWidgets('点开「计划中」才展开占位条目', (tester) async {
      await _pumpToolPage(tester);

      final header = find.textContaining('计划中');
      expect(header, findsWidgets, reason: '折叠区需要一个可点的标题');

      await tester.tap(header.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('系统操作'), findsWidgets);
    });

    testWidgets('可用区排在计划区上方', (tester) async {
      await _pumpToolPage(tester);

      final availableDy = tester.getTopLeft(find.text('图书搜索')).dy;
      final plannedDy = tester.getTopLeft(find.textContaining('计划中').first).dy;

      expect(availableDy, lessThan(plannedDy), reason: '能用的东西必须在没做完的东西上面');
    });

    testWidgets('平铺网格里点已接线工具，直接进对应能力页', (tester) async {
      await _pumpToolPage(tester);

      await tester.tap(find.text('图书搜索'));
      await tester.pumpAndSettle();

      expect(
        find.byType(ApiHubPage),
        findsOneWidget,
        reason: '平铺网格的点击派发没接上 kToolTargets',
      );
    });
  });

  group('搜索仍能找到计划中的条目', () {
    testWidgets('搜到未接线条目时自动展开，不让用户搜到了却看不见', (tester) async {
      await _pumpToolPage(tester);

      await tester.enterText(find.byType(TextField).first, '扫雷');
      await tester.pumpAndSettle();

      // 搜索会把分类 tools 滤成只剩「扫雷」。折叠预览副标题是
      // `previewTools.join(' / ')`，滤完恰好等于「扫雷」四个字。
      // 裸 find.text / 只在 PlannedToolsSection 里找，都会把预览当芯片，
      // 搜到了却点不开。芯片只活在展开后的 Wrap 里，点它才会弹「还没做」。
      final chip = find.descendant(
        of: find.descendant(
          of: find.byType(PlannedToolsSection),
          matching: find.byType(Wrap),
        ),
        matching: find.text('扫雷'),
      );
      expect(chip, findsOneWidget, reason: '命中的占位条目必须展开成可点 chip，不能只停在折叠预览文案');

      await tester.tap(chip);
      await tester.pump();
      expect(
        find.text('【扫雷】还没做，先别点了'),
        findsOneWidget,
        reason: '必须是可点 chip：折叠预览点上去只会展开分类，弹不出「还没做」',
      );
    });
  });

  group('页面里不再有第二份手抄入口名单', () {
    test('tool_page.dart 不硬编码 registry id', () {
      final src = _stripLineComments(
        File(
          'lib/features/tools/presentation/tool_page.dart',
        ).readAsStringSync(),
      );

      for (final id in ["'qr'", "'dummy_image'", "'avatar'", "'directory'"]) {
        expect(
          src.contains(id),
          isFalse,
          reason: '$id 又被抄进页面了，去向应该只由 kToolTargets 决定',
        );
      }
    });

    test('快捷 chip 行已撤：它把 5 个能力做成了第二个入口', () {
      final src = _stripLineComments(
        File(
          'lib/features/tools/presentation/tool_page.dart',
        ).readAsStringSync(),
      );
      expect(src.contains('Mock用户'), isFalse, reason: '可用能力已经平铺置顶，快捷行属于重复入口');
    });
  });
}
