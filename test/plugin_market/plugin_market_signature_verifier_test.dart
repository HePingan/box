import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market/models/plugin_market_signature_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plugins = <dynamic>[
    {
      'id': 'video.tool',
      'title': '影视工具',
      'meta': {'b': 2, 'a': 1},
    },
  ];

  group('plugin market signature verifier', () {
    test('canonical json sorts nested map keys for stable signatures', () {
      final canonical = pluginMarketCanonicalJson({
        'z': 1,
        'a': {'b': 2, 'a': 1},
      });

      expect(canonical, '{"a":{"a":1,"b":2},"z":1}');
    });

    test('passes sha256 signatures over canonical payload', () {
      final signature = pluginMarketSha256Hex(
        pluginMarketCanonicalJson({
          'channel': 'stable',
          'version': 1,
          'plugins': plugins,
        }),
      );

      final result = verifyPluginMarketSignatureForPayload(
        security: const PluginMarketSecurityConfig(),
        channel: PluginMarketChannel.stable,
        version: 0,
        plugins: plugins,
        signature: '  ${signature.toUpperCase()}  ',
      );

      expect(result.passed, isTrue);
      expect(result.message, '验签通过');
      expect(result.actual, signature);
      expect(result.expected, signature);
    });

    test('rejects missing signatures when signing is enabled', () {
      final result = verifyPluginMarketSignatureForPayload(
        security: const PluginMarketSecurityConfig(),
        channel: PluginMarketChannel.stable,
        version: 1,
        plugins: plugins,
        signature: ' ',
      );

      expect(result.passed, isFalse);
      expect(result.message, '缺少 signature');
    });

    test('passes hmac sha256 signatures when secret is configured', () {
      final canonical = pluginMarketCanonicalJson({
        'channel': 'beta',
        'version': 7,
        'plugins': plugins,
      });
      final signature = pluginMarketHmacSha256Hex(canonical, 'secret-key');

      final result = verifyPluginMarketSignatureForPayload(
        security: const PluginMarketSecurityConfig(
          mode: PluginMarketSignMode.hmacSha256,
          secret: 'secret-key',
        ),
        channel: PluginMarketChannel.beta,
        version: 7,
        plugins: plugins,
        signature: signature,
      );

      expect(result.passed, isTrue);
      expect(result.expected, signature);
    });

    test('rejects hmac mode without secret', () {
      final result = verifyPluginMarketSignatureForPayload(
        security: const PluginMarketSecurityConfig(
          mode: PluginMarketSignMode.hmacSha256,
        ),
        channel: PluginMarketChannel.stable,
        version: 1,
        plugins: plugins,
        signature: 'abc',
      );

      expect(result.passed, isFalse);
      expect(result.message, 'HMAC 模式缺少 secret');
    });

    test('signing mode none bypasses signature checks', () {
      final result = verifyPluginMarketSignatureForPayload(
        security: const PluginMarketSecurityConfig(
          mode: PluginMarketSignMode.none,
        ),
        channel: PluginMarketChannel.stable,
        version: 1,
        plugins: plugins,
        signature: '',
      );

      expect(result.passed, isTrue);
      expect(result.message, '验签关闭');
    });
  });

  group('plugin market security wire helpers', () {
    test('parses channels and sign mode aliases', () {
      expect(pluginMarketChannelFromName('beta'), PluginMarketChannel.beta);
      expect(
        pluginMarketChannelFromName('unknown'),
        PluginMarketChannel.stable,
      );
      expect(
        pluginMarketSignModeFromWireName('hmac_sha256'),
        PluginMarketSignMode.hmacSha256,
      );
      expect(
        pluginMarketSignModeWireName(PluginMarketSignMode.hmacSha256),
        'hmac-sha256',
      );
    });
  });
}
