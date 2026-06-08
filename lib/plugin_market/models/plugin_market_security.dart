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

PluginMarketSignMode pluginMarketSignModeFromWireName(String raw) {
  final text = raw.trim().toLowerCase();
  switch (text) {
    case 'sha256':
      return PluginMarketSignMode.sha256;
    case 'hmac-sha256':
    case 'hmac_sha256':
    case 'hmacsha256':
      return PluginMarketSignMode.hmacSha256;
    case 'none':
    default:
      return PluginMarketSignMode.none;
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
