import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'apk_digest.dart';
import 'update_download_plan.dart';
import 'update_models.dart';
import 'update_security.dart';

class AppInstaller {
  static Future<void> downloadAndInstall({
    required UpdateManifest manifest,
    void Function(double progress)? onProgress,
    UpdateManifestSecurityConfig security =
        const UpdateManifestSecurityConfig(),
    CancelToken? cancelToken,
  }) async {
    final expectedSha256 = normalizeSha256Hex(manifest.sha256 ?? '');
    if (!isValidSha256Hex(expectedSha256)) {
      throw Exception('更新包缺少有效的 SHA-256 校验值');
    }

    // A2/A3：主地址 + 备用地址，且都过域名白名单。主地址不合法会直接抛。
    final plan = buildUpdateDownloadPlan(
      manifest: manifest,
      security: security,
    );

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

    Object? lastError;

    for (var i = 0; i < plan.length; i++) {
      final url = plan[i];
      try {
        await dio.download(
          url,
          savePath,
          cancelToken: cancelToken,
          onReceiveProgress: (count, total) {
            if (total > 0 && onProgress != null) {
              onProgress(count / total);
            }
          },
        );

        // A1：流式校验，峰值内存 64KB 量级。
        // 旧实现 readAsBytes() 会一次性分配整包（实测 57MB），低端机上直接被杀，
        // 而且崩在「下载已完成」之后，用户完全无法自查。
        final digest = await sha256OfFile(File(savePath));
        if (digest.toLowerCase() != expectedSha256) {
          await _deleteQuietly(savePath);
          throw Exception('APK 校验失败，文件可能损坏或被篡改');
        }

        await _launchInstaller(savePath);
        return;
      } on Object catch (e) {
        // 用户主动取消不该被当成线路故障去试备用地址。
        if (e is DioException && CancelToken.isCancel(e)) {
          rethrow;
        }

        lastError = e;
        await _deleteQuietly(savePath);

        final isLast = i == plan.length - 1;
        if (isLast) break;

        if (kDebugMode) {
          debugPrint('更新下载失败，切换备用地址: $e');
        }
        // 重置进度，避免 UI 停在上一条线路的百分比上。
        onProgress?.call(0);
      }
    }

    throw Exception('更新失败：${lastError ?? '未知错误'}');
  }

  static Future<void> _launchInstaller(String savePath) async {
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

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 删除失败不应掩盖真正的失败原因。
    }
  }
}
