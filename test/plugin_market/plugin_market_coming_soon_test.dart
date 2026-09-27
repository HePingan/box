// 「未上线」不能靠文案反推：本轮实测，13 个内置模板里 7 个是 `toast`（装了只弹一句
// 「XX插件开发中…」），而 FIX-09 的占位判据是「toast 且 payload 为空」——这 7 个带着
// payload 的同类条目照样能装。现在改成显式声明 `comingSoon`，并锁住这份声明。
import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    fetchedAt: DateTime(2026, 9, 27, 10, 0),
    channel: PluginMarketChannel.stable,
    signatureVerified: true,
    signatureMode: PluginMarketSignMode.none,
    signatureMessage: '',
    signatureValue: '',
  );
}

/// 装了只会弹一句提示的条目（正文自述「开发中」）。
const _mustBeComingSoon = <String>[
  'market_quick_note',
  'market_music_focus',
  'market_music_sleep',
  'market_video_watch_later',
  'market_comic_wallpaper',
  'market_comic_week_rank',
  'market_novel_checkin',
];

/// 真动作条目（控制组）：能跳到真页面，不该被标成未上线。
const _realActionIds = <String>[
  'market_daily_digest',
  'market_image_generator',
  'market_github_accel',
  'market_remote_storage',
  'market_video_archive_search',
  'market_novel_pick',
];

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

  test('内置目录：装了只弹提示的条目必须显式声明 comingSoon', () {
    final byId = {
      for (final t in MarketPluginTemplate.defaults) t.id: t,
    };

    for (final id in _mustBeComingSoon) {
      final t = byId[id];
      expect(t, isNotNull, reason: '内置目录里应当还有 $id');
      expect(
        t!.comingSoon,
        isTrue,
        reason:
            '$id 的动作是 toast（装了只弹一句「开发中」），必须显式声明 comingSoon；'
            '靠 payload 是否为空去反推会漏掉它',
      );
      expect(t.isComingSoon, isTrue);
    }

    for (final id in _realActionIds) {
      final t = byId[id];
      expect(t, isNotNull, reason: '内置目录里应当还有 $id');
      expect(
        t!.isComingSoon,
        isFalse,
        reason: '$id 有真实动作（能跳到真页面），不该被标成未上线',
      );
    }
  });

  test('未上线判据对旧数据仍然成立（远端清单没有 comingSoon 字段时）', () {
    // 向后兼容：老清单里「toast 且无 payload」的条目依旧是未上线。
    final legacyEmpty = MarketPluginTemplate.tryFromJson({
      'id': 'legacy_empty_toast',
      'title': '老占位',
      'areaCode': 'recommend',
      'actionCode': 'toast',
    })!;
    expect(legacyEmpty.comingSoon, isFalse, reason: '新字段缺省是 false');
    expect(legacyEmpty.isComingSoon, isTrue, reason: '旧判据仍要兜住它');

    // 显式声明优先：远端清单自己说了 comingSoon 就算数。
    final declared = MarketPluginTemplate.tryFromJson({
      'id': 'declared_soon',
      'title': '远处未上线',
      'areaCode': 'recommend',
      'actionCode': 'toast',
      'payload': '开发中',
      'comingSoon': true,
    })!;
    expect(declared.isComingSoon, isTrue);

    // 控制组：真动作 + 无声明 → 可安装。
    final real = MarketPluginTemplate.tryFromJson({
      'id': 'real_probe',
      'title': '真条目',
      'areaCode': 'recommend',
      'actionCode': 'openVideoList',
    })!;
    expect(real.isComingSoon, isFalse);
  });

  testWidgets('带 payload 的未上线条目：不给安装按钮、明确标「即将上线」', (
    tester,
  ) async {
    final soon = MarketPluginTemplate.tryFromJson({
      'id': 'soon_with_payload',
      'title': '睡眠电台',
      'subtitle': '夜间轻音乐播放入口',
      'areaCode': 'music',
      'actionCode': 'toast',
      'payload': '睡眠电台插件开发中...',
      'comingSoon': true,
    })!;
    final real = MarketPluginTemplate.tryFromJson({
      'id': 'real_action',
      'title': '影视快速检索',
      'subtitle': '直达公共影视搜索页',
      'areaCode': 'video',
      'actionCode': 'openVideoList',
    })!;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginMarketPage(
          initialInstalledIds: const {},
          onInstall: (_, {onProgress}) async {},
          onUninstall: (_) async {},
          manifestRepository: _FakeRepo(_manifest([real, soon])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('即将上线'),
      findsOneWidget,
      reason: '带 payload 的未上线条目同样要标出来 —— 这正是上一版漏掉的那批',
    );
    expect(
      find.widgetWithText(FilledButton, '安装'),
      findsOneWidget,
      reason: '只有真条目有安装按钮',
    );
  });
}
