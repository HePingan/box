// 工具页结构契约（2026-10-03 重设计后）。
//
// 背景 —— 改前的两个病（都有实测）：
//   * 66 个可用工具**平铺**成 3 列 22 行 ≈ 2660px ≈ 4~5 屏，分类信息只剩卡片
//     底部 9.5px 的小字；"我不知道有什么工具"这条浏览路径等于没有。
//   * 「计划中」区把 56 条**没做的**工具当承诺摆出来（点进去只弹一句
//     「还没做，先别点了」），每个条目都是一次失望点击，还把真能用的往下挤一屏。
//
// 新的结构契约：
//   1. 目录条目仍然是 ToolEntry 模型（名字 + 分类归属 + 去向），可用性由 target 派生。
//   2. 可用条目按**分类分区**呈现（区标题带计数），折叠态只露第一行 + 「还有 N 个」。
//   3. 分类芯片能一次跳到某一区；「离线可用」开关只留纯本地工具。
//   4. 未接线条目**一个字都不上界面**（名单只留在目录里），搜索也搜不到承诺。
//   5. 顶部指标只报真数（可用条数 / 命中数），不报"计划"。
//   6. 页面里不再有第二份手抄的入口名单。
library;

import 'dart:io';

import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/features/tools/application/tool_usage_store.dart';
import 'package:box/features/tools/domain/custom_site_store.dart';
import 'package:box/features/tools/presentation/tool_page.dart';
import 'package:box/features/tools/presentation/widgets/tool_sections.dart';
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
  setUp(() async {
    // 「我的收藏」与「使用记录」都走 SharedPreferences 钩子，测试环境没有平台实现。
    CustomSiteStore.readRaw = () async => null;
    CustomSiteStore.writeRaw = (_) async {};
    ToolUsageStore.readRaw = () async => null;
    ToolUsageStore.writeRaw = (_) async {};
    await ToolUsageStore.instance.clear();
  });

  tearDown(() {
    CustomSiteStore.resetHooksForTest();
    ToolUsageStore.resetHooksForTest();
  });

  group('ToolEntry 模型：条目自带分类归属与去向', () {
    test('allToolEntries 覆盖目录全部条目，顺序与目录一致', () {
      final entries = allToolEntries();
      expect(
        entries.map((e) => e.name).toList(),
        equals(_catalogOrderNames()),
        reason: '条目列表应是目录的忠实展开，顺序不能被 Map 的键序打乱',
      );
    });

    test('每个条目都带非空分类归属，分区时仍能显示它来自哪一类', () {
      for (final entry in allToolEntries()) {
        expect(
          entry.category.trim(),
          isNotEmpty,
          reason: '${entry.name} 没有分类归属，分区标题就对不上',
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
        reason: '映射表里有 ${kToolTargets.length} 个已接线工具，页面上必须一个不漏',
      );
      for (final entry in actual) {
        expect(entry.target, isNotNull);
      }
    });

    test('未接线名单 = 目录 ∖ 已接线，既不重复也不丢；名单只在目录里，不上界面', () {
      final unwired = unwiredToolNames();
      expect(unwired, isNotEmpty, reason: '目录里仍要保留这份名单（分类归属与后续接线都要用）');

      final flattened = <String>[
        ...availableToolEntries().map((e) => e.name),
        ...unwired,
      ];
      expect(
        flattened.toSet().length,
        flattened.length,
        reason: '同一个条目既算可用又算未接线',
      );
      expect(
        flattened.toSet(),
        equals(_catalogOrderNames().toSet()),
        reason: '重排之后有条目从名单里丢了',
      );
      for (final name in unwired) {
        expect(isToolAvailable(name), isFalse, reason: '$name 已接线，不该算未接线');
      }
    });
  });

  group('首屏结构：按分类分区 + 折叠态只露一行', () {
    testWidgets('顶部指标只报真数，不再出现「计划」', (tester) async {
      await _pumpToolPage(tester);

      expect(
        find.text('${availableToolEntries().length} 个工具'),
        findsOneWidget,
        reason: '指标应显示真实可用条数',
      );
      expect(
        find.textContaining('计划'),
        findsNothing,
        reason: '把未完成项当用户指标报，和扩展页那两个恒 0 的死数字同一族病',
      );
    });

    testWidgets('分区标题出现，且折叠态只露第一行 + 「还有 N 个」', (tester) async {
      await _pumpToolPage(tester);

      expect(find.text('开发工具'), findsOneWidget, reason: '分区标题要能扫到');
      // 开发工具 13 个，6 列 → 折叠态露 6 个、收 7 个。
      expect(
        find.textContaining('还有 '),
        findsWidgets,
        reason: '截断了就要说清还剩多少，不能让用户以为这个分类只有 6 个',
      );
      expect(find.text('正则测试'), findsNothing, reason: '折叠态里第 7 个工具不该已经出现');
    });

    testWidgets('点「还有 N 个」把这一区展开', (tester) async {
      await _pumpToolPage(tester);

      // 必须点「开发工具」那一区自己的收口格子 —— find.textContaining('还有 ')
      // 的第一个是第一区（日常工具）的，展开它证明不了「开发工具」的行为。
      final devSection = find.ancestor(
        of: find.text('开发工具'),
        matching: find.byType(ToolCategorySection),
      );
      await tester.tap(
        find.descendant(of: devSection, matching: find.textContaining('还有 ')),
      );
      await tester.pumpAndSettle();

      expect(find.text('正则测试'), findsOneWidget, reason: '展开后要把这一区剩下的工具都放出来');
    });

    testWidgets('点分类芯片 = 只看这一类，且直接展开', (tester) async {
      await _pumpToolPage(tester);

      await tester.tap(find.text('开发工具 ${_countOfCategory('开发工具')}'));
      await tester.pumpAndSettle();

      expect(
        find.text('正则测试'),
        findsOneWidget,
        reason: '点了分类芯片 = 明确要看这一类，不该还要求再展开一次',
      );
      expect(
        find.text('日常工具'),
        findsNothing,
        reason: '只看这一类：不然点第 5 个分类还得自己往下滚四次，「一次点击就到」是空话',
      );

      // 回到「全部」：其他区都回来。
      await tester.tap(find.textContaining('全部 '));
      await tester.pumpAndSettle();
      expect(find.text('日常工具'), findsOneWidget);
    });

    testWidgets('「离线可用」只留纯本地工具', (tester) async {
      await _pumpToolPage(tester);

      // 科学计算器是「计算工具」区的第一个，折叠态也看得见；
      // 它同时也在「常用」推荐行里，所以用 findsWidgets。
      expect(find.text('科学计算器'), findsWidgets, reason: '本地工具默认在');

      // 「离线可用」是全局开关，排在「全部」旁边 —— 一屏就够得着，不用横滑去找。
      await tester.tap(find.text('离线可用'));
      await tester.pumpAndSettle();

      expect(find.text('科学计算器'), findsWidgets, reason: '纯本地工具必须留下');
      // 联网工具消失：天气预报(API) 与 在线PS(WebView)。
      expect(find.text('天气预报'), findsNothing);
      expect(find.text('在线PS'), findsNothing);
    });

    testWidgets('窄屏（360dp）不溢出：芯片横滑、卡片 4 列', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: ToolPage()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '最常见的手机宽度下不该有 overflow');
      expect(find.text('${availableToolEntries().length} 个工具'), findsOneWidget);
      expect(find.text('离线可用'), findsOneWidget, reason: '全局开关要不横滑就够得着');
    });

    testWidgets('平铺网格里点已接线工具，直接进对应能力页', (tester) async {
      await _pumpToolPage(tester);

      await tester.tap(find.text('图书搜索'));
      await tester.pumpAndSettle();

      expect(
        find.byType(ApiHubPage),
        findsOneWidget,
        reason: '分区的点击派发没接上 kToolTargets',
      );
    });
  });

  group('未接线条目一个字都不上界面', () {
    testWidgets('页面上看不到未接线的工具名', (tester) async {
      await _pumpToolPage(tester);

      for (final name in ['扫雷', '扬声器清灰', '舔狗日记', '每日早报']) {
        expect(isToolAvailable(name), isFalse, reason: '$name 应是未接线条目');
        expect(
          find.text(name),
          findsNothing,
          reason: '$name 还没做 —— 摆出来就是一次失望点击',
        );
      }
    });

    testWidgets('搜未接线的工具名：说实话，不给承诺', (tester) async {
      await _pumpToolPage(tester);

      await tester.enterText(find.byType(TextField).first, '扫雷');
      await tester.pumpAndSettle();

      // 注意：查询词本身会出现在 TextField 里，所以不能直接 find.text('扫雷') ——
      // 只断言「没有一张工具卡叫扫雷」。
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == '扫雷',
          description: '名为「扫雷」的工具卡',
        ),
        findsNothing,
      );
      expect(
        find.text('没有匹配的工具。'),
        findsOneWidget,
        reason: '搜不到就说搜不到；改前会自动展开「计划中」把没做的摆出来',
      );
      expect(find.textContaining('计划'), findsNothing);
    });

    testWidgets('搜索命中分类名时，命中整类', (tester) async {
      await _pumpToolPage(tester);

      await tester.enterText(find.byType(TextField).first, '计算');
      await tester.pumpAndSettle();

      expect(find.text('计算工具'), findsOneWidget, reason: '分类名命中要能带出这一区');
      expect(find.text('科学计算器'), findsWidgets);
      expect(
        find.text('匹配 ${_matchCountOf('计算')} 个'),
        findsOneWidget,
        reason: '命中数用真数',
      );
    });
  });

  group('「想要什么工具」有能兑现的出口', () {
    testWidgets('页面底部写着这条路，点了能到关于页', (tester) async {
      tester.view.physicalSize = const Size(1100, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: const ToolPage(),
          routes: {'about': (_) => const Scaffold(body: Text('关于页到了'))},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('想要什么工具？'),
        findsOneWidget,
        reason: '「计划中」撤掉之后，想要的工具得有个真出口',
      );

      await tester.tap(find.text('想要什么工具？'));
      await tester.pumpAndSettle();
      expect(find.text('关于页到了'), findsOneWidget);
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

    test('tool_page.dart 不再引用「计划中」那套东西', () {
      final src = _stripLineComments(
        File(
          'lib/features/tools/presentation/tool_page.dart',
        ).readAsStringSync(),
      );

      for (final dead in [
        'plannedToolCategories',
        'PlannedToolsSection',
        'ExpandableCategoryCard',
        '计划中',
      ]) {
        expect(src.contains(dead), isFalse, reason: '$dead 已经撤掉了，别再长回来');
      }
    });
  });
}

int _countOfCategory(String title) =>
    availableToolEntries().where((e) => e.category == title).length;

int _matchCountOf(String query) {
  final q = query.toLowerCase();
  return availableToolEntries()
      .where(
        (e) =>
            e.name.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q),
      )
      .length;
}
