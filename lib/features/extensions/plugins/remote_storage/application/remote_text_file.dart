/// 远程存储里的「一个小文本文件」读写（便签、稍后看清单这类插件共用）。
///
/// 两个必须封在一起的原因：
/// 1. `uploadFile` 只接受磁盘路径（[LocalUploadFile]），没有直接传字节的入口，
///    所以写文本必须先落一个临时文件、传完删掉（失败也要删，否则每次失败留垃圾）。
/// 2. 文件不存在时 PROPFIND/GET 返回 404 —— 对「首次使用」来说是正常状态，
///    不该冒泡成错误，调用方只关心「有没有内容」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/remote_storage_models.dart';
import 'remote_storage_service.dart';

class RemoteTextFile {
  RemoteTextFile({RemoteStorageService? service})
      : _service = service ?? remoteStorageService();

  final RemoteStorageService _service;

  Directory? _tmpDir;

  /// 读文本；文件不存在返回 null（不是错误）。
  Future<String?> read(RemoteStorageAccount account, String path) async {
    try {
      final payload = await _service.readTextPreview(account, path);
      return utf8.decode(payload.bytes, allowMalformed: true);
    } on RemoteStorageException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 写文本（父目录不存在则创建，已存在则覆盖）。
  Future<void> write(
    RemoteStorageAccount account,
    String path,
    String content,
  ) async {
    final dir = parentRemotePath(path);
    if (dir.isNotEmpty) {
      try {
        await _service.ensureRemoteDirs(account, [dir]);
      } on RemoteStorageException catch (e) {
        // 405/409 = 目录已存在（竞态或别的客户端刚建），不算失败。
        if (e.statusCode != 405 && e.statusCode != 409) rethrow;
      }
    }

    final bytes = utf8.encode(content);
    final name = path.split('/').last;
    final tmp = await _tempFile(name);
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await _service.uploadFile(
        account,
        file: LocalUploadFile(path: tmp.path, name: name, size: bytes.length),
        targetDir: dir,
        overwrite: true,
      );
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (e) {
        debugPrint('清理临时文件失败: $e');
      }
    }
  }

  Future<File> _tempFile(String name) async {
    final dir = _tmpDir ??= await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/rtf-${DateTime.now().microsecondsSinceEpoch}-$safe');
  }
}
