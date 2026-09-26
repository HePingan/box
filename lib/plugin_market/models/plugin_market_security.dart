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

/// 清单信任等级：**对外展示的单一事实源**。
///
/// 起因：平台商店路径此前无条件 `signatureVerified: true`（那个响应里根本没有
/// signature 字段），于是市场页对着用户显示「验签：通过」，而 `allowUnsigned`
/// 那道防线在默认路径上根本不参与判断 —— 把「服务端已审核」说成了「密码学验签」，
/// 属语义错位，不是笔误。
///
/// 原则：**宁如实标注，不谎报**。「服务端审核」比「已验签」弱，但它是真的；
/// 降级展示不是安全能力退步（回滚等于恢复谎报）。
enum PluginMarketTrustLevel {
  /// 有密钥参与的校验（HMAC）通过。
  signed,

  /// 平台审核商店：HTTPS + 服务端审核，**没有**密码学验签。
  serverReviewed,

  /// 随 App 一起发布的内置清单（不来自网络）。
  builtIn,

  /// 既未验签也未审核（例如 `allowUnsigned` 放行）。
  unverified;

  /// 给用户看的中文标签。
  String get label => switch (this) {
        PluginMarketTrustLevel.signed => '已验签',
        PluginMarketTrustLevel.serverReviewed => '服务端审核',
        PluginMarketTrustLevel.builtIn => '随 App 内置',
        PluginMarketTrustLevel.unverified => '未验签',
      };

  /// 进缓存 JSON 用的线名。**别用索引**：枚举顺序一变，老缓存就会读错档。
  String get wireName => name;
}

/// 线名 → 等级；认不出的一律当 [PluginMarketTrustLevel.unverified]（防空档）。
PluginMarketTrustLevel pluginMarketTrustLevelFromWireName(String raw) {
  final text = raw.trim();
  for (final level in PluginMarketTrustLevel.values) {
    if (level.wireName == text) return level;
  }
  return PluginMarketTrustLevel.unverified;
}

