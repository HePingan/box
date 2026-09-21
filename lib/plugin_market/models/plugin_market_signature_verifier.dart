import 'dart:convert';

import 'package:box/utils/json_canonical.dart';
import 'package:crypto/crypto.dart';

import 'plugin_market_security.dart';

/// [pluginMarketCanonicalJson] 与 [pluginMarketSha256Hex] 保留原公开 API，
/// 调用点与既有测试不用改（单一实现见 lib/utils/json_canonical.dart）。
String pluginMarketCanonicalJson(dynamic value) {
  return canonicalJsonEncode(value);
}

String pluginMarketSha256Hex(String text) {
  return sha256.convert(utf8.encode(text)).toString();
}

String pluginMarketHmacSha256Hex(String text, String secret) {
  final mac = Hmac(sha256, utf8.encode(secret));
  return mac.convert(utf8.encode(text)).toString();
}

PluginMarketVerifyResult verifyPluginMarketSignatureForPayload({
  required PluginMarketSecurityConfig security,
  required PluginMarketChannel channel,
  required int version,
  required List<dynamic> plugins,
  required String signature,
}) {
  if (security.mode == PluginMarketSignMode.none) {
    return const PluginMarketVerifyResult(
      passed: true,
      message: '验签关闭',
      expected: '',
      actual: '',
    );
  }

  final actual = signature.trim().toLowerCase();
  if (actual.isEmpty) {
    return const PluginMarketVerifyResult(
      passed: false,
      message: '缺少 signature',
      expected: '',
      actual: '',
    );
  }

  final payload = <String, dynamic>{
    'channel': channel.name,
    'version': version <= 0 ? 1 : version,
    'plugins': plugins,
  };

  final canonical = pluginMarketCanonicalJson(payload);

  String expected = '';
  switch (security.mode) {
    case PluginMarketSignMode.none:
      expected = '';
      break;
    case PluginMarketSignMode.sha256:
      expected = pluginMarketSha256Hex(canonical);
      break;
    case PluginMarketSignMode.hmacSha256:
      if (security.secret.trim().isEmpty) {
        return const PluginMarketVerifyResult(
          passed: false,
          message: 'HMAC 模式缺少 secret',
          expected: '',
          actual: '',
        );
      }
      expected = pluginMarketHmacSha256Hex(canonical, security.secret);
      break;
  }

  final passed = actual == expected.toLowerCase();

  return PluginMarketVerifyResult(
    passed: passed,
    message: passed ? '验签通过' : '签名不匹配',
    expected: expected,
    actual: actual,
  );
}
