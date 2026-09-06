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

  /// 已解析的根目录缓存。
  ///
  /// 原实现每次 read/write/remove 都要走一遍
  /// `getApplicationSupportDirectory()`（platform channel 往返）
  /// + `dir.exists()` + 可能的 `create()`。批量操作时这是纯粹的重复开销：
  /// 一本 1000 章的书统计一次缓存，就是 1000 次 channel 往返。
  /// 目录一旦建好就不会变，缓存住即可。
  Directory? _cachedRoot;

  Future<Directory> _rootDir() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;

    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$namespace');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedRoot = dir;
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

  /// 轻量存在性探测：条目存在且未过期时返回 true。
  ///
  /// 为什么不直接用 `read(key) != null`：`read` 会把整个文件 readAsString 再
  /// jsonDecode。判断「这一章缓存了吗」根本不需要正文，而章节正文动辄几 KB 到
  /// 几十 KB —— 一本 1000 章的书统计一次缓存就要把整本书读进内存解码一遍，
  /// 这是「缓存很慢」的主因。
  ///
  /// 这里只做两件事：文件是否存在 + 读文件头 [_headerProbeBytes] 字节取
  /// `expiresAt`。payload 由 [write] 以固定顺序编码
  /// （`savedAt` → `expiresAt` → `data`），所以 `expiresAt` 必定落在文件头部，
  /// 不必碰正文。
  ///
  /// 探测不到 `expiresAt`（文件头被截断 / 旧格式）时按「未过期」处理：
  /// 宁可多留一份可能过期的缓存，也不要把用户真实存在的缓存误报成没有。
  Future<bool> exists(String key) async {
    if (webMode) {
      final raw = _webCache[_safeName(key)];
      if (raw == null) return false;
      return !_isExpiredHeader(raw);
    }

    final file = await _fileFor(key);
    if (!await file.exists()) return false;

    String header;
    try {
      final handle = await file.open();
      try {
        final bytes = await handle.read(_headerProbeBytes);
        header = utf8.decode(bytes, allowMalformed: true);
      } finally {
        await handle.close();
      }
    } catch (_) {
      // 读文件头失败不代表条目不存在，交给后续真实 read 去定性。
      return true;
    }
    return !_isExpiredHeader(header);
  }

  /// 单个条目占用的真实字节数；不存在则返回 0。
  ///
  /// 用于替代「章节数 × 3072」这种拿魔法常量当磁盘占用的假统计。
  Future<int> sizeOf(String key) async {
    if (webMode) {
      final raw = _webCache[_safeName(key)];
      if (raw == null) return 0;
      return utf8.encode(raw).length;
    }
    final file = await _fileFor(key);
    if (!await file.exists()) return 0;
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  /// 文件头探测长度：`{"savedAt":<13位>,"expiresAt":<13位>,` 约 50 字节，
  /// 128 足够覆盖并留出余量。
  static const int _headerProbeBytes = 128;

  static final RegExp _expiresAtPattern = RegExp(r'"expiresAt"\s*:\s*(\d+)');

  /// 从 payload 头部判断是否已过期。取不到 `expiresAt` 视为未过期。
  static bool _isExpiredHeader(String header) {
    final match = _expiresAtPattern.firstMatch(header);
    if (match == null) return false; // null 或缺失 → 永不过期
    final expiresAt = int.tryParse(match.group(1)!);
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt;
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
