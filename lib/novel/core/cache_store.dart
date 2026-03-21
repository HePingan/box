import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'; // 引入 kIsWeb
import 'package:path_provider/path_provider.dart';

class CacheStore {
  CacheStore({required this.namespace});

  final String namespace;
  
  // 用于 Web 端的内存缓存降级方案
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

  Future<void> write(
    String key,
    dynamic data, {
    Duration? ttl,
  }) async {
    final expiresAt = ttl == null
        ? null
        : DateTime.now().add(ttl).millisecondsSinceEpoch;

    final payload = <String, dynamic>{
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'expiresAt': expiresAt,
      'data': data,
    };

    final jsonString = jsonEncode(payload);

    // 如果是 Web 端，直接存入内存字典，跳过文件读写
    if (kIsWeb) {
      _webCache[_safeName(key)] = jsonString;
      return;
    }

    // 如果是 App 端，写到本地文件
    final file = await _fileFor(key);
    await file.writeAsString(jsonString, flush: true);
  }

  Future<dynamic> read(String key) async {
    String? rawData;

    if (kIsWeb) {
      // 从 Web 内存中读
      rawData = _webCache[_safeName(key)];
    } else {
      // 从 App 文件中读
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      rawData = await file.readAsString();
    }

    if (rawData == null) return null;

    try {
      final obj = jsonDecode(rawData) as Map<String, dynamic>;
      final expiresAt = obj['expiresAt'] as int?;

      if (expiresAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now > expiresAt) {
          await remove(key); // 缓存过期自动清理
          return null;
        }
      }

      return obj['data'];
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    if (kIsWeb) {
      _webCache.remove(_safeName(key));
      return;
    }
    
    final file = await _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
  }
}