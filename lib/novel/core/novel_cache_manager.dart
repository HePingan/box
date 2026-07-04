import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 小说缓存统计信息
class NovelCacheStats {
  final int totalKeys;
  final int totalSizeBytes;
  final Map<String, int> byNamespace;

  const NovelCacheStats({
    required this.totalKeys,
    required this.totalSizeBytes,
    required this.byNamespace,
  });

  String get formattedSize {
    if (totalSizeBytes < 1024) return '${totalSizeBytes}B';
    if (totalSizeBytes < 1024 * 1024) return '${(totalSizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// 小说缓存管理器 — 用于统计和清理缓存文件
class NovelCacheManager {
  NovelCacheManager({required this.namespace, bool? webMode})
      : webMode = webMode ?? kIsWeb;
  NovelCacheManager.web() : namespace = 'web', webMode = true;

  final String namespace;
  final bool webMode;
  final Map<String, String> _webCache = {};

  Future<Directory> _rootDir() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory('${appDir.path}/$namespace');
  }

  /// 获取缓存统计信息
  Future<NovelCacheStats> getStats() async {
    if (webMode) {
      int totalSize = 0;
      for (final entry in _webCache.values) {
        totalSize += utf8.encode(entry).length;
      }
      return NovelCacheStats(
        totalKeys: _webCache.length,
        totalSizeBytes: totalSize,
        byNamespace: {namespace: _webCache.length},
      );
    }

    final dir = await _rootDir();
    if (!await dir.exists()) {
      return const NovelCacheStats(
        totalKeys: 0,
        totalSizeBytes: 0,
        byNamespace: {},
      );
    }

    final files = await dir.list().toList();
    int totalSize = 0;
    for (final entity in files) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return NovelCacheStats(
      totalKeys: files.length,
      totalSizeBytes: totalSize,
      byNamespace: {namespace: files.length},
    );
  }

  /// 清除指定 namespace 的所有缓存
  Future<void> clear() async {
    if (webMode) {
      _webCache.clear();
      return;
    }

    final dir = await _rootDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 清除指定 key 的缓存
  Future<void> clearKey(String key) async {
    if (webMode) {
      _webCache.remove(key);
      return;
    }

    final dir = await _rootDir();
    final file = File('${dir.path}/$_safeName.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _safeName(String key) => base64Url.encode(utf8.encode(key));
}
