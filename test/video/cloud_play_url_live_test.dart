// 真网络：云播页地址到底能不能被归一化成真流。
//
// 跑法：
//   flutter test --tags live test/video/cloud_play_url_live_test.dart
//
// 为什么在 Dart 里测、而不是写个 Python 脚本复核：要验的正是 App 那条路
// —— `CloudPlayUrlResolver` 的候选顺序、Range 探测、`var main` 提取、
// 以及 `#EXTM3U` 判定。另起一套脚本量出来的是「另一条路」的数字。
//
// 这 4 条是 2026-10-02 实测「播不了」的代表地址（9 条 HTML 线路里的 4 条）。
// 地址会腐烂，所以判据不写成「必须解析成功」，而写成：
//   **只要主机答了（拿到响应），就必须解析出真媒体；主机彻底答不了才跳过。**
// 这样源站改名不会误报，而「答了 HTML 却解析不出来」这种回归一定会红。
@Tags(['live'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';

import 'package:box/video/services/cloud_play_url_resolver.dart';
import 'package:box/video/services/shared_http_client.dart';
import 'package:box/video/utils/play_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/play/<id>`：补 `/index.m3u8` 就该拿到真 HLS。
const List<String> _playPages = <String>[
  'https://play.xluuss.com/play/9aAjlRPb',
  'https://hd.kuktxu.com/play/6dBlmVNa',
];

/// `/share/<id>`：补 `/index.m3u8` 是 404，必须拉页面取 `var main`。
const List<String> _sharePages = <String>[
  'https://v.lzcdn28.com/share/f1e2b2c9255d552500a833ac828cd635',
  'https://cdn.ryplay11.com/share/b88764f1c889943b3800a04d001e29c0',
];

const String _userAgent =
    'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/144.0.0.0 Mobile Safari/537.36';

Map<String, String> _headersFor(Uri uri) => <String, String>{
  'User-Agent': _userAgent,
  'Referer': '${uri.scheme}://${uri.host}/',
  'Accept-Language': 'zh-CN,zh;q=0.9',
};

/// 真去读一小段，按统一规则判定（和播放/健康检测用同一个判定）。
Future<PlayProbeVerdict> _verdictOf(
  Uri uri,
  Map<String, String> headers,
) async {
  try {
    final resp = await SharedHttpClient.instance
        .get(uri, headers: <String, String>{
          ...headers,
          'Range': 'bytes=0-1023',
        })
        .timeout(const Duration(seconds: 12));
    return PlayUrlPolicy.classifyProbe(
      statusCode: resp.statusCode,
      contentType: resp.headers['content-type'],
      body: utf8.decode(
        resp.bodyBytes.take(1024).toList(),
        allowMalformed: true,
      ),
    );
  } catch (_) {
    return PlayProbeVerdict.unreachable;
  }
}

void main() {
  test('云播页要么解析成真流，要么主机根本答不了', () async {
    var resolvedCount = 0;
    var reachableCount = 0;

    for (final raw in <String>[..._playPages, ..._sharePages]) {
      final page = Uri.parse(raw);
      final headers = _headersFor(page);

      final resolved = await const CloudPlayUrlResolver().resolve(
        page,
        headers: headers,
      );

      if (resolved != page) {
        resolvedCount++;
        expect(
          PlayUrlPolicy.shapeOf(resolved),
          PlayUrlShape.media,
          reason: '归一化结果必须是媒体地址: $resolved',
        );
        expect(
          await _verdictOf(resolved, headers),
          PlayProbeVerdict.playable,
          reason: '归一化后仍然不是媒体: $resolved',
        );
        continue;
      }

      if (await _verdictOf(page, headers) == PlayProbeVerdict.unreachable) {
        // ignore: avoid_print
        print('[skip] 主机没响应，跳过：$raw');
        continue;
      }
      reachableCount++;
      fail('云播页有响应却没能解析出真流：$raw');
    }

    // 至少得有一条解析成功，否则这套「归一化」等于没验证。
    expect(resolvedCount, greaterThan(0));
    // ignore: avoid_print
    print('[live] 解析成功 $resolvedCount 条 / 可达但失败的 $reachableCount 条');
  });
}
