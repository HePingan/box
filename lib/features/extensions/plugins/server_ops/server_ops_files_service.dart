// 服务器运维插件：文件页的服务层 —— WebdavClient 的薄封装 + 中文错误翻译。
//
// 为什么不直接让页面拿 WebdavClient：
//   * 连接参数来自 ServerOpsSettings，client 要按设置懒建、设置改了就重建；
//   * 「重命名前先 exists() 预检」这类**必须一致**的规则要落在一处
//     （真服务端实测 MOVE 带 Overwrite:F 时目标已存在仍会覆盖，预检才是兜底，
//      见 test/features/extensions/remote_storage/ops_webdav_live_test.dart）；
//   * 页面里只留 UI，错误文案统一在这里翻译成人话。
//
// 按仓库口径，本文件不改动 remote_storage 既有插件的任何行为，只是复用它的
// domain（WebdavClient / RemoteStorageError）与传输实现（DioWebdavTransport）。

import 'dart:io';
import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_text_edit.dart';

class ServerOpsFilesService {
  ServerOpsFilesService({
    required this.settings,
    WebdavClient? client,
    WebdavTransport Function()? transportFactory,
  })  : _clientOverride = client,
        _transportFactory = transportFactory;

  final ServerOpsSettings settings;

  /// 测试注入（假传输已经包在里面的 client）。
  final WebdavClient? _clientOverride;
  final WebdavTransport Function()? _transportFactory;

  WebdavClient? _client;

  /// 当前连接用的 client（按设置懒建）。
  WebdavClient get client {
    final override = _clientOverride;
    if (override != null) return override;
    return _client ??= WebdavClient(
      baseUrl: settings.effectiveBaseUrl,
      username: settings.effectiveUser,
      password: settings.effectivePassword,
      transport: (_transportFactory ?? _defaultTransport)(),
    );
  }

  /// 运维通道是内网自建实例，证书正常；不放开自签证书（与 live 契约测试一致）。
  static WebdavTransport _defaultTransport() =>
      DioWebdavTransport(allowBadCert: false, badCertHost: '');

  /// 复用 remote_storage 预览组件时用的账户视图。
  ///
  /// 图片预览（相册左右滑动、缩放、20MB 上限、逐页失败不阻塞）在远端存储插件里
  /// 已经写细了，运维通道没必要再写一份：这里只把设置翻译成它要求的账户对象。
  /// id 用固定常量 —— clientFor 按 id 缓存 client，借用真实账户的 id 会串味。
  RemoteStorageAccount get account => RemoteStorageAccount(
        id: 'server_ops_channel',
        label: '服务器运维通道',
        baseUrl: settings.effectiveBaseUrl,
        username: settings.effectiveUser,
        password: settings.effectivePassword,
      );

  /// 列目录。
  Future<List<RemoteStorageEntry>> list(String path) => client.list(path);

  /// 是否存在（HEAD，目录自动退回 PROPFIND）。
  Future<bool> exists(String path) => client.exists(path);

  /// 新建目录。
  Future<void> createDirectory(String path) => client.createDirectory(path);

  /// 删除文件或目录。
  ///
  /// **目录是否递归删除由服务端决定**（运维通道的 nginx DAV 是递归删的），
  /// 所以 UI 的确认文案必须写清"目录内所有内容一并删除"。
  Future<void> delete(String path) => client.delete(path);

  /// 上传本地文件到 [remotePath]。
  Future<void> upload(
    File file,
    String remotePath, {
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancel,
  }) =>
      client.uploadFrom(file, remotePath, onProgress: onProgress, cancel: cancel);

  /// 下载 [remotePath] 到本地 [dest]。
  Future<void> download(
    String remotePath,
    File dest, {
    void Function(int received, int total)? onProgress,
    TransferCancelToken? cancel,
  }) =>
      client.downloadTo(
        remotePath,
        dest,
        onProgress: onProgress,
        cancel: cancel,
      );

  /// 读文件开头若干字节（文本预览）。
  Future<ReadUpTo> readUpTo(String path, int maxBytes) =>
      client.readUpTo(path, maxBytes);

  /// 重命名 / 移动：**先 exists() 预检目标**再 MOVE。
  ///
  /// 真服务端（rclone 后端）对 `Overwrite: F` 不一定回 412，可能直接静默覆盖，
  /// 所以覆盖保护只能靠自己这一遍预检 —— 宁可多一次 HEAD，也不能悄悄覆盖别人的文件。
  Future<void> rename(String from, String to) async {
    if (await client.exists(to)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标已存在：${basename(to)}',
      );
    }
    await client.move(from, to);
  }

  /// 移动到另一个目录（跨目录）：MOVE 由服务端一次完成，**目录整树一起走**。
  ///
  /// 与 [rename] 同为覆盖保护 + MOVE，只是语义上是"搬家"而不是"改名"。
  Future<void> moveEntry(String from, String to) => rename(from, to);

  /// 复制文件或目录到 [to]。
  ///
  /// **目录必须客户端递归逐文件 COPY**：实测（2026-09-25）对目录直接发 COPY
  /// 只会得到一个**空的副本目录**（子文件不在里面），静默丢内容。所以：
  ///   * 文件：`COPY` 一次搞定，服务端完成、不耗手机流量；
  ///   * 目录：先 MKCOL，再按 `list` 递归逐个子目录 MKCOL、逐个文件 COPY。
  ///
  /// [isDirectory] 由调用方给（页面已经有条目类型，不必再探测一次）；
  /// [onProgress] 报"已复制 done/total 个文件"；[cancel] 在每项前检查，
  /// 取消后不再发起后续请求。
  Future<void> copyEntry(
    String from,
    String to, {
    required bool isDirectory,
    void Function(int done, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    if (await client.exists(to)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标已存在：${basename(to)}',
      );
    }
    // 取消要归一成中文异常：传输层各处抛的是 TransferCanceledException，
    // 直接漏到页面上会显示成英文的 "transfer canceled"。
    try {
      cancel?.throwIfCanceled();
      if (!isDirectory) {
        await client.copy(from, to);
        onProgress?.call(1, 1);
        return;
      }
      await _copyDirectory(
        from,
        to,
        onProgress: onProgress,
        cancel: cancel,
      );
    } on TransferCanceledException {
      throw const RemoteStorageException(RemoteStorageError.canceled, '已取消');
    }
  }

  /// 目录复制：客户端递归（见 [copyEntry] 的"空目录陷阱"）。
  Future<void> _copyDirectory(
    String from,
    String to, {
    void Function(int done, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    // 先走一遍把要建的目录与要复制的文件都收齐，才能给出**有总数**的进度。
    final plan = await _planDirectoryCopy(from, to, cancel: cancel);

    await client.createDirectory(to);
    for (final dir in plan.directories) {
      cancel?.throwIfCanceled();
      await client.createDirectory(dir);
    }

    var done = 0;
    for (final file in plan.files) {
      cancel?.throwIfCanceled();
      await client.copy(file.$1, file.$2);
      done += 1;
      onProgress?.call(done, plan.files.length);
    }
  }

  /// 收集目录复制计划：子目录（目标路径）与文件（源,目标）对。
  Future<_OpsCopyPlan> _planDirectoryCopy(
    String from,
    String to, {
    TransferCancelToken? cancel,
  }) async {
    final directories = <String>[];
    final files = <(String, String)>[];
    await _walkCopy(from, to, directories, files, cancel);
    return _OpsCopyPlan(directories: directories, files: files);
  }

  Future<void> _walkCopy(
    String dir,
    String mapped,
    List<String> directories,
    List<(String, String)> files,
    TransferCancelToken? cancel,
  ) async {
    cancel?.throwIfCanceled();
    final entries = await client.list(dir);
    for (final entry in entries) {
      cancel?.throwIfCanceled();
      final target = joinPath(mapped, entry.name);
      if (entry.isDirectory) {
        directories.add(target);
        await _walkCopy(entry.path, target, directories, files, cancel);
      } else {
        files.add((entry.path, target));
      }
    }
  }

  // ── 列表排序 / 过滤（A3，纯函数，用例直接调） ──────────────────

  /// 关键词过滤：按名称包含（大小写不敏感）；空关键词返回原列表。
  static List<RemoteStorageEntry> filterEntries(
    List<RemoteStorageEntry> entries,
    String keyword,
  ) {
    final needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) return entries;
    return entries
        .where((e) => e.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  /// 排序：**目录恒在前**，同组内按 [mode] 排；[descending] 只反转组内顺序
  /// （目录永远排在最前面 —— 把目录混到文件里排会让人找不回"上层入口"）。
  static List<RemoteStorageEntry> sortEntries(
    List<RemoteStorageEntry> entries,
    OpsSortMode mode, {
    bool descending = false,
  }) {
    final list = List<RemoteStorageEntry>.from(entries);
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      var cmp = _compareBy(a, b, mode);
      if (cmp == 0) {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return descending ? -cmp : cmp;
    });
    return list;
  }

  static int _compareBy(
    RemoteStorageEntry a,
    RemoteStorageEntry b,
    OpsSortMode mode,
  ) {
    switch (mode) {
      case OpsSortMode.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case OpsSortMode.size:
        return (a.size ?? 0).compareTo(b.size ?? 0);
      case OpsSortMode.time:
        final at = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
        return at.compareTo(bt);
    }
  }

  // ── 路径工具（纯函数，用例直接调） ──────────────────────────────

  /// 拼账户内相对路径，顺手把多余斜杠归一（目录页传进来的都是相对路径）。
  static String joinPath(String directory, String name) {
    final dir = directory.replaceAll(RegExp(r'^/+|/+$'), '');
    final leaf = name.replaceAll(RegExp(r'^/+'), '');
    if (dir.isEmpty) return leaf;
    if (leaf.isEmpty) return dir;
    return '$dir/$leaf';
  }

  /// 上一级目录；已经在根（空路径）时返回空串。
  static String parentOf(String path) {
    final normalized = path.replaceAll(RegExp(r'^/+|/+$'), '');
    if (normalized.isEmpty) return '';
    final idx = normalized.lastIndexOf('/');
    if (idx < 0) return '';
    return normalized.substring(0, idx);
  }

  /// 面包屑（含根）：`a/b/c` → `[('', '根目录'), ('a','a'), ('a/b','b'), ('a/b/c','c')]`。
  static List<(String, String)> breadcrumbs(String path) {
    final normalized = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final crumbs = <(String, String)>[('', '根目录')];
    if (normalized.isEmpty) return crumbs;
    final parts = normalized.split('/');
    var acc = '';
    for (final part in parts) {
      acc = acc.isEmpty ? part : '$acc/$part';
      crumbs.add((acc, part));
    }
    return crumbs;
  }

  /// 路径最后一段（显示用）。
  static String basename(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }

  /// 路径的父目录（`/a/b/c` → `/a/b`；根下第一层 → 空串）。
  static String dirname(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    final idx = normalized.lastIndexOf('/');
    if (idx < 0) return '';
    return normalized.substring(0, idx);
  }

  /// 单个条目的元信息（大小 / 修改时间 / etag）。
  ///
  /// 实现走"列父目录再挑那一条"：这条路径已经验证过能用，而且顺带确认了
  /// 文件还在。读不到（父目录打不开、文件没了）返回 null —— 调用方据此
  /// 说"文件已经不在"而不是"你没权限"。
  Future<RemoteStorageEntry?> statFor(String path) async {
    try {
      final entries = await client.list(dirname(path));
      for (final e in entries) {
        if (e.path == path || basename(e.path) == basename(path)) return e;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// 列某文件的历史备份（本插件生成的 `*.box-bak-*`），最新在前。
  Future<List<RemoteStorageEntry>> listBackups(String path) async {
    final parent = dirname(path);
    final base = basename(path);
    try {
      final entries = await client.list(parent);
      final backups = entries
          .where((e) =>
              !e.isDirectory &&
              e.name.startsWith('$base$kOpsBackupMarker'))
          .toList()
        ..sort((a, b) => b.name.compareTo(a.name));
      return backups;
    } catch (_) {
      return const <RemoteStorageEntry>[];
    }
  }

  /// 保存编辑后的内容：先落本机临时文件，再上传覆盖（WebDAV PUT）。
  ///
  /// 为什么走临时文件：底层只有 `uploadFrom(File)`。临时文件用完即删，
  /// 里面是用户自己正在编辑的文本，不留痕。
  Future<void> saveText(String path, Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('box-ops-save-');
    final file = File('${dir.path}/payload');
    try {
      await file.writeAsBytes(bytes, flush: true);
      await client.uploadFrom(file, path);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 删不掉临时目录不影响保存结果
      }
    }
  }

  /// 落盘（覆盖式，抗半路断网）：先上传到临时名，再 MOVE 盖到目标上。
  ///
  /// 为什么不直接 PUT 覆盖：手机网络断在传输中间时，rclone 会留下**被截断**的目标
  /// 文件 —— "文件坏了"比"这次没保存成功"严重得多（`sshd_config` 这种直接把自己锁
  /// 在门外）。先写临时名再 MOVE，失败时目标原样不动，最坏只多一个临时文件。
  ///
  /// 这里的 MOVE 语义是**要覆盖**：服务层的 [rename] 带 exists 预检（防手滑覆盖），
  /// 那是给用户手动改名用的；保存场景正相反，所以单独一个方法，故意不走那个预检。
  Future<void> saveTextAtomic(String path, Uint8List bytes) async {
    final stamp = DateTime.now().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final tmp = '$path$kOpsPendingMarker${stamp.year}${two(stamp.month)}'
        '${two(stamp.day)}-${two(stamp.hour)}${two(stamp.minute)}'
        '${two(stamp.second)}-${stamp.millisecond.toString().padLeft(3, '0')}';
    await saveText(tmp, bytes);
    try {
      await client.move(tmp, path);
    } catch (e) {
      // MOVE 没过：把半成品收拾掉，别在用户的目录里留垃圾（目标文件没被动过）
      try {
        await delete(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  /// 保存前备份：把当前内容 COPY 成 `<name>.box-bak-<时间戳>`，并只留最近 [keep] 份。
  ///
  /// 返回备份的路径（界面上要显示"已备份到 …"，让人知道有后路）。
  /// 备份失败**要抛** —— 没有后路的保存不能悄悄进行。
  Future<String> backupBeforeSave(
    String path, {
    int keep = kOpsBackupKeep,
    DateTime? now,
  }) async {
    final backup = opsBackupName(path, now ?? DateTime.now());
    await copyEntry(path, backup, isDirectory: false);
    // 清理旧备份：失败无所谓（顶多多留几份），绝不能因此让保存失败。
    try {
      final stale = opsBackupsToPrune(
        (await listBackups(path)).map((e) => e.name).toList(),
        keep: keep,
      );
      final parent = dirname(path);
      for (final name in stale) {
        await delete(parent.isEmpty ? name : '$parent/$name');
      }
    } catch (_) {}
    return backup;
  }

  /// 用某个备份覆盖目标文件 —— 恢复之前**先把当前内容也备份一次**，
  /// 这样"恢复"本身也能撤销（恢复错了还能再退回来）。
  Future<void> restoreBackup(String backupPath, String targetPath) async {
    final result = await readUpTo(backupPath, kOpsEditMaxBytes);
    await backupBeforeSave(targetPath);
    await saveText(targetPath, result.bytes);
  }
}

/// 列表排序档位（A3）：名称 / 大小 / 时间。
enum OpsSortMode { name, size, time }

/// 目录复制计划：目标子目录清单 + 文件（源, 目标）对。
class _OpsCopyPlan {
  const _OpsCopyPlan({required this.directories, required this.files});

  final List<String> directories;
  final List<(String, String)> files;
}

/// 操作失败时给用户看的中文原因。
///
/// `RemoteStorage*` 异常本身已经带中文 message（远端存储插件 §5.5 的映射表），
/// 这里只兜住那些"不该出现但出现了"的原始错误，别把堆栈式英文甩给用户。
String serverOpsErrorMessage(Object error) {
  if (error is RemoteStorageException) return error.message;
  if (error is FileSystemException) return '本机文件读写失败：${error.message}';
  return '操作失败：$error';
}
