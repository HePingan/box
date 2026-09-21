import 'package:flutter/foundation.dart' show debugPrint;

enum PluginMarketChannel { stable, beta }

extension PluginMarketChannelX on PluginMarketChannel {
  String get label {
    switch (this) {
      case PluginMarketChannel.stable:
        return 'Stable';
      case PluginMarketChannel.beta:
        return 'Beta';
    }
  }

  String get code => name;
}

PluginMarketChannel pluginMarketChannelFromName(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == 'beta') return PluginMarketChannel.beta;
  return PluginMarketChannel.stable;
}

enum PluginMarketSignMode { none, sha256, hmacSha256 }

String pluginMarketSignModeWireName(PluginMarketSignMode mode) {
  switch (mode) {
    case PluginMarketSignMode.none:
      return 'none';
    case PluginMarketSignMode.sha256:
      return 'sha256';
    case PluginMarketSignMode.hmacSha256:
      return 'hmac-sha256';
  }
}

/// 由「线上/环境变量字面量」解析验签模式。
///
/// 安全默认：**未知值不视为 none**（即不放行未签名）。未知值回落
/// [PluginMarketSignMode.sha256] 并打日志——旧实现 `default:` 直通 none，
/// 一个拼写错误就会静默关闭验签（P0-4）。
///
/// 空串按调用方约定处理：这里按安全默认 sha256（调用方若需区分空串，
/// 应在传入前自行判断）。
PluginMarketSignMode pluginMarketSignModeFromWireName(String raw) {
  final text = raw.trim().toLowerCase();
  switch (text) {
    case '':
    case 'sha256':
      return PluginMarketSignMode.sha256;
    case 'hmac-sha256':
    case 'hmac_sha256':
    case 'hmacsha256':
      return PluginMarketSignMode.hmacSha256;
    case 'none':
      return PluginMarketSignMode.none;
    default:
      debugPrint(
        '[plugin_market] 未知的验签模式字面量 "$raw"，'
        '已回落到安全默认 sha256（不降级到 none）',
      );
      return PluginMarketSignMode.sha256;
  }
}

class PluginMarketSecurityConfig {
  final PluginMarketSignMode mode;

  /// mode = hmacSha256 时需要设置
  final String secret;

  /// true: 验签失败也允许放行远程
  /// false: 验签失败直接拒绝远程，走缓存/内置回退
  final bool allowUnsigned;

  const PluginMarketSecurityConfig({
    this.mode = PluginMarketSignMode.sha256,
    this.secret = '',
    this.allowUnsigned = false,
  });
}

class PluginMarketVerifyResult {
  final bool passed;
  final String message;
  final String expected;
  final String actual;

  const PluginMarketVerifyResult({
    required this.passed,
    required this.message,
    required this.expected,
    required this.actual,
  });
}
