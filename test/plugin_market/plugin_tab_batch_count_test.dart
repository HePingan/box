// P2-7 子项2 回归测试：批量启用计数必须只统计「真的被启用」的插件。
//
// 修复前的真实缺陷：_batchToggleEnabled 里 changedCount++ 无条件执行，
// 而 _togglePluginEnabled 对「已下架/风险」插件会弹提示并拒绝（return）。
// 批量启用 3 个插件（其中 1 个已下架）时 UI 提示「已启用 3 个」，
// 实际只有 2 个被启用 —— 数字与真实状态不符，误导用户。
//
// 走真 UI 路径：mount PluginTab → 批量模式 → 全选 → 点「启用」，
// 断言 SnackBar 计数 + 插件宿主里的真实启用状态。

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/presentation/plugin_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final host = HomePluginHost.instance;
    host.resetForTesting();
    // widget 测试的 FakeAsync zone 里，默认 CacheStore 走 path_provider +
    // dart:io，await 永不完成（register / toggleEnabled 整条写路径挂死，
    // 实测卡死 300s+）。注入内存实现后批量链路纯 microtask 完成，
    // 测到的才是真实计数逻辑。
    host.injectPersistenceForTesting(
      HomePluginPersistence(cache: CacheStore.inMemory('home_plugin_center')),
    );
    // 空基线 + 已 bootstrap：内置插件不混入选择范围。
    host.seedForTesting(const <HomePlugin>[]);
  });

  tearDown(() {
    HomePluginHost.instance.resetForTesting();
  });

  HomeCustomPluginConfig pluginConfig(
    String id, {
    bool enabled = false,
    String status = 'published',
    bool risk = false,
  }) => HomeCustomPluginConfig(
    id: id,
    title: '插件-$id',
    subtitle: '',
    iconCodePoint: 0xe1bd,
    colorValue: 0xFF112233,
    area: HomePluginArea.recommend,
    actionType: HomePluginActionType.toast,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    origin: 'local',
    enabled: enabled,
    marketStatus: status,
    marketRisk: risk,
    marketVersion: '1.0',
  );

  Future<void> mountTab(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PluginTab())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterBatchAndSelectAll(WidgetTester tester) async {
    await tester.tap(find.byTooltip('批量操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
  }

  /// 消费 SnackBar 队列（每个默认 4s），避免测试结束时 pending timer 报错。
  Future<void> drainSnacks(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('批量启用含 1 个已下架插件：计数只算真实启用数，并提示被拒项', (tester) async {
    final host = HomePluginHost.instance;
    await host.addCustomPlugin(pluginConfig('batch_ok_a'));
    await host.addCustomPlugin(pluginConfig('batch_ok_b'));
    await host.addCustomPlugin(
      pluginConfig('batch_yanked', status: 'yanked', risk: true),
    );

    await mountTab(tester);
    await enterBatchAndSelectAll(tester);

    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();

    // 第一个 snack 是单插件拒绝提示（已下架）……
    expect(find.textContaining('已下架'), findsWidgets);

    // ……推进 4s 让汇总 snack 上台
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 汇总计数必须只含真实启用的 2 个（修复前是 3）
    expect(find.textContaining('已启用 2 个'), findsOneWidget);
    // 且必须如实告知有 1 个被拒
    expect(find.textContaining('1 个未能启用'), findsOneWidget);

    // 真实状态与文案一致：2 启用、1 仍禁用
    expect(host.findById('batch_ok_a')!.enabled, isTrue);
    expect(host.findById('batch_ok_b')!.enabled, isTrue);
    expect(host.findById('batch_yanked')!.enabled, isFalse);

    await drainSnacks(tester);
  });

  testWidgets('批量启用全部正常插件：计数如实为 3', (tester) async {
    final host = HomePluginHost.instance;
    await host.addCustomPlugin(pluginConfig('all_ok_1'));
    await host.addCustomPlugin(pluginConfig('all_ok_2'));
    await host.addCustomPlugin(pluginConfig('all_ok_3'));

    await mountTab(tester);
    await enterBatchAndSelectAll(tester);

    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已启用 3 个'), findsOneWidget);
    expect(find.textContaining('未能启用'), findsNothing);
    expect(host.findById('all_ok_1')!.enabled, isTrue);
    expect(host.findById('all_ok_2')!.enabled, isTrue);
    expect(host.findById('all_ok_3')!.enabled, isTrue);

    await drainSnacks(tester);
  });

  testWidgets('批量禁用方向：无拦截路径，计数如实为 2', (tester) async {
    final host = HomePluginHost.instance;
    await host.addCustomPlugin(pluginConfig('dis_on_1', enabled: true));
    await host.addCustomPlugin(pluginConfig('dis_on_2', enabled: true));

    await mountTab(tester);
    await enterBatchAndSelectAll(tester);

    await tester.tap(find.text('禁用'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已禁用 2 个'), findsOneWidget);
    expect(host.findById('dis_on_1')!.enabled, isFalse);
    expect(host.findById('dis_on_2')!.enabled, isFalse);

    await drainSnacks(tester);
  });
}
