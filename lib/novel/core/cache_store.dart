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
}
