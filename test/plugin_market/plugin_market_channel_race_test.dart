import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 按频道返回不同延迟/不同内容的清单，用来制造「后发先至」。
class _RacingRepository extends PluginMarketManifestRepository {
  _RacingRepository({required this.delays, required this.manifests});

  /// 每个频道的响应延迟
  final Map<PluginMarketChannel, Duration> delays;

  /// 每个频道对应返回的清单
  final Map<PluginMarketChannel, PluginMarketManifest> manifests;

  final List<PluginMarketChannel> requested = <PluginMarketChannel>[];

  @override
  Future<PluginMarketManifest> loadManifest({
    required List<MarketPluginTemplate> fallbackTemplates,
    required PluginMarketChannel channel,
    required PluginMarketSecurityConfig security,
    String? remoteConfigUrl,
    bool forceRefresh = false,
  }) async {
    requested.add(channel);
    await Future<void>.delayed(delays[channel] ?? Duration.zero);
    return manifests[channel]!;
  }
}

PluginMarketManifest _manifestFor(
  PluginMarketChannel channel,
  String templateId,
  String title,
) {
  return PluginMarketManifest(
    version: 2,
    templates: <MarketPluginTemplate>[
      MarketPluginTemplate.tryFromJson({
        'id': templateId,
        'title': title,
        'subtitle': '频道 ${channel.name} 的插件',
        'areaCode': 'recommend',
        'actionCode': 'toast',
        'version': '1.0.0',
      })!,
    ],
    source: 'remote',
    fetchedAt: DateTime(2026, 7, 12, 13, 0),
    channel: channel,
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

  testWidgets('慢的 stable 响应不得覆盖已切到 beta 的频道与列表', (tester) async {
    // stable（初始加载）很慢，beta（用户切换）很快 —— 制造后发先至。
    final repo = _RacingRepository(
      delays: <PluginMarketChannel, Duration>{
        PluginMarketChannel.stable: const Duration(milliseconds: 600),
        PluginMarketChannel.beta: const Duration(milliseconds: 50),
      },
      manifests: <PluginMarketChannel, PluginMarketManifest>{
        PluginMarketChannel.stable: _manifestFor(
          PluginMarketChannel.stable,
          'stable_only_plugin',
          '稳定版插件',
        ),
        PluginMarketChannel.beta: _manifestFor(
          PluginMarketChannel.beta,
          'beta_only_plugin',
          '测试版插件',
        ),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: repo,
          remoteConfigUrl: 'https://example.com/manifest.json',
        ),
      ),
    );

    // 初始 stable 请求已发出但未返回。
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.requested, contains(PluginMarketChannel.stable));

    // 用户切到 Beta：beta 会先回来（50ms），stable 稍后才回（600ms）。
    final dynamic state = tester.state(find.byType(PluginMarketPage));
    // 不能 await：它内部 await 的 Future.delayed 只有 pump 推动 fakeAsync
    // 时钟才会完成，在测试体里 await 会把 pump 挡住 —— 经典自锁，表现为超时。
    // ignore: avoid_dynamic_calls
    state.switchChannelForTesting(PluginMarketChannel.beta);

    // 推进到两个响应都已落地。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ignore: avoid_dynamic_calls
    final PluginMarketChannel channelNow =
        state.currentChannelForTesting as PluginMarketChannel;
    expect(
      channelNow,
      PluginMarketChannel.beta,
      reason: '慢的 stable 响应回来后不得把频道改回 stable',
    );

    expect(
      find.text('测试版插件'),
      findsOneWidget,
      reason: '列表应保留 beta 频道的结果',
    );
    expect(
      find.text('稳定版插件'),
      findsNothing,
      reason: '过期的 stable 清单不得覆盖 beta 列表',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}
