import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class CacheStore {
  CacheStore({required this.namespace, bool? webMode})
      : webMode = webMode ?? kIsWeb;
  CacheStore.web() : namespace = 'web', webMode = true;

  static CacheStore inMemory(String namespace) => CacheStore(namespace: namespace, webMode: true);

  final String namespace;
  final bool webMode;
  final Map<String, String> _webCache = {};

  Future<Directory> _rootDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$namespace');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _safeName(String key) => base64Url.encode(utf8.encode(key));

  Future<File> _fileFor(String key) async {
    final root = await _rootDir();
    return File('${root.path}/${_safeName(key)}.json');
  }

  Future<void> write(String key, dynamic data, {Duration? ttl}) async {
    final expiresAt = ttl == null
        ? null
        : DateTime.now().add(ttl).millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'expiresAt': expiresAt,
      'data': data,
    };
    final jsonString = jsonEncode(payload);

    if (webMode) {
      _webCache[_safeName(key)] = jsonString;
      return;
    }
    final file = await _fileFor(key);
    await file.writeAsString(jsonString);
  }

  Future<dynamic> read(String key) async {
    String? rawData;
    if (webMode) {
      rawData = _webCache[_safeName(key)];
    } else {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      rawData = await file.readAsString();
    }
    if (rawData == null) return null;

    try {
      final obj = jsonDecode(rawData) as Map<String, dynamic>;
      final expiresAt = obj['expiresAt'] as int?;
      if (expiresAt != null) {
        if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
          await remove(key);
          return null;
        }
      }
      return obj['data'];
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    if (webMode) {
      _webCache.remove(_safeName(key));
      return;
    }
    final file = await _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 清空该 namespace 下的全部缓存条目。
  ///
  /// 之前没有这个能力，"清除全部缓存"只能删掉索引、正文文件留给 TTL 过期，
  /// 导致用户清完缓存磁盘占用不变。
  /// 返回实际删除的条目数。
  Future<int> clear() async {
    if (webMode) {
      final count = _webCache.length;
      _webCache.clear();
      return count;
    }

    final root = await _rootDir();
    if (!await root.exists()) return 0;

    var removed = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // 单个文件删除失败不影响其余条目
      }
    }
    return removed;
  }

  /// 统计该 namespace 当前占用的磁盘字节数。
  ///
  /// web / 内存模式下返回 UTF-8 编码后的近似值。
  Future<int> sizeInBytes() async {
    if (webMode) {
      var total = 0;
      for (final value in _webCache.values) {
        total += utf8.encode(value).length;
      }
      return total;
    }

    final root = await _rootDir();
    if (!await root.exists()) return 0;

    var total = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        total += await entity.length();
      } catch (_) {
        // 统计期间文件被删则跳过
      }
    }
    return total;
  }
}
