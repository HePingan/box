// 工具「常用/最近」这一行的数据层与接线（2026-10-03）。
//
// 为什么需要它：工具页有 66 个可用入口，搜索解决「我知道我要什么」，
// 但「我天天用的是那个」得靠记录 —— 否则每次都要重新滚 4~5 屏或重新打字。
// ApiHub 页原来有一份写死的「最近使用」列表（6 个硬编码 id，重启就回到原样），
// 工具页没有；这里做成一份真实记录，两边读同一份。
//
// 契约：
//   1. 计数与「最后一次使用时间」都从真实点击产生，写盘后才通知（读到的必须是落地的值）。
//   2. 排序是「次数优先、最近其次」—— 一眼能看懂的规则，不用需要调参的 frecency 公式。
//   3. 存储损坏当作空记录；条数有上限，不会无限增长。
//   4. **不进备份**（BackupPrefKeys 里没有它）：使用痕迹是设备本地的，恢复到新机没意义。
//   5. 一条记录都没有时，界面给的是**推荐**（标题写「试试这些」），不冒充「常用」。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:box/features/tools/application/tool_usage_store.dart';
import 'package:box/features/tools/presentation/widgets/available_tool_grid.dart';
import 'package:box/features/tools/presentation/widgets/tool_sections.dart';
import 'package:box/features/backup/backup_pref_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String?> store;

  setUp(() async {
    store = <String, String?>{};
    ToolUsageStore.readRaw = () async => store[ToolUsageStore.prefsKey];
    ToolUsageStore.writeRaw = (raw) async =>
        store[ToolUsageStore.prefsKey] = raw;
    await ToolUsageStore.instance.clear();
    // 时间可控：排序用例必须断言「最近其次」，不能让真实时钟搅进来。
    ToolUsageStore.nowMs = () => 1000;
  });

  tearDown(() {
    ToolUsageStore.resetHooksForTest();
    ToolUsageStore.nowMs = () => DateTime.now().millisecondsSinceEpoch;
  });

  group('ToolUsageStore', () {
    test('记录一次：次数 1、有时间戳，并且已落盘', () async {
      await ToolUsageStore.instance.record('科学计算器');

      expect(ToolUsageStore.instance.countOf('科学计算器'), 1);
      expect(store[ToolUsageStore.prefsKey], isNotNull, reason: '必须写盘');

      final decoded = jsonDecode(store[ToolUsageStore.prefsKey]!) as Map;
      expect(decoded.keys, contains('科学计算器'));
    });

    test('重复记录累加次数', () async {
      await ToolUsageStore.instance.record('JSON格式化');
      await ToolUsageStore.instance.record('JSON格式化');

      expect(ToolUsageStore.instance.countOf('JSON格式化'), 2);
    });

    test('排序：次数优先，次数相同看谁更近用过', () async {
      ToolUsageStore.nowMs = () => 100;
      await ToolUsageStore.instance.record('秒表');
      ToolUsageStore.nowMs = () => 200;
      await ToolUsageStore.instance.record('指南针');
      // 秒表用两次（第二次最近）
      ToolUsageStore.nowMs = () => 300;
      await ToolUsageStore.instance.record('秒表');

      expect(ToolUsageStore.instance.recentNames(), [
        '秒表',
        '指南针',
      ], reason: '两次的排在一次的前面');

      // 次数打平之后，最近用过的在前。
      ToolUsageStore.nowMs = () => 400;
      await ToolUsageStore.instance.record('指南针');
      expect(ToolUsageStore.instance.recentNames().first, '指南针');
    });

    test('冷启动重新读盘：次数与时间都还在', () async {
      await ToolUsageStore.instance.record('进制转换');
      await ToolUsageStore.instance.record('进制转换');

      // 单例自己记着 `_loaded`，没法自证「重新读」—— 用一个独立实例读同一份存储。
      final reloaded = ToolUsageStore.forTest();
      await reloaded.ensureLoaded();

      expect(reloaded.countOf('进制转换'), 2, reason: '重启后计数不能归零');
      expect(reloaded.recentNames(), ['进制转换']);
    });

    test('写盘内容是可读 JSON（能人工排查）', () async {
      await ToolUsageStore.instance.record('秒表');

      final payload = jsonDecode(store[ToolUsageStore.prefsKey]!) as Map;
      expect((payload['秒表'] as Map)['c'], 1);
    });

    test('存储损坏时当作空记录，不抛', () async {
      store[ToolUsageStore.prefsKey] = '{坏掉的 json';
      final fresh = ToolUsageStore.instance;
      // 先把 loaded 状态骗回去，模拟冷启动。
      await fresh.clear();
      store[ToolUsageStore.prefsKey] = '{坏掉的 json';
      await fresh.ensureLoaded();

      expect(fresh.recentNames(), isEmpty);
      expect(fresh.loaded, isTrue, reason: '读过了（只是没内容），不是「还没读」');
    });

    test('条数有上限，只留次数最多的那些', () async {
      for (var i = 0; i < ToolUsageStore.maxRecords + 5; i++) {
        await ToolUsageStore.instance.record('工具$i');
      }

      expect(
        ToolUsageStore.instance.recentNames(limit: 100).length,
        ToolUsageStore.maxRecords,
        reason: '不能无限增长',
      );
    });

    test('使用记录不进备份', () {
      expect(
        BackupPrefKeys.fixedKeys.contains(ToolUsageStore.prefsKey),
        isFalse,
        reason: '使用痕迹是这台设备上的行为记录，恢复到新机没有意义',
      );
    });
  });

  group('接线：点工具就记一笔', () {
    testWidgets('openToolTarget 先记使用再跳转', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      // 用未接线目标走 null 分支：只弹提示，不开新页（避免测试里真去拉网络）。
      await openToolTarget(ctx, '扫雷', null);

      expect(
        ToolUsageStore.instance.countOf('扫雷'),
        1,
        reason: '派发点是唯一记录处，跳转与否都要记',
      );
    });
  });

  group('页面顶部那一行', () {
    testWidgets('一条记录都没有时给推荐，并写明是推荐', (tester) async {
      // 折叠态下给的是目录里真实存在的工具（页面就是这么传的）。
      final defaults = availableToolEntries()
          .where((e) => e.name == '天气预报')
          .toList();
      expect(defaults, isNotEmpty, reason: '推荐集里的名字必须在目录里真实存在');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentToolsRow(entries: defaults, usingDefaults: true),
          ),
        ),
      );

      expect(find.text('试试这些'), findsOneWidget);
      expect(find.text('常用'), findsNothing, reason: '没有记录就不能自称「常用」');
      expect(find.text('用过的工具会记在这里'), findsOneWidget);
    });

    testWidgets('有记录时显示真实条目', (tester) async {
      await ToolUsageStore.instance.record('科学计算器');
      final entries = availableToolEntries()
          .where((e) => e.name == '科学计算器')
          .toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentToolsRow(entries: entries, usingDefaults: false),
          ),
        ),
      );

      expect(find.text('常用'), findsOneWidget);
      expect(find.text('科学计算器'), findsOneWidget);
    });
  });

  group('ApiHub 页的「最近使用」也读这份记录（不再是写死的 6 个 id）', () {
    MockClient stubClient() => MockClient(
      (request) async => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    Future<void> pumpHub(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ApiHubPage(httpClientForTesting: stubClient())),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    test('面板 id → 工具名（记一笔时用的反查）', () {
      expect(toolNameForApiHubPanel('weather'), '天气预报');
      expect(toolNameForApiHubPanel('currency'), '汇率换算');
      expect(
        toolNameForApiHubPanel('no_such_panel_xyz'),
        isNull,
        reason: '面板没有对应的工具入口时就不记 —— 不硬造一个名字凑数',
      );
    });

    testWidgets('一条记录都没有时，「最近使用」整块不渲染', (tester) async {
      await pumpHub(tester);

      expect(
        find.text('最近使用'),
        findsNothing,
        reason: '拿没点过的工具冒充「最近使用」，和「计划中」是同一类假承诺',
      );
    });

    testWidgets('有记录时渲染出对应面板，点它还会再记一笔', (tester) async {
      await ToolUsageStore.instance.record('天气预报');
      await ToolUsageStore.instance.record('汇率换算');
      await pumpHub(tester);

      expect(find.text('最近使用'), findsOneWidget);

      final weatherTitle = PublicApiRegistry.tryById('weather')!.title;
      expect(find.text(weatherTitle), findsWidgets);

      await tester.tap(find.text(weatherTitle).first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        ToolUsageStore.instance.countOf('天气预报'),
        2,
        reason: '在 ApiHub 里切面板也要记进同一份记录',
      );
    });
  });
}
