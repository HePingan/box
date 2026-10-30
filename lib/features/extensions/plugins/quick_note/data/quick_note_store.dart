/// 便签的存储接缝 + 远程存储（WebDAV）实现。
///
/// 为什么要抽象成 [QuickNoteStore]：页面要能在 widget 测试里跑完整流程
/// （新建 → 列表 → 编辑 → 删除），而真实现会连 WebDAV、写临时文件、碰
/// `shared_preferences`。测试里注入内存实现，页面代码一行不用改。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote_storage/application/remote_storage_service.dart';
import '../../remote_storage/domain/remote_storage_models.dart';
import '../domain/quick_note.dart';

/// 便签存储接口（页面只依赖它）。
abstract class QuickNoteStore {
  /// 可用的远程存储账户。
  Future<List<RemoteStorageAccount>> accounts();

  /// 上次用的账户 id（多账户用户不必每次重选）。
  Future<String?> lastAccountId();

  Future<void> rememberAccount(String accountId);

  /// 列出便签（最新在前）。目录不存在时返回空列表，不报错。
  Future<List<QuickNote>> list(RemoteStorageAccount account);

  /// 读取单条便签正文。
  Future<String> read(RemoteStorageAccount account, QuickNote note);

  /// 新建或覆盖保存；返回落盘后的条目（名字已按规则生成/沿用）。
  Future<QuickNote> save(
    RemoteStorageAccount account, {
    required String fileName,
    required String body,
  });

  Future<void> delete(RemoteStorageAccount account, QuickNote note);
}

/// 走远程存储（WebDAV）的真实实现。
class WebdavQuickNoteStore implements QuickNoteStore {
  WebdavQuickNoteStore({RemoteStorageService? service})
      : _service = service ?? remoteStorageService();

  final RemoteStorageService _service;

  static const String _prefsKey = 'quick_note_account_id';

  /// 每条便签保存前先落一个本地临时文件再上传：
  /// `uploadFile` 只接受 [LocalUploadFile]（磁盘路径），没有直接传字节的入口。
  /// 临时文件用完即删，不留在用户目录里。
  Directory? _tmpDir;

  @override
  Future<List<RemoteStorageAccount>> accounts() => _service.loadAccounts();

  @override
  Future<String?> lastAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  @override
  Future<void> rememberAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, accountId);
  }

  @override
  Future<List<QuickNote>> list(RemoteStorageAccount account) async {
    List<RemoteStorageEntry> entries;
    try {
      entries = await _service.list(
        account,
        kQuickNoteDir,
        forceRefresh: true,
      );
    } on RemoteStorageException catch (e) {
      // 目录还没建（首次使用）就是 404，这不是错误。
      if (e.statusCode == 404) return const [];
      rethrow;
    }
    final notes = entries
        .where((e) => !e.isDirectory && isQuickNoteFileName(e.name))
        .map(
          (e) => QuickNote(
            name: e.name,
            path: e.path,
            title: quickNoteTitleFromFileName(e.name),
            modifiedAt: e.modifiedAt,
            size: e.size ?? 0,
          ),
        )
        .toList();
    notes.sort((a, b) => compareQuickNoteNames(a.name, b.name));
    return notes;
  }

  @override
  Future<String> read(RemoteStorageAccount account, QuickNote note) async {
    final payload = await _service.readTextPreview(account, note.path);
    // 便签都很短；真超长了 truncated 为 true，正文会被截断——
    // 这种情况在 UI 上由「只显示前 N 字节」提示兜住，不静默。
    return utf8.decode(payload.bytes, allowMalformed: true);
  }

  @override
  Future<QuickNote> save(
    RemoteStorageAccount account, {
    required String fileName,
    required String body,
  }) async {
    await _ensureDir(account);
    final bytes = utf8.encode(body);
    final tmp = await _tempFile(fileName);
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await _service.uploadFile(
        account,
        file: LocalUploadFile(
          path: tmp.path,
          name: fileName,
          size: bytes.length,
        ),
        targetDir: kQuickNoteDir,
        overwrite: true,
      );
    } finally {
      // 上传失败也要删掉临时文件，否则每次失败留一个垃圾文件。
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (e) {
        debugPrint('清理便签临时文件失败: $e');
      }
    }
    return QuickNote(
      name: fileName,
      path: '$kQuickNoteDir/$fileName',
      title: quickNoteTitleFromFileName(fileName),
      body: body,
      size: bytes.length,
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<void> delete(RemoteStorageAccount account, QuickNote note) async {
    await _service.deleteEntry(
      account,
      entry: RemoteStorageEntry(
        name: note.name,
        path: note.path,
        isDirectory: false,
        size: note.size,
      ),
    );
  }

  Future<void> _ensureDir(RemoteStorageAccount account) async {
    try {
      await _service.ensureRemoteDirs(account, const [kQuickNoteDir]);
    } on RemoteStorageException catch (e) {
      // 已存在（405/409）不算错；其它错误往上抛：目录建不出来时上传必定失败，
      // 早报比让每条便签各失败一次好。
      if (e.statusCode == 405 || e.statusCode == 409) return;
      rethrow;
    }
  }

  Future<File> _tempFile(String fileName) async {
    final dir = _tmpDir ??= await getTemporaryDirectory();
    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}/qn-${DateTime.now().microsecondsSinceEpoch}-$safe');
  }
}

/// 便于测试与调试：内存实现（进程内有效，不落盘、不联网）。
class InMemoryQuickNoteStore implements QuickNoteStore {
  InMemoryQuickNoteStore({
    List<RemoteStorageAccount>? accounts,
    Map<String, String>? seed,
  })  : _accounts = accounts ?? const [],
        _docs = seed ?? {};

  final List<RemoteStorageAccount> _accounts;

  /// 文件名 → 正文。
  final Map<String, String> _docs;

  String? _lastAccountId;

  @override
  Future<List<RemoteStorageAccount>> accounts() async => _accounts;

  @override
  Future<String?> lastAccountId() async => _lastAccountId;

  @override
  Future<void> rememberAccount(String accountId) async {
    _lastAccountId = accountId;
  }

  @override
  Future<List<QuickNote>> list(RemoteStorageAccount account) async {
    final notes = _docs.entries
        .map(
          (e) => QuickNote(
            name: e.key,
            path: '$kQuickNoteDir/${e.key}',
            title: quickNoteTitleFromFileName(e.key),
            size: utf8.encode(e.value).length,
            modifiedAt: DateTime(2026, 10, 30),
          ),
        )
        .toList();
    notes.sort((a, b) => compareQuickNoteNames(a.name, b.name));
    return notes;
  }

  @override
  Future<String> read(RemoteStorageAccount account, QuickNote note) async =>
      _docs[note.name] ?? '';

  @override
  Future<QuickNote> save(
    RemoteStorageAccount account, {
    required String fileName,
    required String body,
  }) async {
    _docs[fileName] = body;
    return QuickNote(
      name: fileName,
      path: '$kQuickNoteDir/$fileName',
      title: quickNoteTitleFromFileName(fileName),
      body: body,
      size: utf8.encode(body).length,
      modifiedAt: DateTime(2026, 10, 30),
    );
  }

  @override
  Future<void> delete(RemoteStorageAccount account, QuickNote note) async {
    _docs.remove(note.name);
  }
}
