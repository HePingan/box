import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';

class AppInstaller {
  static Future<void> downloadAndInstall({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
  }) async {
    if (manifest.downloadUrl.isEmpty) {
      throw Exception('下载地址为空');
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

    if (manifest.sha256 != null && manifest.sha256!.isNotEmpty) {
      final bytes = await File(savePath).readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest.toLowerCase() != manifest.sha256!.toLowerCase()) {
        await File(savePath).delete().catchError((_) {});
        throw Exception('APK 校验失败，文件可能损坏或被篡改');
      }
    }

    // 强行拉起系统安装器，并捕获它的返回状态
    final result = await OpenFilex.open(savePath);
    if (kDebugMode) {
      debugPrint('OpenFilex result: ${result.type} - ${result.message}');
    }

    // 如果不能安装，直接抛出红字错误
    if (result.type != ResultType.done) {
      throw Exception('系统拒绝安装: ${result.message}\n请检查 AndroidManifest 权限配置是否生效');
    }
  }
}