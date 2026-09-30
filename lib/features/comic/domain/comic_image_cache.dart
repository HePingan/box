// 在线漫画的图片缓存：把章节图落到本地，翻页时先用本地那份。
//
// 三条底线：
//   * 下载失败**如实抛**（由界面显示"这张没下来，点重试"），不静默给占位图；
//   * 同一个地址的并发请求只发一次（翻页来回滑时很常见）；
//   * 缓存目录在系统缓存目录下，用户清缓存/系统清缓存都不会影响别处。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// 图片缓存：`url → 本地文件`。
class ComicImageCache {
  ComicImageCache({
    this.httpClientFactory,
    Map<String, String> Function(String url)? headerFor,
    Future<Directory> Function()? tempDirProvider,
    this.maxBytes = defaultMaxBytes,
    this.maxFiles = defaultMaxFiles,
    this.pruneEveryWrites = defaultPruneEveryWrites,
  }) : headerFor = headerFor ?? _noHeaders,
       tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  /// 可注入（测试用）：默认走 `HttpClient()`。
  final HttpClient Function()? httpClientFactory;

  /// 可注入（测试用）：缓存根目录，默认系统临时目录。
  final Future<Directory> Function() tempDirProvider;

  /// 取**这个地址**的图要带的头（默认空表）。
  ///
  /// 为什么按地址给、而不是一张固定表：图片地址里既有图床（直连取，只要手机 UA），
  /// 也有经自建中转包出来的地址（要 `X-Box-Token`，否则每张 401）。规则见
  /// [comicImageHeadersFor]。令牌仍然**只在请求头**里，不进地址、不进日志。
  final Map<String, String> Function(String url) headerFor;

  static Map<String, String> _noHeaders(String url) => const <String, String>{};

  final Map<String, Future<File>> _inFlight = {};
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await tempDirProvider();
    final dir = Directory('${base.path}/comic_online_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// 已经下好的本地文件（没有就 null）。
  Future<File?> cachedFile(String url) async {
    final dir = await _cacheDir();
    final f = File('${dir.path}/${_key(url)}');
    return await f.exists() ? f : null;
  }

  /// 取图：有缓存直接用，没有就下载。**失败抛出**（带原因）。
  Future<File> fetch(String url) {
    final key = url;
    final running = _inFlight[key];
    if (running != null) return running;
    final future = _fetchOnce(url).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  Future<File> _fetchOnce(String url) async {
    final existing = await cachedFile(url);
    if (existing != null) return existing;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ComicImageException('图片地址不合法：$url');
    }
    final client = httpClientFactory?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
      headerFor(url).forEach((k, v) {
        req.headers.set(k, v);
      });
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw ComicImageException('这张图没下来（HTTP ${resp.statusCode}）');
      }
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (bytes.isEmpty) {
        throw ComicImageException('这张图是空的（0 字节）');
      }
      final dir = await _cacheDir();
      final tmp = File('${dir.path}/${_key(url)}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      final out = File('${dir.path}/${_key(url)}');
      await tmp.rename(out.path);
      // 下完一张顺手看一眼上限（每 16 张才真去全盘数一次：全盘 list 是 O(文件数)，
      // 209 张一话挨张扫一遍是白跑）。
      await _maybePrune();
      return out;
    } on ComicImageException {
      rethrow;
    } catch (e) {
      throw ComicImageException('图片下载失败：${_short(e)}');
    } finally {
      client.close(force: true);
    }
  }

  /// 已经缓存的张数（界面上如实显示缓存情况用）。
  Future<int> cachedCount(List<String> urls) async {
    var n = 0;
    for (final u in urls) {
      if (await cachedFile(u) != null) n++;
    }
    return n;
  }

  /// 缓存占用的字节数（界面显示用；统计的是**这个实例**用的那个目录）。
  Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    return _bytesIn(dir);
  }

  /// 清空缓存（用户手动触发）。
  Future<void> clear() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    _inFlight.clear();
  }

  // ── 上限与清理（设置页的「清理缓存」也走这里）───────────────────────

  /// 默认上限：超过就按**最旧的先删**（构造时可覆盖，单测用小值）。
  ///
  /// 为什么必须有：单话实测最多 209 张 × ~48KB ≈ 10MB，翻几本书就上百 MB，
  /// 而它全落在系统缓存目录里 —— 不设上限就是"用户手机空间被慢慢吃掉，界面上还看不出来"。
  static const int defaultMaxBytes = 300 * 1024 * 1024; // 300MB
  static const int defaultMaxFiles = 4000;

  /// 每下这么多张才全盘数一次（见 [_maybePrune]）。
  static const int defaultPruneEveryWrites = 16;

  /// 上限（超过就删最旧的）。
  final int maxBytes;
  final int maxFiles;

  /// 每下多少张查一次上限。
  final int pruneEveryWrites;

  int _writesSincePrune = 0;

  Future<void> _maybePrune() async {
    if (++_writesSincePrune < pruneEveryWrites) return;
    _writesSincePrune = 0;
    await _prune();
  }

  /// 刚下好的图**最少保留多久**：正在显示的那张被删掉会闪一下破图标。
  static const Duration _minAge = Duration(minutes: 5);

  /// 缓存目录（静态版：设置页清缓存时不必造一个带请求头的实例）。
  static Future<Directory> cacheDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/comic_online_images');
  }

  static Future<int> _bytesIn(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      try {
        total += await e.length();
      } on FileSystemException {
        // 量不到就当 0：统计不该把「清缓存」这个动作本身挡下来。
      }
    }
    return total;
  }

  /// 当前占用字节数（[inDir] 只给单测用；不传就是真实缓存目录）。
  static Future<int> diskUsage({Directory? inDir}) async =>
      _bytesIn(inDir ?? await cacheDirectory());

  /// 清掉整个漫画图片缓存，返回**清出多少字节**（界面用它说人话）。
  ///
  /// [inDir] 只给单测用；不传就是真实缓存目录。
  static Future<int> clearAll({Directory? inDir}) async {
    final dir = inDir ?? await cacheDirectory();
    if (!await dir.exists()) return 0;
    final freed = await _bytesIn(dir);
    await dir.delete(recursive: true);
    return freed;
  }

  /// 单测入口：真实现由取图后按 [_maybePrune] 的节奏自动触发。
  @visibleForTesting
  Future<void> pruneNow() => _prune();

  /// 超上限就删最旧的（尽力而为：删不掉不算失败，这次的图已经拿到了）。
  Future<void> _prune() async {
    try {
      final dir = await _cacheDir();
      final files = <File>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        files.add(e);
        total += await e.length();
      }
      var count = files.length;
      if (count <= maxFiles && total <= maxBytes) return;
      // 旧 → 新：先删最旧的，最近 [_minAge] 内的一律不动（可能正在显示）。
      final stats = <File, FileStat>{};
      for (final f in files) {
        stats[f] = await f.stat();
      }
      files.sort(
        (a, b) => stats[a]!.modified.compareTo(stats[b]!.modified),
      );
      final cutoff = DateTime.now().subtract(_minAge);
      for (final f in files) {
        if (count <= maxFiles && total <= maxBytes) break;
        final st = stats[f]!;
        if (st.modified.isAfter(cutoff)) continue;
        total -= st.size;
        count -= 1;
        try {
          await f.delete();
        } on FileSystemException {
          // 删不掉（被占用 / 已不存在）不影响这次取图；下次再清。
        }
      }
    } on FileSystemException {
      // 清理只是尽力而为：真正的失败（下载）已经在上面如实抛了。
    }
  }

  static String _key(String url) => sha1.convert(utf8.encode(url)).toString();

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

/// 取图失败（可以给人看）。
class ComicImageException implements Exception {
  ComicImageException(this.message);

  final String message;

  @override
  String toString() => message;
}
