import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/features/extensions/market/domain/plugin_market_stats.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 市场卡片的「下载量 / 更新时间 / 包体积」统计行。
///
/// 存在理由：排序支持「按下载量」「按更新时间」，但卡片上这两个数都不显示 ——
/// 排完序用户看不出依据。这些断言锁住「该显示的显示、没有数据的不编造」。
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
  }) async =>
      manifest;
}

PluginMarketManifest _manifest(List<MarketPluginTemplate> templates) =>
    PluginMarketManifest(
      version: 2,
      templates: templates,
      source: 'builtin',
      fetchedAt: DateTime(2026, 10, 30, 22, 0),
      channel: PluginMarketChannel.stable,
      signatureVerified: true,
      signatureMode: PluginMarketSignMode.none,
      signatureMessage: '',
      signatureValue: '',
    );

MarketPluginTemplate _template({
  required String id,
  required String title,
  int downloadCount = 0,
  String publishedAt = '',
  int packageSize = 0,
}) =>
    MarketPluginTemplate(
      id: id,
      title: title,
      subtitle: '副标题',
      areaCode: 'recommend',
      actionCode: 'openVideoList',
      payload: '',
      icon: Icons.extension_outlined,
      color: const Color(0xFF4F46E5),
      downloadCount: downloadCount,
      publishedAt: publishedAt,
      packageSize: packageSize,
    );

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

  final now = DateTime(2026, 10, 30, 22, 0);

  group('marketPluginStatsLine', () {
    test('三个字段齐全时按「下载 · 更新 · 大小」拼起来', () {
      final line = marketPluginStatsLine(
        downloadCount: 12,
        publishedAt: '2026-10-30T20:30:00',
        packageSize: 4096,
        now: now,
      );
      expect(line, '↓ 12 次下载 · 今天更新 · 4.0 KB');
    });

    test('0 次下载不写「0 次下载」（内置条目不是「没人装」）', () {
      final line = marketPluginStatsLine(
        downloadCount: 0,
        publishedAt: '',
        packageSize: 0,
        now: now,
      );
      expect(line, isEmpty);
    });

    test('空/坏时间不编造日期，但其余字段照常显示', () {
      expect(
        marketPluginStatsLine(
          downloadCount: 3,
          publishedAt: '   ',
          packageSize: 0,
          now: now,
        ),
        '↓ 3 次下载',
      );
      expect(
        marketPluginStatsLine(
          downloadCount: 0,
          publishedAt: '昨天下午',
          packageSize: 0,
          now: now,
        ),
        isEmpty,
      );
    });

    test('真实服务端数据形态可用（downloadCount=1、2048 字节）', () {
      expect(
        marketPluginStatsLine(
          downloadCount: 1,
          publishedAt: '2026-10-30T17:48:21.802687',
          packageSize: 2048,
          now: now,
        ),
        '↓ 1 次下载 · 今天更新 · 2.0 KB',
      );
    });
  });

  group('marketUpdatedStamp', () {
    test('一小时内 → 刚更新', () {
      expect(
        marketUpdatedStamp('2026-10-30T21:30:00', now: now),
        '刚更新',
      );
    });

    test('同一天超过一小时 → 今天更新', () {
      expect(
        marketUpdatedStamp('2026-10-30T12:00:00', now: now),
        '今天更新',
      );
    });

    test('跨午夜两小时 → 昨天更新（不是「今天」）', () {
      expect(
        marketUpdatedStamp(
          '2026-10-29T23:00:00',
          now: DateTime(2026, 10, 30, 1, 0),
        ),
        '昨天更新',
      );
    });

    test('几天内 → N 天前更新', () {
      expect(
        marketUpdatedStamp('2026-10-26T10:00:00', now: now),
        '4 天前更新',
      );
    });

    test('同一年的更早时间 → MM-DD 更新；跨年 → 带年份', () {
      expect(
        marketUpdatedStamp('2026-08-01T10:00:00', now: now),
        '08-01 更新',
      );
      expect(
        marketUpdatedStamp('2025-12-31T10:00:00', now: now),
        '2025-12-31 更新',
      );
    });

    test('时间比现在还晚（手机时钟快）→ 刚更新，不显示负数', () {
      expect(
        marketUpdatedStamp('2026-10-31T09:00:00', now: now),
        '刚更新',
      );
    });
  });

  group('formatPackageSize', () {
    test('档位', () {
      expect(formatPackageSize(0), isEmpty);
      expect(formatPackageSize(-1), isEmpty);
      expect(formatPackageSize(512), '512 B');
      expect(formatPackageSize(2048), '2.0 KB');
      expect(formatPackageSize(20480), '20 KB');
      expect(formatPackageSize(1572864), '1.5 MB');
      expect(formatPackageSize(5242880), '5.0 MB');
    });
  });

  group('卡片渲染', () {
    testWidgets('远程条目显示统计行', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PluginMarketPage(
            initialInstalledIds: const {},
            onInstall: (_, {onProgress}) async {},
            onUninstall: (_) async {},
            manifestRepository: _FakeRepo(
              _manifest([
                _template(
                  id: 'remote_stats',
                  title: 'GitHub 加速下载',
                  downloadCount: 1,
                  publishedAt: '2026-10-30T17:48:21.802687',
                  packageSize: 2048,
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('次下载'), findsOneWidget);
      expect(find.textContaining('2.0 KB'), findsOneWidget);
    });

    testWidgets('没有数据的条目根本不渲染这一行', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PluginMarketPage(
            initialInstalledIds: const {},
            onInstall: (_, {onProgress}) async {},
            onUninstall: (_) async {},
            manifestRepository: _FakeRepo(
              _manifest([
                _template(id: 'builtin_no_stats', title: '内置无统计'),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 注意别断言 '更新' 二字：排序栏本来就有「最近更新」、「元信息卡」也有
      // 拉取时间，那样断言会误伤既有 UI。只钉统计行自己的特征串。
      expect(find.textContaining('次下载'), findsNothing);
      for (final stamp in ['刚更新', '今天更新', '昨天更新', '天前更新']) {
        expect(find.textContaining(stamp), findsNothing, reason: stamp);
      }
    });
  });
}
