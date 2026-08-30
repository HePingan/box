import 'package:flutter/foundation.dart';

import '../update/update_security.dart';

/// Build/runtime configuration supplied by `--dart-define`.
///
/// Defaults keep the current development behavior while allowing release builds
/// and channel packages to override endpoints without changing source code.
class AppConfig {
  const AppConfig._();

  static const String appId = String.fromEnvironment(
    'APP_ID',
    defaultValue: 'box',
  );

  static const String updateCheckUrl = String.fromEnvironment(
    'UPDATE_CHECK_URL',
    defaultValue: 'https://box.hpa888.top/api/v1/app-updates/check',
  );

  static const String appChannel = String.fromEnvironment(
    'APP_CHANNEL',
    defaultValue: 'release',
  );

  static const String updatePlatform = String.fromEnvironment(
    'APP_PLATFORM',
    defaultValue: kIsWeb ? 'web' : 'android',
  );

  /// 验签失败时是否仍然放行更新。
  ///
  /// 默认 `false`：多人使用场景下，「验签失败还照装」等于任何能插进这条链路的人
  /// 都可以给用户推包。宁可不更新，也不装来源不明的安装包。
  /// 之前默认 `true` 加上 `catch (_)` 的组合，正是验签 bug 能长期静默存活的原因。
  static const bool allowProceedOnCheckFailure = bool.fromEnvironment(
    'ALLOW_PROCEED_ON_UPDATE_CHECK_FAILURE',
    defaultValue: false,
  );

  /// 默认对齐服务端：`build_manifest()` 只会产出 `HMAC-SHA256` 或不签名。
  /// 之前默认 `sha256` 与服务端不匹配，验签在算 HMAC 之前就因算法不符失败。
  static const String updateSignatureAlgorithm = String.fromEnvironment(
    'UPDATE_SIGNATURE_ALGORITHM',
    defaultValue: 'hmac_sha256',
  );

  static const String updateSignatureSecret = String.fromEnvironment(
    'UPDATE_SIGNATURE_SECRET',
    defaultValue: '',
  );

  static const String updateDownloadAllowedHosts = String.fromEnvironment(
    'UPDATE_DOWNLOAD_ALLOWED_HOSTS',
    defaultValue: 'box.hpa888.top',
  );

  static const bool requireUpdateSha256 = bool.fromEnvironment(
    'REQUIRE_UPDATE_SHA256',
    defaultValue: true,
  );

  static UpdateManifestSecurityConfig get updateSecurityConfig {
    return UpdateManifestSecurityConfig(
      signatureMode: updateSignatureModeFromName(updateSignatureAlgorithm),
      hmacSecret: updateSignatureSecret,
      requireSha256: requireUpdateSha256,
      allowedDownloadHosts: updateDownloadAllowedHosts
          .split(',')
          .map((host) => host.trim())
          .where((host) => host.isNotEmpty)
          .toSet(),
    );
  }
}
