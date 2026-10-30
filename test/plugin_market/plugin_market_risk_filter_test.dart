import 'dart:io';

import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 市场「按权限敏感度筛选」：列表层直接滤掉要高危权限的插件。
///
/// 披露（安装前的风险标注）回答「它要什么」，筛选回答「我不想看要这些东西的」。
/// 这里锁住两件事：判定口径（未知 code 视同高风险）与实际 UI 行为（点一下真消失）。
class _FakeRepo extends PluginMarketManifestRepository {
  _FakeRepo(this.manifest);

  final PluginMarketManifest manifest;

  @override
  Future<PluginMarketManifest> loadManifest({
    required List<MarketPluginTemplate> fallbackTemplates,
    required PluginMarketChannel channel,
    required PluginMarketSecurityConfig security,
    String? remoteConfigUrl,
    bool forceRefresh = false,
  }) async {
    return manifest;
  }
}

PluginMarketManifest _manifest(List<MarketPluginTemplate> templates) {
  return PluginMarketManifest(
    version: 2,
    templates: templates,
    source: 'builtin',
    fetchedAt: DateTime(2026, 10, 30, 20, 0),
    channel: PluginMarketChannel.stable,
    signatureVerified: true,
    signatureMode: PluginMarketSignMode.none,
    signatureMessage: '',
    signatureValue: '',
  );
}

MarketPluginTemplate _template({
  required String id,
  required String title,
  List<String> permissions = const [],
}) {
  return MarketPluginTemplate(
    id: id,
    title: title,
    subtitle: '副标题 $title',
    areaCode: 'recommend',
    actionCode: 'openVideoList',
    payload: '',
    permissions: permissions,
    icon: Icons.extension_outlined,
    color: const Color(0xFF4F46E5),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  final safe = _template(
    id: 'risk_safe',
    title: '安全插件',
    permissions: const ['network'],
  );
  final medium = _template(
    id: 'risk_medium',
    title: '中风险插件',
    permissions: const ['storage'],
  );
  final high = _template(
    id: 'risk_high',
    title: '高权限插件',
    permissions: const ['camera', 'microphone'],
  );
  final unknown = _template(
    id: 'risk_unknown',
    title: '未知权限插件',
    permissions: const ['someFuturePermission'],
  );
  final noneOnly = _template(id: 'risk_none', title: '无权限插件');

  group('PluginRiskFilter 判定口径', () {
    test('all 不过滤任何东西', () {
      expect(PluginRiskFilter.all.matches(const []), isTrue);
      expect(PluginRiskFilter.all.matches(const ['accessibility']), isTrue);
    });

    test('noHigh 只滤高风险（低/中/无都留）', () {
      expect(PluginRiskFilter.noHigh.matches(const []), isTrue);
      expect(PluginRiskFilter.noHigh.matches(const ['network']), isTrue);
      expect(PluginRiskFilter.noHigh.matches(const ['storage']), isTrue);
      expect(PluginRiskFilter.noHigh.matches(const ['none']), isTrue);
      expect(PluginRiskFilter.noHigh.matches(const ['microphone']), isFalse);
      expect(
        PluginRiskFilter.noHigh.matches(const ['network', 'accessibility']),
        isFalse,
        reason: '只要有一项高风险就整条滤掉',
      );
    });

    test('未知 code 视同高风险（当前版本读不懂 = 不知道它要干什么）', () {
      expect(
        PluginRiskFilter.noHigh.matches(const ['someFuturePermission']),
        isFalse,
      );
    });

    test('noneOnly 只留不申请权限的条目', () {
      expect(PluginRiskFilter.noneOnly.matches(const []), isTrue);
      expect(PluginRiskFilter.noneOnly.matches(const ['none']), isTrue);
      expect(PluginRiskFilter.noneOnly.matches(const ['network']), isFalse);
    });

    test('每个筛选项都有标签，筛掉东西时有说明文案', () {
      for (final filter in PluginRiskFilter.values) {
        expect(filter.label.trim(), isNotEmpty);
      }
      expect(PluginRiskFilter.all.hint, isEmpty);
      expect(PluginRiskFilter.noHigh.hint, contains('无障碍'));
      expect(PluginRiskFilter.noneOnly.hint, contains('不申请'));
    });
  });

  group('市场页 UI', () {
    // 注意：卡片在 SliverList 里懒加载，屏幕外的条目标题本来就不存在，
    // 所以「某条消失」不能单独作为证据。这里用 hero 上的「筛选 N」
    // （= _visibleTemplates.length）做主断言，标题只做交叉印证。
    Future<void> pump(WidgetTester tester, List<MarketPluginTemplate> all) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PluginMarketPage(
            initialInstalledIds: const {},
            onInstall: (_, {onProgress}) async {},
            onUninstall: (_) async {},
            manifestRepository: _FakeRepo(_manifest(all)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('点「不含高风险」后可见数从 5 变 3（滤掉高权限 + 未知权限）', (tester) async {
      await pump(tester, [safe, medium, high, unknown, noneOnly]);
      expect(find.textContaining('筛选 5'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '不含高风险 (2)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('筛选 3'), findsOneWidget,
          reason: '只该滤掉 camera/microphone 与未知 code 这两条');
      expect(find.text(high.title), findsNothing);
      expect(find.text(unknown.title), findsNothing);
      expect(find.textContaining('已滤掉需要相机'), findsOneWidget);
    });

    testWidgets('点「不申请权限」后只剩 1 条', (tester) async {
      await pump(tester, [safe, medium, high, noneOnly]);
      expect(find.textContaining('筛选 4'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '不申请权限'));
      await tester.pumpAndSettle();

      expect(find.textContaining('筛选 1'), findsOneWidget);
      expect(find.text(noneOnly.title), findsWidgets);
      expect(find.text(safe.title), findsNothing);
      expect(find.textContaining('只显示不申请任何权限'), findsOneWidget);
    });

    testWidgets('高权限条目数为 0 时，chip 不带计数', (tester) async {
      await pump(tester, [safe, noneOnly]);

      expect(find.widgetWithText(FilterChip, '不含高风险'), findsOneWidget);
      expect(find.textContaining('不含高风险 ('), findsNothing);
    });

    test('重置筛选会把权限筛选一并清掉（源码契约）', () {
      // 走 UI 不稳：清空按钮只在搜索框有关键字时才渲染，而 _resetFilters
      // 同时被空态页复用。这里直接锁住它确实清了 _riskFilter。
      final source = File(
        'lib/features/extensions/market/presentation/plugin_market_page.dart',
      ).readAsStringSync();
      final start = source.indexOf('void _resetFilters()');
      expect(start, greaterThan(0));
      final block = source.substring(start, start + 400);
      expect(block, contains('_riskFilter = PluginRiskFilter.all'));
      expect(block, contains("_areaFilter = 'all'"));
      expect(block, contains("_keyword = ''"));
    });
  });
}
