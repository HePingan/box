import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 平台商店清单此前**无条件** `signatureVerified: true`（响应里根本没有 signature
/// 字段），市场页就对着用户显示「验签：通过」—— 把「服务端已审核」说成了
/// 「密码学验签」，而 `allowUnsigned` 那道防线在默认路径上根本不参与判断。
///
/// 这组用例锁死"如实标注"：平台来源 = 服务端审核，内置 = 随 App 内置，
/// 只有真有密钥校验才算已验签。
class _FakePlatformApi extends PluginMarketApi {
  _FakePlatformApi(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<PluginMarketRemoteManifest> fetchMarket({String channel = 'stable'}) async {
    return PluginMarketRemoteManifest.fromJson(payload);
  }
}

class _UnreachableApi extends PluginMarketApi {
  @override
  Future<PluginMarketRemoteManifest> fetchMarket({String channel = 'stable'}) async {
    throw PluginMarketApiException('平台不可达（测试）');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const platformPayload = {
    'version': 3,
    'plugins': [
      {
        'id': 'published_by_platform',
        'title': '平台审核插件',
        'subtitle': '服务端审核通过',
        'areaCode': 'recommend',
        'actionCode': 'toast',
      },
    ],
  };

  test('平台清单标为「服务端审核」，不再自称已验签', () async {
    final repo = PluginMarketManifestRepository(
      api: _FakePlatformApi(platformPayload),
      cache: CacheStore.inMemory('plugin_market_trust_test'),
    );

    final manifest = await repo.loadManifest(
      fallbackTemplates: const [],
      channel: PluginMarketChannel.stable,
      security: const PluginMarketSecurityConfig(),
      forceRefresh: true,
    );

    expect(manifest.source, 'platform');
    expect(
      manifest.trustLevel,
      PluginMarketTrustLevel.serverReviewed,
      reason: '平台响应里没有 signature 字段，没有密码学验签这回事',
    );
    expect(
      manifest.signatureVerified,
      isFalse,
      reason: '谎报已验签会让 allowUnsigned 形同虚设，也让界面骗用户',
    );
    expect(manifest.signatureMessage, contains('未做密码学验签'));
  });

  test('平台不可达且未配置远程时，内置清单标为「随 App 内置」', () async {
    final repo = PluginMarketManifestRepository(
      api: _UnreachableApi(),
      cache: CacheStore.inMemory('plugin_market_trust_test'),
    );

    final manifest = await repo.loadManifest(
      fallbackTemplates: const [],
      channel: PluginMarketChannel.stable,
      security: const PluginMarketSecurityConfig(),
      remoteConfigUrl: null,
      forceRefresh: true,
    );

    expect(manifest.source, 'builtin');
    expect(manifest.trustLevel, PluginMarketTrustLevel.builtIn);
  });

  test('老缓存迁移：平台来源的旧档不得被推成「已验签」', () {
    // 写这份缓存的是谎报那版代码：signatureVerified 被写成了 true。
    // 只看这个位会把平台清单读成"已验签" —— 必须按来源判。
    final restored = PluginMarketManifest.fromCacheJson(
      const {
        'version': 3,
        'source': 'platform',
        'signatureVerified': true,
        'signatureMode': 'sha256',
        'signatureMessage': '平台审核商店',
      },
      defaultChannel: PluginMarketChannel.stable,
    );

    expect(restored.trustLevel, PluginMarketTrustLevel.serverReviewed);
  });

  test('信任等级随缓存往返不丢', () {
    final manifest = PluginMarketManifest(
      version: 3,
      templates: const [],
      source: 'remote',
      fetchedAt: DateTime(2026, 9, 26),
      channel: PluginMarketChannel.stable,
      signatureVerified: true,
      signatureMode: PluginMarketSignMode.hmacSha256,
      signatureMessage: '验签通过',
      signatureValue: 'sig',
      trustLevel: PluginMarketTrustLevel.signed,
    );

    final restored = PluginMarketManifest.fromCacheJson(
      manifest.toJson(),
      defaultChannel: PluginMarketChannel.stable,
    );

    expect(restored.trustLevel, PluginMarketTrustLevel.signed);
  });

  test('认不出的信任等级线名一律当「未验签」（防空档）', () {
    expect(
      pluginMarketTrustLevelFromWireName('server-reviewed-typo'),
      PluginMarketTrustLevel.unverified,
    );
    expect(pluginMarketTrustLevelFromWireName(''), PluginMarketTrustLevel.unverified);
    expect(
      pluginMarketTrustLevelFromWireName('signed'),
      PluginMarketTrustLevel.signed,
    );
  });

  test('线名用名字不用序号（枚举顺序变也不读错档）', () {
    expect(PluginMarketTrustLevel.serverReviewed.wireName, 'serverReviewed');
    expect(PluginMarketTrustLevel.unverified.wireName, 'unverified');
  });
}
