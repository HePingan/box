// 真网络：漫画下载的并发到底该给几（第二批「下载提速」的实测）。
//
// 跑法（**默认不会在 CI/全量里跑**，它在真取图床）：
//   flutter test --tags live test/features/comic/comic_download_parallel_live_test.dart
//
// 为什么要在 Dart 里测、而不是写个 Python 脚本：要验的正是 App 自己那条路的并发行为
// —— 共享 HttpClient、候选地址顺序（优先活得着的边缘 IP）、单张重试，这些都在
// `ComicImageCache` 里。另起一套脚本量出来的是"另一条路"的数字，不能拿来做决定。
//
// 量的是：同一批图，`maxParallel` 取几个值各下一遍，比**用时**与**失败数**。
// 图床对突发并发敏感（345 那轮就是自己把连接打多了才翻车的），所以只认实测。
//
// ⚠️ **别一口气打太多请求**：这台图床会被打急。2026-10-02 我先跑了个 Python 脚本
// （36 张 × 5 种并发 × 3 轮 ≈ 540 个请求），随后同样的地址就开始回 400 / 直接丢连接
// —— 那时候量到的"失败率"是自己的锅，不是并发的锅。所以默认footprint 很小，
// 想加大用环境变量：
//   COMIC_LIVE_BATCHES=3 COMIC_LIVE_PARALLEL=1,2,3,4 flutter test --tags live …
// 两次量之间至少隔十几分钟，且先用手动 curl 确认地址还是 200。
@Tags(['live'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_fetcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

const String _picsApi = 'https://yemancomic.com/api/comic/read/pics';
const String _id = '2218599';
const String _aid = '65547';

/// 取几批真实的图地址（站点一批最多 10 张）。
Future<List<String>> _imageUrls(int batches) async {
  final out = <String>[];
  final client = http.Client();
  try {
    for (var b = 0; b < batches; b++) {
      final resp = await client.post(
        Uri.parse(_picsApi),
        headers: comicDirectHeaders(),
        body: {
          'id': _id,
          'aid': _aid,
          'offset': '${b * 10}',
          'limit': '10',
        },
      );
      if (resp.statusCode != 200) continue;
      final decoded = resp.body;
      // 形状：{"data":{"pic":[{"pic":"https://…","id":"…"}, …]}}
      for (final m in RegExp(r'"pic"\s*:\s*"(https?:[^"]+)"').allMatches(decoded)) {
        out.add(m.group(1)!.replaceAll(r'\/', '/'));
      }
    }
  } finally {
    client.close();
  }
  return out.toSet().toList();
}

void main() {
  test('并发 1/2/3/4 各下一遍：用时与失败数', () async {
    final batches = int.tryParse(
          Platform.environment['COMIC_LIVE_BATCHES'] ?? '',
        ) ??
        1;
    final parallels = (Platform.environment['COMIC_LIVE_PARALLEL'] ?? '1,2,3')
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    final urls = await _imageUrls(batches);
    // ignore: avoid_print
    print('LIVE 拿到 ${urls.length} 张图地址');
    expect(urls, isNotEmpty, reason: '取不到图地址就别下结论');

    final tmp = await Directory.systemTemp.createTemp('comic_parallel_live_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    for (final parallel in parallels) {
      final dir = Directory('${tmp.path}/p$parallel')..createSync(recursive: true);
      // tempDirProvider 必须注入：`flutter test` 跑在 VM 里，path_provider 的平台通道
      // 在这儿是拿不到目录的（没注入就会"每张都失败"，而失败原因与并发无关 —— 我第一版
      // 就是这么量出"并发几都是 12/12 失败"的）。
      final cache = ComicImageCache(
        maxParallel: parallel,
        tempDirProvider: () async => dir,
        // 图床认客户端特征：**必须带手机 UA**（桌面 UA/无 UA 会被 400/丢连接，
        // 这也是 App 里 `headerFor: comicDirectHeaders()` 的原因）。
        headerFor: (url) => comicDirectHeaders(),
      );
      var failed = 0;
      String firstError = '';
      final sw = Stopwatch()..start();
      // 逐张"丢进去、等结果"：并发由 cache 的 maxParallel 控制（和 App 一样）。
      final futures = <Future<void>>[];
      for (var i = 0; i < urls.length; i++) {
        final dest = File('${dir.path}/$i.bin');
        futures.add(
          cache
              .fetch(urls[i], dest: dest, maxAttempts: 6)
              .then((_) {})
              .catchError((Object e) {
            failed++;
            if (firstError.isEmpty) firstError = '$e';
          }),
        );
      }
      await Future.wait(futures);
      sw.stop();
      // ignore: avoid_print
      print(
        'LIVE 并发 $parallel: 用时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'
        ' · 失败 $failed/${urls.length}'
        '${firstError.isEmpty ? '' : ' · 例：${firstError.split('\n').first}'}',
      );
      cache.close();
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
