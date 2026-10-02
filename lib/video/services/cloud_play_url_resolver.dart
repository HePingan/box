import 'dart:convert';

import '../../utils/app_logger.dart';
import '../utils/play_url_policy.dart';
import 'shared_http_client.dart';

/// 一次媒体探测的结果：只保留判定需要的三样东西。
class MediaProbeResult {
  const MediaProbeResult({
    required this.statusCode,
    this.contentType,
    this.body = '',
  });

  /// HTTP 状态码；0 表示没拿到响应（超时 / 连接失败 / DNS）。
  final int statusCode;
  final String? contentType;

  /// 响应体文本前缀（最多 [CloudPlayUrlResolver.maxProbeBytes] 字节）。
  final String body;
}

/// 探测一个地址。注入点：测试里换成假实现就不必联网。
typedef MediaProbe = Future<MediaProbeResult> Function(Uri uri);

/// 把「云播页地址」换成能直接交给播放器的媒体地址。
///
/// 采集站给的 `/play/<id>`、`/share/<id>` 不是媒体流而是网页，以前会一路
/// 放行到 ExoPlayer，用户只看到「播放失败」。两条确定性规则能把绝大多数救回来
/// （2026-10-02 实测：`/play/<id>` 补 `/index.m3u8` 6/6 命中，`/share/<id>`
/// 取页面里的 `var main` 2/2 命中）。
///
/// 判定不了就**原样返回**：宁可让播放器照旧报错，也不猜一个地址出来。
class CloudPlayUrlResolver {
  /// 每次探测的等待上限。云播页最多会用到 4 次探测（候选 → 页面 → var main），
  /// 调用方（播放容器）另有一层总时限兜底。
  const CloudPlayUrlResolver({this.probeTimeout = const Duration(seconds: 5)});

  /// 探测只读响应体前 16KB —— 分享页的 `var main` 落在这段里（实测页面约 2KB）。
  static const int maxProbeBytes = 16 * 1024;

  final Duration probeTimeout;

  Future<Uri> resolve(
    Uri uri, {
    required Map<String, String> headers,
    MediaProbe? probe,
  }) async {
    final shape = PlayUrlPolicy.shapeOf(uri);
    if (shape != PlayUrlShape.playPage && shape != PlayUrlShape.sharePage) {
      return uri;
    }

    final doProbe = probe ?? _defaultProbe(headers);
    try {
      // 规则 1：/play/<id> → /play/<id>/index.m3u8
      for (final candidate in PlayUrlPolicy.mediaCandidatesFor(uri)) {
        final result = await doProbe(candidate);
        if (_verdictOf(result) == PlayProbeVerdict.playable) {
          _log('云播页补 index.m3u8 命中 -> ${_sanitize(candidate)}');
          return candidate;
        }
      }

      // 规则 2：把页面本身拉回来，取 var main（/share/<id> 只能走这条）
      final page = await doProbe(uri);
      final mainUrl = PlayUrlPolicy.extractShareMainUrl(page.body, uri);
      if (mainUrl != null) {
        final mainUri = Uri.parse(mainUrl);
        final result = await doProbe(mainUri);
        if (_verdictOf(result) == PlayProbeVerdict.playable) {
          _log('页面 var main 命中 -> ${_sanitize(mainUri)}');
          return mainUri;
        }
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
    }
    return uri;
  }

  /// 生产路径：走进程级共享连接池，带播放器的 Referer/UA 头。
  MediaProbe _defaultProbe(Map<String, String> headers) {
    return (Uri uri) async {
      final response = await SharedHttpClient.instance
          .get(
            uri,
            headers: <String, String>{
              ...headers,
              'Range': 'bytes=0-${maxProbeBytes - 1}',
            },
          )
          .timeout(probeTimeout);
      final bytes = response.bodyBytes.take(maxProbeBytes).toList();
      return MediaProbeResult(
        statusCode: response.statusCode,
        contentType: response.headers['content-type'],
        body: utf8.decode(bytes, allowMalformed: true),
      );
    };
  }

  static PlayProbeVerdict _verdictOf(MediaProbeResult result) {
    return PlayUrlPolicy.classifyProbe(
      statusCode: result.statusCode,
      contentType: result.contentType,
      body: result.body,
    );
  }

  static void _log(String message) {
    AppLogger.instance.log(message, tag: 'PLAYER');
  }

  /// 日志里不带 query（`sign=` 之类的令牌不进日志）。
  static String _sanitize(Uri uri) {
    return uri
        .replace(queryParameters: const <String, String>{}, fragment: '')
        .toString()
        .replaceFirst(RegExp(r'[?#]+$'), '');
  }
}
