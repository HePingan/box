import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'apk_digest.dart';
import 'update_download_plan.dart';
import 'update_models.dart';
import 'update_resume.dart';
import 'update_security.dart';

/// 一个**已经下载完、并且校验过哈希**的更新包。
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
  /// 只下载 + 校验，**不**拉系统安装界面（拉界面交给 [launchInstaller]）。
  ///
  /// 为什么拆成两步：下载完成的那一刻，用户很可能已经把 App 切到后台了。Android 10+
  /// 会把**后台发起的 startActivity 静默丢掉** —— open_filex 照样返回 `done`，于是
  /// 界面停在「下载中 100%」、什么也不弹，用户只能从头再下一遍（2026-09-29 用户报的
  /// 就是这个）。拆开之后：后台只管下载，回到前台再拉安装界面。
  static Future<DownloadedUpdate> downloadApk({
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

    // 半成品留在原地（`<包>.part` + 它的记录）：断网/切后台之后下次接着下。
    // 旧实现每次失败都删掉，所以"断了就得重下 27MB"（用户报过一次）。
    final partPath = '$savePath.part';
    final metaPath = '$partPath.meta';
    // 别的版本留下的半成品顺手清掉：临时目录不该越攒越多（当前版本的要留着）。
    await _dropOtherPartials(dir.path, keep: fileName);

    Object? lastError;

    for (var i = 0; i < plan.length; i++) {
      final url = plan[i];
      try {
        final resumeState = await _readResumeState(metaPath);
        final partBytes = await _fileLength(partPath);
        final response = await dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: resumeHeaders(partBytes: partBytes, state: resumeState),
            validateStatus: (code) =>
                code != null && code >= 200 && code < 400,
          ),
          cancelToken: cancelToken,
        );
        final body = response.data;
        if (body == null) throw Exception('更新包没有响应内容');

        // 服务端给的起点必须**正好**是我们请求的那个偏移，否则拼出来是坏包：
        // 拼不上就当整包重来（不是错误，只是那部分白下了）。
        final rangeStart = startFromContentRange(
          response.headers.value('content-range'),
        );
        final partial =
            isPartialContent(response.statusCode) &&
            partBytes > 0 &&
            (rangeStart == null || rangeStart == partBytes);
        final headerTotal = _totalFromHeader(response.headers.value('content-length'));
        final total = partial
            ? (totalFromContentRange(
                    response.headers.value('content-range'),
                  ) ??
                  (headerTotal == null ? null : headerTotal + partBytes))
            : headerTotal;

        var received = partial ? partBytes : 0;
        if (total != null && total > 0) onProgress?.call(received / total);

        final sink = File(
          partPath,
        ).openWrite(mode: partial ? FileMode.append : FileMode.write);
        try {
          await for (final chunk in body.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total != null && total > 0 && onProgress != null) {
              onProgress((received / total).clamp(0.0, 1.0));
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        // 把这次的包标识记下来，供下一次续传带 If-Range。
        await _writeResumeState(
          metaPath,
          UpdateResumeState(
            etag: response.headers.value('etag'),
            lastModified: response.headers.value('last-modified'),
            totalBytes: total,
          ),
        );

        if (total != null && received < total) {
          // 连接被中途掐断（但 HTTP 层没报错）：留着半成品，下次接着下。
          throw Exception('更新包没下完（$received/$total 字节）');
        }

        // A1：流式校验，峰值内存 64KB 量级。
        // 旧实现 readAsBytes() 会一次性分配整包（实测 57MB），低端机上直接被杀，
        // 而且崩在「下载已完成」之后，用户完全无法自查。
        final digest = await sha256OfFile(File(partPath));
        if (digest.toLowerCase() != expectedSha256) {
          // 哈希不符说明这份文件根本不是我们要的包（换过包/被改过）：
          // 留着它会让每次续传都拼在上面，所以必须删干净、下次重下。
          await _deleteQuietly(partPath);
          await _deleteQuietly(metaPath);
          throw Exception('APK 校验失败，文件可能损坏或被篡改');
        }

        // 校验过了才改名成正式文件名（半成品名带 .part，安装器不该看到它）。
        final target = File(savePath);
        if (await target.exists()) await target.delete();
        await File(partPath).rename(savePath);
        await _deleteQuietly(metaPath);

        return DownloadedUpdate(
          path: savePath,
          versionCode: manifest.latestVersionCode,
          sha256: expectedSha256,
          fileSize: await File(savePath).length(),
        );
      } on Object catch (e) {
        // 用户主动取消不该被当成线路故障去试备用地址。
        if (e is DioException && CancelToken.isCancel(e)) {
          rethrow;
        }

        lastError = e;
        // **不删半成品**：断网/切后台这种下次能接着下（这条就是本次改动的重点）。
        // 只有上面"哈希不符"那一种情况才必须删（那里已经删了）。

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

  /// 拉起系统安装界面。
  ///
  /// **必须在前台调用**（原因见 [downloadApk]）：后台调用时这里看起来"成功"，
  /// 但用户什么都看不到。
  static Future<void> launchInstaller(String savePath) async {
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

  static int? _totalFromHeader(String? contentLength) {
    final parsed = contentLength == null ? null : int.tryParse(contentLength.trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static Future<int> _fileLength(String path) async {
    final f = File(path);
    if (!await f.exists()) return 0;
    return f.length();
  }

  static Future<UpdateResumeState?> _readResumeState(String metaPath) async {
    try {
      final f = File(metaPath);
      if (!await f.exists()) return null;
      return UpdateResumeState.decode(await f.readAsString());
    } on FileSystemException {
      // 读不到记录就当没有：续传只是省流量，不该因此让下载失败。
      return null;
    }
  }

  static Future<void> _writeResumeState(
    String metaPath,
    UpdateResumeState state,
  ) async {
    try {
      await File(metaPath).writeAsString(state.encode(), flush: true);
    } on FileSystemException {
      // 记不下来就算了：下次从 0 下，功能照旧。
    }
  }

  /// 清掉**别的版本**留下的半成品与记录（当前版本的那份要留着续传）。
  static Future<void> _dropOtherPartials(
    String dirPath, {
    required String keep,
  }) async {
    try {
      await for (final entity in Directory(dirPath).list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('update_')) continue;
        if (name == keep || name.startsWith('$keep.part')) continue;
        try {
          await entity.delete();
        } on FileSystemException {
          // 删不掉不影响这次下载。
        }
      }
    } on FileSystemException {
      // 列不出临时目录也不影响下载本身。
    }
  }
}
