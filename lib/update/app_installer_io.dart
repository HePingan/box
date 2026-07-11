import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';
import 'update_security.dart';

class AppInstaller {
  static Future<void> downloadAndInstall({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
  }) async {
    if (manifest.downloadUrl.isEmpty) {
      throw Exception('下载地址为空');
    }
    validateUpdateDownloadUrl(manifest.downloadUrl);

    final expectedSha256 = normalizeSha256Hex(manifest.sha256 ?? '');
    if (!isValidSha256Hex(expectedSha256)) {
      throw Exception('更新包缺少有效的 SHA-256 校验值');
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // 改用临时缓存目录，防止被沙盒拦截安装
    final dir = await getTemporaryDirectory();
    final fileName = 'update_${manifest.latestVersionCode}.apk';
    final savePath = p.join(dir.path, fileName);

    await dio.download(
      manifest.downloadUrl,
      savePath,
      onReceiveProgress: (count, total) {
        if (total > 0 && onProgress != null) {
          onProgress(count / total);
        }
      },
    );

    final bytes = await File(savePath).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    if (digest.toLowerCase() != expectedSha256) {
      try {
        await File(savePath).delete();
      } catch (_) {
        // 删除失败不应掩盖真正的校验失败。
      }
      throw Exception('APK 校验失败，文件可能损坏或被篡改');
    }

    // 强行拉起系统安装器，并捕获它的返回状态
    final result = await OpenFilex.open(savePath);
    if (kDebugMode) {
      debugPrint('OpenFilex result: ${result.type} - ${result.message}');
    }

    // 如果不能安装，直接抛出红字错误
    if (result.type != ResultType.done) {
      throw Exception(
        '系统拒绝安装: ${result.message}\n请检查 AndroidManifest 权限配置是否生效',
      );
    }
  }
}
