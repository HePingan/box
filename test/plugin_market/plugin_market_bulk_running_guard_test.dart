// P0-2 回归测试：批量安装/卸载按钮不得因异常永久置灰。
//
// 背景（已复现的真实缺陷）：
//   plugin_market_page.dart 的 _installVisible / _removeVisible 里
//     setState(() => _bulkRunning = true);      // 开始
//     final packageInfo = await PackageInfo.fromPlatform();   // ← 无 try 保护
//     ...
//     setState(() => _bulkRunning = false);     // 结束
//   中间无 try/finally。PackageInfo.fromPlatform() 一旦抛错，异常逃逸出上层，
//   setState(false) 永不执行 → _bulkRunning 永久为 true
//   → 按钮 onPressed 是 `_bulkRunning ? null : ...` → 永久置灰，只能重启页面。
//
// 本测试通过 mock platform channel 让 fromPlatform() 抛错来复现。

import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  }) async => manifest;
}

PluginMarketManifest _manifest(List<MarketPluginTemplate> templates) {
  return PluginMarketManifest(
    version: 2,
    templates: templates,
    source: 'builtin',
    fetchedAt: DateTime(2026, 9, 14),
    channel: PluginMarketChannel.stable,
    signatureVerified: true,
    signatureMode: PluginMarketSignMode.none,
    signatureMessage: '',
    signatureValue: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester, List<MarketPluginTemplate> tpl)
  async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakeRepo(_manifest(tpl)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('PackageInfo 抛错时批量按钮必须恢复可用（不得永久置灰）', (tester) async {
    final tpl = MarketPluginTemplate.tryFromJson({
      'id': 'bulk_guard_plugin',
      'title': '批量护栏插件',
      'subtitle': '用于验证按钮不卡死',
      'areaCode': 'recommend',
      'actionCode': 'toast',
    })!;

    await pumpPage(tester, [tpl]);

    // 让 PackageInfo.fromPlatform() 抛错
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => throw PlatformException(code: 'channel_error'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        null,
      ),
    );

    await tester.tap(find.text('安装筛选'));
    await tester.pump();
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始安装'),
    );
    confirm.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 关键断言：批量按钮必须重新可用，而不是永久 null（置灰）
    final installBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '安装筛选'),
    );
    expect(
      installBtn.onPressed,
      isNotNull,
      reason: 'PackageInfo 异常后 _bulkRunning 必须被重置，否则按钮永久置灰',
    );
  });
}
