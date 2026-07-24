import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakePluginMarketManifestRepository
    extends PluginMarketManifestRepository {
  _FakePluginMarketManifestRepository(this.manifest);

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
    fetchedAt: DateTime(2026, 7, 12, 13, 0),
    channel: PluginMarketChannel.stable,
    signatureVerified: true,
    signatureMode: PluginMarketSignMode.none,
    signatureMessage: '',
    signatureValue: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'com.example.box',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('PluginMarketPage shows manifest v2 metadata on cards', (
    tester,
  ) async {
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'metadata_plugin',
      'title': '元数据插件',
      'subtitle': '展示版本作者权限',
      'areaCode': 'recommend',
      'actionCode': 'toast',
      'version': '2.3.0',
      'author': 'Box Team',
      'tags': ['AI', '效率'],
      'permissions': ['network', 'openPage'],
      'deprecated': true,
      'changelog': '增加权限说明',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([template]).copyWith(
              source: 'remote',
              signatureMode: PluginMarketSignMode.sha256,
              signatureMessage: 'ok',
              signatureValue: 'sig',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('元数据插件'), findsOneWidget);
    expect(find.text('v2.3.0'), findsOneWidget);
    expect(find.text('作者：Box Team'), findsOneWidget);
    expect(find.text('权限：network、openPage'), findsOneWidget);
    expect(find.text('已废弃'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('效率'), findsOneWidget);
  });

  testWidgets('PluginMarketPage blocks incompatible plugin before install', (
    tester,
  ) async {
    var installCalls = 0;
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'future_plugin',
      'title': '未来插件',
      'subtitle': '需要更高版本',
      'areaCode': 'recommend',
      'actionCode': 'missing.action',
      'minAppVersion': '9.0.0',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async => installCalls++,
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([template]),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '安装').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(installCalls, 0);
    expect(find.text('无法安装插件'), findsOneWidget);
    expect(find.textContaining('当前版本未注册动作：missing.action'), findsOneWidget);
    expect(find.textContaining('需要 App 版本 9.0.0 或更高'), findsOneWidget);
  });

  testWidgets(
    'PluginMarketPage skips incompatible plugins during bulk install',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final installedIds = <String>[];
      final good = MarketPluginTemplate.tryFromJson({
        'id': 'good_plugin',
        'title': '可安装插件',
        'subtitle': '兼容当前版本',
        'areaCode': 'recommend',
        'actionCode': 'toast',
      })!;
      final blocked = MarketPluginTemplate.tryFromJson({
        'id': 'blocked_plugin',
        'title': '阻断插件',
        'subtitle': '动作不存在',
        'areaCode': 'recommend',
        'actionCode': 'missing.action',
      })!;

      await tester.pumpWidget(
        MaterialApp(
          home: PluginMarketPage(
            initialInstalledIds: const {},
            onInstall: (template, {onProgress}) async => installedIds.add(template.id),
            onUninstall: (_) async {},
            manifestRepository: _FakePluginMarketManifestRepository(
              _manifest([good, blocked]),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('安装筛选'));
      await tester.pump();
      final confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '开始安装'),
      );
      confirmButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(installedIds, ['good_plugin']);
      expect(find.textContaining('批量安装完成：1 / 2'), findsOneWidget);
    },
  );

  testWidgets('PluginMarketPage confirms warning plugin before install', (
    tester,
  ) async {
    var installCalls = 0;
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'deprecated_plugin',
      'title': '废弃插件',
      'subtitle': '需要确认',
      'areaCode': 'recommend',
      'actionCode': 'toast',
      'deprecated': true,
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async => installCalls++,
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([template]),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '安装').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('安装前确认'), findsOneWidget);
    expect(find.textContaining('该插件已废弃，建议谨慎安装'), findsOneWidget);
    expect(installCalls, 0);

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '继续安装'),
    );
    continueButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(installCalls, 1);
    expect(find.textContaining('安装成功：废弃插件'), findsOneWidget);
  });
}
