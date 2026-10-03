// 扩展页四个缺口的回归用例（2026-10-03）：顺序可调 / 插件详情 / 搜不到去市场 / 全部更新。
//
// 前三个都能挂真 UI 跑：`PluginTab` 可以 mount（见 plugin_tab_batch_count_test.dart 的
// 注入方式：宿主单例 + 内存持久化 + 空基线 seed）。第四个（批量更新）跑不动 ——
// 它要一份**已验签**的市场清单，测试里不该联网，所以那一节钉源码结构：
// 走同一个清单仓库、串行安装、失败逐条留名。

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/features/extensions/presentation/plugin_tab.dart';
import 'package:box/features/extensions/presentation/widgets/extension_management_widgets.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'dart:io';

import 'package:box/plugin_market_page.dart';
import 'package:box/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeManifestRepository extends PluginMarketManifestRepository {
  _FakeManifestRepository(this.manifest);

  final PluginMarketManifest manifest;

  @override
  Future<PluginMarketManifest> loadManifest({
    required List<MarketPluginTemplate> fallbackTemplates,
    required PluginMarketChannel channel,
    required PluginMarketSecurityConfig security,
    String? remoteConfigUrl,
    bool forceRefresh = false,
  }) async => manifest;
}

PluginMarketManifest _manifest(List<MarketPluginTemplate> templates) =>
    PluginMarketManifest(
      version: 2,
      templates: templates,
      source: 'builtin',
      fetchedAt: DateTime(2026, 10, 3, 12, 0),
      channel: PluginMarketChannel.stable,
      signatureVerified: true,
      signatureMode: PluginMarketSignMode.none,
      signatureMessage: '',
      signatureValue: '',
    );

MarketPluginTemplate _template(String id, String title) =>
    MarketPluginTemplate.tryFromJson({
      'id': id,
      'title': title,
      'subtitle': '$title 的说明',
      'areaCode': 'center',
      'version': '1.0.0',
    })!;

HomePlugin _plugin(String id, String title, {int sort = 1000}) => HomePlugin(
  id: id,
  title: title,
  subtitle: '$title 说明',
  icon: Icons.extension_rounded,
  color: const Color(0xFF4F46E5),
  area: HomePluginArea.center,
  sort: sort,
  onTap: (context) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HomePluginHost host;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    host = HomePluginHost.instance;
    host.resetForTesting();
    host.injectPersistenceForTesting(
      HomePluginPersistence(cache: CacheStore.inMemory('plugin_tab_next')),
    );
    host.seedForTesting(<HomePlugin>[
      _plugin('p-a', '甲插件', sort: 100),
      _plugin('p-b', '乙插件', sort: 200),
      _plugin('p-c', '丙插件', sort: 300),
    ]);
  });

  /// 用例收尾：插件页会拉市场推荐（测试里 400）+ 写日志，
  /// 两者的定时器都要烧掉，否则 flutter_test 报「A Timer is still pending…」。
  Future<void> flushPendingTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await AppLogger.instance.flush();
  }

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PluginTab()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  List<String> enabledIds() =>
      host.allPlugins.where((p) => p.enabled).map((p) => p.id).toList();

  testWidgets('插件详情：信息按钮弹出已写好却没人调的面板（含 ID 与来源）', (tester) async {
    await pumpTab(tester);

    // 这个面板全仓此前零调用点 —— 点卡片是直接运行插件，看不到"是谁、从哪来"。
    await tester.tap(find.byTooltip('插件详情').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PluginDetailSheet), findsOneWidget);
    expect(find.text('p-a'), findsOneWidget, reason: '面板要给出插件 ID');
    expect(find.text('自定义'), findsWidgets, reason: '来源要写清（内置 or 自定义）');
    await flushPendingTimers(tester);
  });

  testWidgets('调整顺序：排序模式下上移一格，顺序真的变了', (tester) async {
    await pumpTab(tester);
    expect(enabledIds(), <String>['p-a', 'p-b', 'p-c']);

    await tester.tap(find.byTooltip('调整顺序'));
    await tester.pump();

    // 乙插件上移 → 应变成 乙、甲、丙。
    final upButtons = find.byTooltip('上移');
    expect(upButtons, findsWidgets, reason: '排序模式下每张卡都该有上移/下移');
    await tester.tap(upButtons.at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(enabledIds(), <String>[
      'p-b',
      'p-a',
      'p-c',
    ], reason: '上移必须落到真顺序上（宿主 sort），不能只是视觉位移');
    await flushPendingTimers(tester);
  });

  testWidgets('调整顺序：首位的上移、末位的下移不可点（不产生空操作）', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byTooltip('调整顺序'));
    await tester.pump();

    // byTooltip 命中的是 Tooltip 本身，IconButton 在它外层。
    IconButton buttonOf(Finder tooltip) => tester.widget<IconButton>(
      find.ancestor(of: tooltip, matching: find.byType(IconButton)).first,
    );

    expect(
      buttonOf(find.byTooltip('上移').first).onPressed,
      isNull,
      reason: '第一位没有上移目标',
    );
    expect(
      buttonOf(find.byTooltip('下移').last).onPressed,
      isNull,
      reason: '最后一位没有下移目标',
    );
    await flushPendingTimers(tester);
  });

  testWidgets('搜不到时给出路：去市场用同一个词找', (tester) async {
    await pumpTab(tester);

    await tester.enterText(find.byType(TextField).first, '不存在的插件名');
    await tester.pump();

    expect(find.text('没有匹配的插件'), findsOneWidget);
    expect(
      find.text('去市场搜「不存在的插件名」'),
      findsOneWidget,
      reason: '本地搜不到不等于没有 —— 要给一条去市场的路',
    );
    await flushPendingTimers(tester);
  });

  testWidgets('市场页支持带着关键词打开（初筛就生效）', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.21.2',
      buildNumber: '359',
      buildSignature: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialQuery: '日报',
          initialInstalledIds: const <String>{},
          onInstall: (tpl, {onProgress}) async {},
          onUninstall: (id) async {},
          manifestRepository: _FakeManifestRepository(
            _manifest(<MarketPluginTemplate>[
              _template('daily', '日报详情'),
              _template('base64', 'Base64 编解码'),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('日报详情'), findsOneWidget, reason: '命中关键词的要留着');
    expect(find.text('Base64 编解码'), findsNothing, reason: '初筛必须真的生效');
    await flushPendingTimers(tester);
  });

  test('宿主：applySortOrder 按给定顺序重编号，重启后仍生效', () async {
    final cache = CacheStore.inMemory('apply_sort_order');
    final first = HomePluginHost(
      persistence: HomePluginPersistence(cache: cache),
    );
    await first.bootstrap();
    final ids = first
        .pluginsOf(HomePluginArea.center)
        .map((p) => p.id)
        .toList();
    expect(ids.length, greaterThanOrEqualTo(3));

    // 整段重编号：交换前两个，其余保持 —— applySortOrder 会把传入的顺序
    // 依次编号 100/200/300…，所以传入的必须是这个 area 的**完整**顺序。
    final moved = <String>[ids[1], ids[0], ...ids.sublist(2)];
    await first.applySortOrder(moved);
    expect(
      first.pluginsOf(HomePluginArea.center).map((p) => p.id).toList(),
      moved,
      reason: '按可见顺序落 sort —— 交换相等 sort 会等于没动，所以是整段重编号',
    );

    final reborn = HomePluginHost(
      persistence: HomePluginPersistence(cache: cache),
    );
    await reborn.bootstrap();
    expect(
      reborn.pluginsOf(HomePluginArea.center).map((p) => p.id).toList(),
      moved,
      reason: '顺序必须随快照持久化',
    );
  });

  group('批量更新（跑不动 UI，钉源码结构）', () {
    final source = File(
      'lib/features/extensions/presentation/plugin_tab.dart',
    ).readAsStringSync();

    test('「全部更新」只在有待更新项时出现，且进行中置灰', () {
      expect(source.contains('全部更新'), isTrue);
      expect(source.contains('PluginRiskKind.outdated'), isTrue);
      expect(source.contains('onPressed: _bulkUpdating'), isTrue);
    });

    test('批量更新走同一份已验签清单，串行安装，不做并发', () {
      final body = source.substring(
        source.indexOf('Future<void> _updateAllRisks()'),
        source.indexOf('Future<void> _handleRiskUninstall'),
      );
      expect(
        body.contains('PluginMarketManifestRepository.instance'),
        isTrue,
        reason: '必须复用市场页那同一个清单仓库（含验签配置），不能另开取包通道',
      );
      expect(body.contains('PluginMarketSecurityConfig'), isTrue);
      expect(body.contains('installFromTemplate'), isTrue);
      expect(
        body.contains('Future.wait'),
        isFalse,
        reason: '安装要写盘 + 可能弹权限，串行失败面最小',
      );
      expect(
        body.contains('failed.add') && body.contains('missing.add'),
        isTrue,
        reason: '失败与"市场里没有"都要逐条留名，不能只报总数',
      );
    });
  });
}
