import 'package:flutter/foundation.dart';

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
}
