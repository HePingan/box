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
import 'package:path_provider/path_provider.dart';

/// 图片缓存：`url → 本地文件`。
class ComicImageCache {
  ComicImageCache({
    this.httpClientFactory,
    Map<String, String> Function(String url)? headerFor,
  }) : headerFor = headerFor ?? _noHeaders;

  /// 可注入（测试用）：默认走 `HttpClient()`。
  final HttpClient Function()? httpClientFactory;

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
    final base = await getTemporaryDirectory();
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

  /// 缓存占用（字节）。
  Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// 清空缓存（用户手动触发）。
  Future<void> clear() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    _inFlight.clear();
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
