import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
          onInstall: (_) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakePluginMarketManifestRepository(
            PluginMarketManifest(
              version: 2,
              templates: [template],
              source: 'remote',
              fetchedAt: DateTime(2026, 7, 12, 13, 0),
              channel: PluginMarketChannel.stable,
              signatureVerified: true,
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
}
