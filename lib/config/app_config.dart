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

  static const bool allowProceedOnCheckFailure = bool.fromEnvironment(
    'ALLOW_PROCEED_ON_UPDATE_CHECK_FAILURE',
    defaultValue: true,
  );

  static const String updateSignatureAlgorithm = String.fromEnvironment(
    'UPDATE_SIGNATURE_ALGORITHM',
    defaultValue: 'sha256',
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
