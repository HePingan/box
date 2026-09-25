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

import 'package:box/features/extensions/plugins/remote_storage/application/remote_storage_service.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:box/features/extensions/plugins/remote_storage/domain/webdav_client.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

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
