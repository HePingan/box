import 'update_models.dart';

class AppInstaller {
  static Future<void> downloadAndInstall({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('当前平台不支持 APK 安装');
  }
}