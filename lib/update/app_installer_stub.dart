import 'package:dio/dio.dart';

import 'update_models.dart';
import 'update_security.dart';

/// 一个已经下载完、校验过的更新包（本平台没有这个概念，见 [AppInstaller]）。
class DownloadedUpdate {
  const DownloadedUpdate({
    required this.path,
    required this.versionCode,
    required this.sha256,
    required this.fileSize,
  });

  final String path;
  final int versionCode;
  final String sha256;
  final int fileSize;
}

class AppInstaller {
  static Future<DownloadedUpdate> downloadApk({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
    UpdateManifestSecurityConfig security =
        const UpdateManifestSecurityConfig(),
    CancelToken? cancelToken,
  }) async {
    throw UnsupportedError('当前平台不支持 APK 安装');
  }

  static Future<void> launchInstaller(String savePath) async {
    throw UnsupportedError('当前平台不支持 APK 安装');
  }
}
