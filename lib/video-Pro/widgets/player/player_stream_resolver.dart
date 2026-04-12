import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../utils/app_logger.dart';

String normalizePlayableUrl(String raw) {
  var url = raw.trim().replaceAll('\\', '');
  if (url.startsWith('//')) {
    url = 'https:$url';
  }
  return url;
}

bool isInvalidWebPageUrl(Uri uri) {
  final path = uri.path.toLowerCase();
  final host = uri.host.toLowerCase();

  if (path.endsWith('.html') || path.endsWith('.htm')) return true;

  if ((host.contains('iqiyi.com') ||
          host.contains('v.qq.com') ||
          host.contains('mgtv.com') ||
          host.contains('youku.com')) &&
      !path.endsWith('.m3u8') &&
      !path.endsWith('.mp4') &&
      !path.endsWith('.flv')) {
    return true;
  }

  return false;
}

class PlayerStreamResolver {
  const PlayerStreamResolver({
    this.probeTimeout = const Duration(seconds: 5),
    this.masterResolveTimeout = const Duration(milliseconds: 2500),
  });

  final Duration probeTimeout;
  final Duration masterResolveTimeout;

  /// 尽量把 m3u8 的 master playlist 降到 media playlist
  Future<Uri> resolveDirectM3u8(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (!uri.path.toLowerCase().contains('.m3u8')) return uri;

    Uri currentUri = uri;
    final client = http.Client();

    try {
      for (int i = 0; i < 2; i++) {
        final res = await client
            .get(currentUri, headers: headers)
            .timeout(masterResolveTimeout);

        final finalUrl = res.request?.url ?? currentUri;
        AppLogger.instance.log(
          'HLS检查: code=${res.statusCode}, final=$finalUrl, ct=${res.headers['content-type']}',
          tag: 'PLAYER',
        );

        if (res.statusCode != 200) {
          return currentUri;
        }

        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final lines = _playlistLines(body);

        final isMaster = lines.any((e) => e.startsWith('#EXT-X-STREAM-INF'));
        if (!isMaster) {
          return finalUrl;
        }

        String? childPath;
        for (int k = 0; k < lines.length; k++) {
          if (lines[k].startsWith('#EXT-X-STREAM-INF')) {
            for (int j = k + 1; j < lines.length; j++) {
              final nextLine = lines[j];
              if (!nextLine.startsWith('#')) {
                childPath = nextLine;
                break;
              }
            }
            if (childPath != null) break;
          }
        }

        if (childPath == null || childPath.isEmpty) {
          return finalUrl;
        }

        final nextUri = finalUrl.resolve(childPath);
        if (nextUri == currentUri) {
          return finalUrl;
        }

        AppLogger.instance.log(
          'HLS Master降维成功，切入内核直连 -> $nextUri',
          tag: 'PLAYER',
        );
        currentUri = nextUri;
      }
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      return uri;
    } finally {
      client.close();
    }

    return currentUri;
  }

  /// HLS 预探测：
  /// 1. 拉 m3u8
  /// 2. 如果是 master playlist，再拉子 playlist
  /// 3. 找首个分片
  /// 4. 只探测首个分片
  ///
  /// 任何一步失败都直接返回 false，避免播放器底层一直超时卡住。
  Future<bool> probeHls(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (kIsWeb) return true;
    if (!uri.path.toLowerCase().contains('.m3u8')) return true;

    final client = http.Client();

    try {
      Uri mediaPlaylistUri = uri;

      AppLogger.instance.log('HLS探测开始 -> $uri', tag: 'PLAYER');

      final entryRes = await _httpGetWithTimeout(
        client,
        uri,
        headers: headers,
        timeout: probeTimeout,
      );

      final entryFinalUrl = entryRes.request?.url ?? uri;
      AppLogger.instance.log(
        'HLS探测 entry: code=${entryRes.statusCode}, final=$entryFinalUrl, ct=${entryRes.headers['content-type']}, len=${entryRes.bodyBytes.length}',
        tag: 'PLAYER',
      );

      if (entryRes.statusCode != 200) {
        AppLogger.instance.log('HLS探测终止: entry 非 200', tag: 'PLAYER');
        return false;
      }

      String body = utf8.decode(entryRes.bodyBytes, allowMalformed: true);
      List<String> lines = _playlistLines(body);
      final isMaster = lines.any((e) => e.startsWith('#EXT-X-STREAM-INF'));

      if (isMaster) {
        String? childPath;
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            for (int j = i + 1; j < lines.length; j++) {
              final next = lines[j];
              if (!next.startsWith('#')) {
                childPath = next;
                break;
              }
            }
            if (childPath != null) break;
          }
        }

        if (childPath == null || childPath.isEmpty) {
          AppLogger.instance.log(
            'HLS探测: master playlist 未找到子线路',
            tag: 'PLAYER',
          );
          return false;
        }

        mediaPlaylistUri = entryFinalUrl.resolve(childPath);

        final mediaRes = await _httpGetWithTimeout(
          client,
          mediaPlaylistUri,
          headers: headers,
          timeout: probeTimeout,
        );

        mediaPlaylistUri = mediaRes.request?.url ?? mediaPlaylistUri;
        AppLogger.instance.log(
          'HLS探测 media: code=${mediaRes.statusCode}, final=$mediaPlaylistUri, ct=${mediaRes.headers['content-type']}, len=${mediaRes.bodyBytes.length}',
          tag: 'PLAYER',
        );

        if (mediaRes.statusCode != 200) {
          AppLogger.instance.log('HLS探测终止: media 非 200', tag: 'PLAYER');
          return false;
        }

        body = utf8.decode(mediaRes.bodyBytes, allowMalformed: true);
        lines = _playlistLines(body);
      } else {
        mediaPlaylistUri = entryFinalUrl;
        AppLogger.instance.log('HLS探测: 入口本身就是 media playlist', tag: 'PLAYER');
      }

      /// 可选：探一下 KEY / MAP，帮助更早发现异常，但失败不直接判死
      String? keyLine;
      for (final line in lines) {
        if (line.startsWith('#EXT-X-KEY')) {
          keyLine = line;
          break;
        }
      }

      if (keyLine != null) {
        final keyPath = _extractQuotedAttr(keyLine, 'URI');
        if (keyPath != null && keyPath.isNotEmpty) {
          final keyUri = mediaPlaylistUri.resolve(keyPath);
          final keyRes = await _httpGetWithTimeout(
            client,
            keyUri,
            headers: {
              ...headers,
              'Range': 'bytes=0-15',
            },
          );

          AppLogger.instance.log(
            'HLS探测 key: code=${keyRes.statusCode}, final=${keyRes.request?.url ?? keyUri}, ct=${keyRes.headers['content-type']}, len=${keyRes.bodyBytes.length}, hex=${_hexPreview(keyRes.bodyBytes)}',
            tag: 'PLAYER',
          );
        }
      }

      String? mapLine;
      for (final line in lines) {
        if (line.startsWith('#EXT-X-MAP')) {
          mapLine = line;
          break;
        }
      }

      if (mapLine != null) {
        final mapPath = _extractQuotedAttr(mapLine, 'URI');
        if (mapPath != null && mapPath.isNotEmpty) {
          final mapUri = mediaPlaylistUri.resolve(mapPath);
          final mapRes = await _httpGetWithTimeout(
            client,
            mapUri,
            headers: {
              ...headers,
              'Range': 'bytes=0-63',
            },
          );

          AppLogger.instance.log(
            'HLS探测 map: code=${mapRes.statusCode}, final=${mapRes.request?.url ?? mapUri}, ct=${mapRes.headers['content-type']}, len=${mapRes.bodyBytes.length}, hex=${_hexPreview(mapRes.bodyBytes)}',
            tag: 'PLAYER',
          );
        }
      }

      /// 找首个分片
      String? firstSegment;
      for (final line in lines) {
        if (!line.startsWith('#')) {
          firstSegment = line;
          break;
        }
      }

      if (firstSegment == null || firstSegment.isEmpty) {
        AppLogger.instance.log(
          'HLS探测: media playlist 没有找到分片行',
          tag: 'PLAYER',
        );
        return true;
      }

      /// 只探测首个分片，拿不到就直接失败
      final segUri = mediaPlaylistUri.resolve(firstSegment);
      final segRes = await _httpGetWithTimeout(
        client,
        segUri,
        headers: {
          ...headers,
          'Range': 'bytes=0-63',
        },
      );

      AppLogger.instance.log(
        'HLS探测 seg: code=${segRes.statusCode}, final=${segRes.request?.url ?? segUri}, ct=${segRes.headers['content-type']}, len=${segRes.bodyBytes.length}, hex=${_hexPreview(segRes.bodyBytes)}',
        tag: 'PLAYER',
      );

      if (segRes.statusCode != 200 && segRes.statusCode != 206) {
        return false;
      }

      if (segRes.bodyBytes.isEmpty) {
        return false;
      }

      AppLogger.instance.log('HLS探测结束', tag: 'PLAYER');
      return true;
    } catch (e, st) {
      AppLogger.instance.logError(e, st, 'PLAYER');
      return false;
    } finally {
      client.close();
    }
  }

  Future<http.Response> _httpGetWithTimeout(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) {
    return client.get(uri, headers: headers).timeout(timeout ?? probeTimeout);
  }

  List<String> _playlistLines(String text) {
    return const LineSplitter()
        .convert(text)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _extractQuotedAttr(String line, String key) {
    final match = RegExp('$key="([^"]+)"').firstMatch(line);
    return match?.group(1);
  }

  String _hexPreview(List<int> bytes, {int count = 8}) {
    if (bytes.isEmpty) return '';
    return bytes
        .take(count)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }
}