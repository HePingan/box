import 'package:dio/dio.dart';

import 'update_models.dart';
import 'update_security.dart';

class AppInstaller {
  static Future<void> downloadAndInstall({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
    UpdateManifestSecurityConfig security = const UpdateManifestSecurityConfig(),
    CancelToken? cancelToken,
  }) async {
    throw UnsupportedError('当前平台不支持 APK 安装');
  }
}
