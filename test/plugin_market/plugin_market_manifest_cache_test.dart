import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PluginMarketManifest cache parsing', () {
    test('serializes and restores cache metadata and templates', () {
      final fetchedAt = DateTime.parse('2026-06-08T10:20:30.000');
      final manifest = PluginMarketManifest(
        version: 3,
        templates: const [
          MarketPluginTemplate(
            id: 'tool_a',
            title: '工具 A',
            subtitle: '测试工具',
            areaCode: 'video',
            actionCode: 'openVideoList',
            payload: 'payload-a',
            icon: Icons.play_circle_outline,
            color: Color(0xFF4F46E5),
            sort: 20,
          ),
        ],
        source: 'remote',
        fetchedAt: fetchedAt,
        channel: PluginMarketChannel.beta,
        signatureVerified: true,
        signatureMode: PluginMarketSignMode.hmacSha256,
        signatureMessage: '验签通过',
        signatureValue: 'abc123',
      );

      final restored = PluginMarketManifest.fromCacheJson(
        manifest.toJson(),
        defaultChannel: PluginMarketChannel.stable,
      );

      expect(restored.version, 3);
      expect(restored.source, 'cache');
      expect(restored.fetchedAt, fetchedAt);
      expect(restored.channel, PluginMarketChannel.beta);
      expect(restored.signatureVerified, isTrue);
      expect(restored.signatureMode, PluginMarketSignMode.hmacSha256);
      expect(restored.signatureMessage, '验签通过');
      expect(restored.signatureValue, 'abc123');
      expect(restored.templates, hasLength(1));
      expect(restored.templates.single.id, 'tool_a');
      expect(restored.templates.single.areaCode, 'video');
      expect(restored.templates.single.actionCode, 'openVideoList');
    });

    test('uses safe defaults and drops invalid or duplicate templates', () {
      final restored = PluginMarketManifest.fromCacheJson({
        'version': 0,
        'channel': 'unknown',
        'signatureVerified': 'true',
        'signatureMode': 'hmac_sha256',
        'plugins': [
          {'id': '', 'title': 'invalid'},
          {'id': 'dup', 'title': '旧标题', 'sort': 30},
          {'id': 'dup', 'title': '新标题', 'sort': 10},
          {'id': 'late', 'title': '靠后', 'sort': 20},
        ],
      }, defaultChannel: PluginMarketChannel.beta);

      expect(restored.version, 1);
      expect(restored.channel, PluginMarketChannel.stable);
      expect(restored.signatureVerified, isTrue);
      expect(restored.signatureMode, PluginMarketSignMode.hmacSha256);
      expect(restored.templates.map((e) => e.id), ['dup', 'late']);
      expect(restored.templates.first.title, '新标题');
    });
  });
}
