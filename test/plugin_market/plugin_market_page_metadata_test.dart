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
      packageName: 'top.hpa888.box',
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
    // FIX-08：权限标签改为如实的中文披露（原样保留认不出的 code）。
    expect(find.text('声明：网络、openPage'), findsOneWidget);
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
        'actionCode': 'openVideoList',
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
      'actionCode': 'openVideoList',
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

  testWidgets('平台审核清单不弹「未验签」告警（服务端审核 ≠ 未验签）', (tester) async {
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'platform_plugin',
      'title': '平台插件',
      'subtitle': '服务端审核',
      'areaCode': 'recommend',
      'actionCode': 'toast',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([template]).copyWith(
              source: 'platform',
              signatureVerified: false,
              trustLevel: PluginMarketTrustLevel.serverReviewed,
              signatureMessage: '平台商店清单（服务端审核，未做密码学验签）',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('未验签'),
      findsNothing,
      reason: '服务端审核是如实的弱标签，不是失败；对它报警会把正常状态说成异常',
    );
  });

  testWidgets('远程清单未验签仍然要弹告警（控制组）', (tester) async {
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'remote_plugin',
      'title': '远程插件',
      'subtitle': '未验签',
      'areaCode': 'recommend',
      'actionCode': 'toast',
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
              signatureVerified: false,
              trustLevel: PluginMarketTrustLevel.unverified,
              signatureMessage: 'HMAC 校验不通过',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('未验签'), findsWidgets);
  });

  // FIX-08：安装前的权限披露（只翻译给人看，不暗示沙箱）。
  testWidgets('安装确认里如实列出插件声明的权限', (tester) async {
    final template = MarketPluginTemplate.tryFromJson({
      'id': 'perm_plugin',
      'title': '要权限的插件',
      'subtitle': '声明了网络与剪贴板',
      'areaCode': 'recommend',
      'actionCode': 'openVideoList',
      'permissions': ['network', 'clipboard'],
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([template]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '安装').last);
        // 模态面板常驻不下，pumpAndSettle 会一直等它收尾；定量 pump 足够。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.textContaining('该插件声明将访问：网络、剪贴板'),
      findsOneWidget,
      reason: '装之前必须能看到它要什么',
    );
    expect(
      find.textContaining('不做运行时权限拦截'),
      findsOneWidget,
      reason: '如实说明：声明≠控制，不能暗示有沙箱',
    );
  });

  // FIX-09：占位条目（toast 且无 payload）不给安装入口。
  testWidgets('占位条目显示「即将上线」且没有安装按钮', (tester) async {
    final placeholder = MarketPluginTemplate.tryFromJson({
      'id': 'market_placeholder_probe',
      'title': '占位条目',
      'subtitle': '还没做完',
      'areaCode': 'recommend',
      'actionCode': 'toast',
    })!;
    final real = MarketPluginTemplate.tryFromJson({
      'id': 'market_real_probe',
      'title': '真条目',
      'subtitle': '能装',
      'areaCode': 'recommend',
      'actionCode': 'openVideoList',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            _manifest([real, placeholder]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('即将上线'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '安装'),
      findsOneWidget,
      reason: '只有真条目有安装按钮；占位条目装了只会弹提示',
    );
  });
}

