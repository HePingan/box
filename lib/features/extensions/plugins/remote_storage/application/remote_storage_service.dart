// 远程存储 服务门面：
// - DioWebdavTransport：生产传输实现（dio 5.x；支持流式请求体、自签证书放行）。
// - RemoteStorageService：账户 CRUD、列目录、预览读取、下载/上传、播放通道判定。
// - 运行时单例：页面共享同一 service 与 TransferQueue 实例。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/remote_storage_store.dart';
import '../data/remote_thumbnail_cache.dart';
import '../domain/exif_thumbnail.dart';
import '../domain/remote_storage_models.dart';
import '../domain/webdav_client.dart';
import 'playback_relay.dart';
import 'thumbnail_loader.dart';
import 'transfer_queue.dart';

/// 生产传输：dio → WebdavTransport。
///
/// - 请求体为 [WebdavRequest.bodyStream]（PUT 流式上传），content-length 由客户端
///   在 headers 中显式给出（dio 对 Stream 数据不会自动覆盖，见 dio_mixin 实现）。
/// - [allowBadCert] 时仅对 [badCertHost] 放行自签证书；其余主机仍严格校验。
class DioWebdavTransport implements WebdavTransport {
  DioWebdavTransport({
    required this.allowBadCert,
    required this.badCertHost,
    Duration connectTimeout = kConnectTimeout,
    Duration readTimeout = kReadTimeout,
  }) : _dio = _buildDio(
          allowBadCert: allowBadCert,
          badCertHost: badCertHost,
          connectTimeout: connectTimeout,
          readTimeout: readTimeout,
        );

  final bool allowBadCert;
  final String badCertHost;
  final Dio _dio;

  static Dio _buildDio({
    required bool allowBadCert,
    required String badCertHost,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: readTimeout,
        validateStatus: (_) => true,
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    if (allowBadCert) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) {
            final ok = badCertHost.isNotEmpty && host == badCertHost;
            if (!ok) {
              AppLogger.instance.logTo(
                LogChannel.storage,
                '拒绝证书: host=$host（仅放行 $badCertHost）',
                level: LogLevel.warn,
              );
            }
            return ok;
          };
          return client;
        },
      );
    }
    return dio;
  }

  @override
  Future<WebdavResponse> send(WebdavRequest request) async {
    final watch = Stopwatch()..start();
    try {
      final response = await _dio.requestUri<dynamic>(
        request.uri,
        data: request.bodyStream,
        options: Options(
          method: request.method,
          headers: Map<String, dynamic>.from(request.headers),
          responseType: request.readTextResponse
              ? ResponseType.plain
              : ResponseType.stream,
        ),
      );

      final data = response.data;
      final status = data is ResponseBody
          ? data.statusCode
          : (response.statusCode ?? 0);
      traceWebdavRequest(request, status, watch.elapsed);

      if (data is ResponseBody) {
        return WebdavResponse(
          statusCode: data.statusCode,
          headers: _flattenHeaders(data.headers),
          bodyStream: data.stream,
        );
      }
      if (data is String) {
        return WebdavResponse(
          statusCode: response.statusCode ?? 0,
          headers: _flattenHeaders(response.headers.map),
          bodyText: data,
        );
      }
      // 其余形态（null / List<int>）按空响应处理。
      return WebdavResponse(
        statusCode: response.statusCode ?? 0,
        headers: _flattenHeaders(response.headers.map),
        bodyText: data == null ? '' : null,
        bodyStream: data is List<int> ? Stream<List<int>>.value(data) : null,
      );
    } on DioException catch (e) {
      // 上传下载流里抛出的人为取消，原样上抛（队列据此标记「已取消」）。
      final inner = e.error;
      if (inner is TransferCanceledException) rethrow;
      final mapped = mapDioException(e);
      // 走到这里的都是"没拿到响应"（连接/证书/超时）：把请求行与耗时也记下来，
      // 否则日志里只有一句"网络错误"，不知道卡在哪个路径上。
      AppLogger.instance.logTo(
        LogChannel.storage,
        '${request.method} ${request.uri.path} 未完成'
        '（${watch.elapsedMilliseconds}ms）: ${mapped.message}',
        level: LogLevel.warn,
      );
      throw mapped;
    }
  }

  static Map<String, String> _flattenHeaders(Map<String, List<String>> raw) {
    final out = <String, String>{};
    raw.forEach((key, values) {
      final k = key.toLowerCase();
      if (values.isEmpty) {
        out[k] = '';
      } else {
        // set-cookie 等重复头合并为逗号串；本项目用到的头均单值。
        out[k] = values.length == 1 ? values.first : values.join(', ');
      }
    });
    return out;
  }
}

/// dio 异常 → 已归一的中文异常（§5.5 单一事实源在 models 层）。
RemoteStorageException mapDioException(DioException e) {
  // 「已记入调试日志」的承诺兑现处：请求失败的统一归一化入口。
  // 用户看到的每个连接错误都在此落盘到「存储」频道（主动取消除外）。
  if (e.type != DioExceptionType.cancel) {
    AppLogger.instance.logChannelError(LogChannel.storage, e);
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const RemoteStorageException(
        RemoteStorageError.timeout,
        '连接超时，网络不可达（已记入调试日志）',
      );
    case DioExceptionType.badCertificate:
      return const RemoteStorageException(
        RemoteStorageError.certificate,
        '证书校验失败。如为自建/群晖自签证书，请在账户里开启「允许自签名证书」',
      );
    case DioExceptionType.badResponse:
      final status = e.response?.statusCode;
      if (status != null) {
        return remoteStorageExceptionForStatus(
          status,
          retryAfter: parseRetryAfterHeader(
            e.response?.headers.value('retry-after'),
          ),
        );
      }
      return const RemoteStorageException(
        RemoteStorageError.network,
        '网络错误，无法连接服务器',
      );
    case DioExceptionType.cancel:
      return const RemoteStorageException(RemoteStorageError.canceled, '操作已取消');
    case DioExceptionType.connectionError:
      return const RemoteStorageException(
        RemoteStorageError.network,
        '网络错误，无法连接服务器',
      );
    case DioExceptionType.unknown:
      final inner = e.error;
      if (inner is HandshakeException) {
        return const RemoteStorageException(
          RemoteStorageError.certificate,
          '证书校验失败。如为自建/群晖自签证书，请在账户里开启「允许自签名证书」',
        );
      }
      if (inner is SocketException) {
        return const RemoteStorageException(
          RemoteStorageError.network,
          '网络错误，无法连接服务器',
        );
      }
      return RemoteStorageException(
        RemoteStorageError.unknown,
        remoteStorageErrorMessage(
          RemoteStorageError.unknown,
          detail: inner?.runtimeType.toString(),
        ),
      );
  }
}

/// 播放通道判定结果。
class PlaybackPlan {
  const PlaybackPlan({
    required this.needsRelay,
    required this.directUri,
    this.headers = const {},
  });

  /// true：经本机回环中继播放（http 明文 / 自签证书站点）。
  final bool needsRelay;

  /// 可直连的完整 URL（needsRelay 时仅作参考）。
  final Uri directUri;

  /// 直连时需要附加的请求头（Basic 认证）。
  final Map<String, String> headers;
}

/// 远程存储服务门面（每账户一个 WebdavClient，配置变更自动失效）。
class RemoteStorageService {
  RemoteStorageService({
    RemoteStorageStore? store,
    WebdavTransport Function(RemoteStorageAccount account)? transportFactory,
    Future<Directory> Function()? docsDirProvider,
    RemoteThumbnailCache? thumbnailCache,
    this.dirCacheTtl = kDirCacheTtl,
  })  : _store = store ?? RemoteStorageStore(),
        _transportFactory = transportFactory,
        _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory,
        _thumbnails = ThumbnailLoader(
          cache: thumbnailCache ?? RemoteThumbnailCache(),
        );

  /// 目录列表缓存有效期（测试注入 Duration.zero 可强制每次都联网）。
  final Duration dirCacheTtl;

  final RemoteStorageStore _store;
  final WebdavTransport Function(RemoteStorageAccount account)? _transportFactory;
  final Future<Directory> Function() _docsDirProvider;

  final Map<String, String> _clientKeys = {};
  final Map<String, WebdavClient> _clients = {};

  /// 目录列表缓存：`accountId|path` → 条目 + 写入时间（FIFO 淘汰，命中即移到队尾）。
  final Map<String, _CachedListing> _dirCache = {};

  /// 在途上传的远端路径（C7 并发防竞态）：同名文件视为"已存在"，见 [uploadFile]。
  final Set<String> _inFlightUploads = {};

  /// 列表缩略图取用器（缓存 + 并发上限 + 同键去重）。
  final ThumbnailLoader _thumbnails;

  /// 探测过但没有 EXIF 内嵌缩略图的条目（283 D1）。
  ///
  /// 为什么需要：EXIF 探测要读文件开头（最多 [kExifProbeBytes]），如果没命中，
  /// 取用器不会缓存 null（失败结果本就不该缓存），于是每次滚动回来都会再花一次
  /// 256KB。这个集合把"探过没有"记在内存里；上限 [kExifProbeMissLimit]，超了清空
  /// （宁可多探几次，也不要让集合无限增长）。
  final Set<String> _exifProbeMisses = {};

  // ---------------------------------------------------------------- 账户

  Future<List<RemoteStorageAccount>> loadAccounts() async {
    final all = await _store.loadAccounts();
    all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return all;
  }

  Future<void> saveAccount(RemoteStorageAccount account) async {
    final all = await _store.loadAccounts();
    final idx = all.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      all[idx] = account;
    } else {
      all.add(account);
    }
    await _store.saveAccounts(all);
    _invalidateClient(account.id);
    // 账户配置变了：目录缓存的 key 前缀是该账户，整体作废比逐条猜更可靠。
    _dirCache.removeWhere((key, _) => key.startsWith('${account.id}|'));
  }

  Future<void> deleteAccount(String id) async {
    final all = await _store.loadAccounts();
    all.removeWhere((a) => a.id == id);
    await _store.saveAccounts(all);
    _invalidateClient(id);
    _dirCache.removeWhere((key, _) => key.startsWith('$id|'));
  }

  // ------------------------------------------------------------ 客户端

  /// 取出/构建账户客户端（同配置复用连接池；改配置自动重建）。
  WebdavClient clientFor(RemoteStorageAccount account) {
    _validateForUse(account);
    final key = [
      account.baseUrl,
      account.username,
      account.password,
      account.tlsMode.name,
      account.allowBadCert ? '1' : '0',
    ].join('|');
    final cached = _clients[account.id];
    if (cached != null && _clientKeys[account.id] == key) return cached;
    final transport = _transportFactory?.call(account) ??
        DioWebdavTransport(
          allowBadCert: account.allowBadCert,
          badCertHost: account.host,
        );
    final client = WebdavClient(
      baseUrl: account.baseUrl,
      username: account.username,
      password: account.password,
      transport: transport,
    );
    _clients[account.id] = client;
    _clientKeys[account.id] = key;
    return client;
  }

  void _invalidateClient(String id) {
    _clients.remove(id);
    _clientKeys.remove(id);
  }

  /// 使用前校验（http 策略）。抛 [RemoteStorageException]。
  void _validateForUse(RemoteStorageAccount account) {
    final err = RemoteStorageAccount.validateBaseUrl(account.baseUrl);
    if (err != null) {
      throw RemoteStorageException(RemoteStorageError.unknown, err);
    }
    if (account.isHttp && !account.httpEffectiveAllowed) {
      throw const RemoteStorageException(
        RemoteStorageError.unknown,
        '该地址为 http 明文连接，按当前设置被禁止。如为局域网设备，'
        '可在账户设置中改为「始终允许不安全连接」',
      );
    }
  }

  // ------------------------------------------------------------ 操作

  /// 测试连接。
  Future<WebdavProbeResult> testConnection(RemoteStorageAccount account) async {
    try {
      return await clientFor(account).probe();
    } on RemoteStorageException catch (e) {
      return WebdavProbeResult(rootListable: false, errorMessage: e.message);
    }
  }

  Future<List<RemoteStorageEntry>> list(
    RemoteStorageAccount account,
    String path, {
    bool forceRefresh = false,
  }) async {
    final key = '${account.id}|$path';
    if (!forceRefresh) {
      final cached = _dirCache.remove(key);
      if (cached != null &&
          DateTime.now().difference(cached.storedAt) < dirCacheTtl) {
        // 命中即移到队尾：淘汰时先掉的是"最久没被看过"的目录，而不是最早的。
        _dirCache[key] = cached;
        return cached.entries;
      }
    }
    final entries = await clientFor(account).list(
      path,
      filterSystemNames: !account.showSystemFolders,
    );
    _storeListing(key, entries);
    return entries;
  }

  /// 目录配额（RFC 4331）。服务器未实现该扩展时返回空对象，UI 自然不显示。
  Future<RemoteStorageQuota> quota(
    RemoteStorageAccount account, {
    String path = '',
  }) {
    return clientFor(account).quota(path);
  }

  /// 写操作后让某目录的缓存失效（上传成功、将来的删除/移动/新建）。
  void invalidateListing(RemoteStorageAccount account, String path) {
    _dirCache.remove('${account.id}|$path');
  }

  void _storeListing(String key, List<RemoteStorageEntry> entries) {
    _dirCache.remove(key);
    _dirCache[key] = _CachedListing(
      List<RemoteStorageEntry>.unmodifiable(entries),
      DateTime.now(),
    );
    while (_dirCache.length > kDirCacheMaxEntries) {
      _dirCache.remove(_dirCache.keys.first);
    }
  }

  /// 扫描同名冲突（仅上传流程用）：返回与远端同名的本地文件名列表。
  ///
  /// 实现要点：**一次 PROPFIND 取代每文件一次 HEAD**。原实现是
  /// `for (file) await client.exists(...)`——选 50 个文件就是 50 次串行往返，
  /// 弱网/弱 NAS 上用户要等分钟级，且任何一次抖动还要吃满重试退避。
  ///
  /// 判据取条目 **href 派生出的 basename**（`entry.path`），而不是 `displayname`：
  /// Nextcloud / 部分群晖会返回与真实文件名不同的 displayname，用它会漏判冲突，
  /// 而漏判的后果是用户以为"没有同名"却被静默覆盖。
  ///
  /// 目录列表失败（404 目录不存在、403、服务器不支持列目录）时**退回原逐文件
  /// HEAD 实现**——慢但权威，不因为优化引入"漏判"这种数据安全回归。
  Future<List<String>> scanConflicts(
    RemoteStorageAccount account, {
    required List<LocalUploadFile> files,
    required String targetDir,
  }) async {
    if (files.isEmpty) return const <String>[];

    // 保持入参顺序；同名重复的本地文件只算一次。
    final wanted = <String, String>{};
    for (final file in files) {
      final safe = sanitizeRemoteSegment(file.name);
      if (safe == null) continue;
      wanted.putIfAbsent(safe, () => file.name);
    }
    if (wanted.isEmpty) return const <String>[];

    final client = clientFor(account);
    try {
      // 这里刻意走 `client.list` 而不是第 354 行的带缓存 `list()`：
      // 冲突判定是写路径的安全检查，"15 秒前的列表"可能漏判并导致静默覆盖。
      final entries = await client.list(
        targetDir,
        filterSystemNames: !account.showSystemFolders,
      );
      final existing = <String>{
        for (final entry in entries)
          if (!entry.isDirectory) _basenameOfRemotePath(entry.path),
      };
      final conflicts = <String>[];
      for (final candidate in wanted.entries) {
        if (existing.contains(candidate.key)) {
          conflicts.add(candidate.value);
          continue;
        }
        // Unicode 归一化差异（O6）：群晖/macOS 以 NFD 存名，我们用 NFC 名去
        // `exists()` 会得到 404，于是"看起来没冲突"→ 传上去变成第二份看着同名的
        // 文件。骨架比对能把这种情况认出来，按冲突处理（跳过）。
        final variant = normalizationVariantOf(candidate.key, existing);
        if (variant != null) {
          AppLogger.instance.logTo(
            LogChannel.storage,
            '「${candidate.value}」与服务器上的「$variant」只是 Unicode 归一化差异，'
            '按同名处理（跳过）',
            level: LogLevel.debug,
          );
          conflicts.add(candidate.value);
        }
      }
      return conflicts;
    } on RemoteStorageException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '冲突扫描退化为逐个 HEAD（目录列表失败：${e.message}）',
        level: LogLevel.debug,
      );
    }

    final conflicts = <String>[];
    for (final candidate in wanted.entries) {
      try {
        if (await client.exists(joinRemotePath(targetDir, candidate.key))) {
          conflicts.add(candidate.value);
        }
      } on RemoteStorageException catch (e) {
        AppLogger.instance.logTo(
          LogChannel.storage,
          '冲突扫描失败（${candidate.value}）: ${e.message}',
          level: LogLevel.warn,
        );
      }
    }
    return conflicts;
  }

  /// 远端相对路径的末段（文件名）。列表条目的 `path` 已由客户端按 href 解码。
  static String _basenameOfRemotePath(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  /// 下载到应用文档目录（按账户分子目录、同名自动加序号）。
  /// 返回最终文件路径。
  Future<String> download(
    RemoteStorageAccount account, {
    required String remotePath,
    required String fileName,
    void Function(int received, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    final client = clientFor(account);
    final safe = sanitizeRemoteSegment(fileName) ?? 'download.bin';
    final dir = await _downloadDirFor(account);
    final target = await _resolveDownloadTarget(dir, safe);
    final temp = File('${target.path}.part');
    final metaFile = File('${temp.path}.meta');

    // 断点归属校验（C2）：只有"同一个账户 + 同一个远端路径"的 .part 才能续传。
    var resumeFrom = 0;
    if (await temp.exists()) {
      final length = await temp.length();
      final meta = PartialDownload.tryParse(await _readTextOrNull(metaFile));
      if (length > 0 &&
          meta != null &&
          meta.matches(accountId: account.id, remotePath: remotePath)) {
        resumeFrom = length;
      } else {
        // 不认识的断点（别的账户/别的文件/元数据坏了）：留着只会拼出坏文件。
        await _deleteQuietly(temp);
        await _deleteQuietly(metaFile);
      }
    }
    if (resumeFrom == 0) {
      await metaFile.writeAsString(
        PartialDownload(
          accountId: account.id,
          remotePath: remotePath,
        ).toJsonString(),
      );
    }

    try {
      await client.downloadTo(
        remotePath,
        temp,
        onProgress: onProgress,
        cancel: cancel,
        resumeFrom: resumeFrom,
      );
      await temp.rename(target.path);
      await _deleteQuietly(metaFile);
    } catch (e) {
      // 断点留不留，按两条判断：
      //  - 可重试的错误（网络抖动/超时/5xx）→ 保留 .part，下一轮从字节数续传；
      //  - 不可重试（401/403/404/507…）或一个字节都没收到 → 清掉，留着只是占空间。
      final received = await temp.exists() ? await temp.length() : 0;
      if (!isRetryableTransferError(e) || received == 0) {
        await _deleteQuietly(temp);
        await _deleteQuietly(metaFile);
      }
      rethrow;
    }
    return target.path;
  }

  /// 下载落点：优先复用"同一名字的未完成断点"，否则挑一个不撞名的文件（C2）。
  ///
  /// 规则（两个条件同时满足才复用）：`<name>.part` 存在 **且** `<name>` 还不存在。
  /// 后者是关键——否则会在一个已经下载好的成品上继续追加、再把它覆盖掉。
  static Future<File> _resolveDownloadTarget(
    Directory dir,
    String baseName,
  ) async {
    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    final ext = dot > 0 ? baseName.substring(dot) : '';
    for (var i = 0; i <= 200; i++) {
      final name = i == 0 ? baseName : '$stem ($i)$ext';
      final target = File('${dir.path}/$name');
      final hasFinal = await target.exists();
      if (hasFinal) continue;
      final part = File('${target.path}.part');
      final partLength = await part.exists() ? await part.length() : 0;
      // 有非空断点 → 复用它续传；没有 → 这就是个干净的名字。
      if (partLength == 0) {
        await _deleteQuietly(part); // 0 字节的空壳没有续传价值
      }
      return target;
    }
    return File('${dir.path}/$baseName');
  }

  static Future<String?> _readTextOrNull(File file) async {
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 清理失败不该盖住真正的错误（尤其是那个让用户看到原因的异常）。
    }
  }

  /// 上传单个文件；返回 false 表示远端已有同名文件且 [overwrite] 为 false（跳过）。
  Future<bool> uploadFile(
    RemoteStorageAccount account, {
    required LocalUploadFile file,
    required String targetDir,
    required bool overwrite,
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    final client = clientFor(account);
    final safe = sanitizeRemoteSegment(file.name);
    if (safe == null) {
      final why = remoteSegmentRejectionReason(file.name);
      throw RemoteStorageException(
        RemoteStorageError.unknown,
        '文件名不可用：${file.name}（${why ?? '未知原因'}）',
      );
    }
    final remotePath = joinRemotePath(targetDir, safe);
    // 并发上传的竞态（C7）：队列现在会同时跑多个任务，而 `exists()` 在另一个上传
    // 写完之前返回 false——两个同名文件（不同源目录里各有一个同名文件）会双双通过
    // 检查，后写的静默覆盖先写的。用"在途占位"把这条路堵掉：同名者视为已存在。
    if (!overwrite) {
      if (_inFlightUploads.contains(remotePath) ||
          await client.exists(remotePath)) {
        return false; // 拍板3：默认跳过
      }
    }
    _inFlightUploads.add(remotePath);
    try {
      final src = File(file.path);
      if (!await src.exists()) {
        throw RemoteStorageException(
          RemoteStorageError.unknown,
          '本地文件不存在：${file.name}',
        );
      }
      await client.uploadFrom(
        src,
        remotePath,
        onProgress: onProgress,
        cancel: cancel,
      );
    } finally {
      _inFlightUploads.remove(remotePath);
    }
    // 上传改变了目录内容：作废该目录缓存，避免"传完了列表里还没有"。
    invalidateListing(account, targetDir);
    return true;
  }

  /// 文本预览（拍板6：512KB 上限；超出显示前缀并提示）。
  Future<PreviewPayload> readTextPreview(
    RemoteStorageAccount account,
    String path, {
    TransferCancelToken? cancel,
  }) async {
    final client = clientFor(account);
    final up = await client.readUpTo(
      path,
      kPreviewTextMaxBytes,
      cancel: cancel,
    );
    return PreviewPayload(
      bytes: up.bytes,
      truncated: up.truncated || up.bytes.length >= kPreviewTextMaxBytes,
      oversize: false,
      totalLength: up.totalLength,
    );
  }

  // ------------------------------------------------------- 写操作（B1 拍板）

  /// 新建文件夹。名称不可用或已存在时抛异常（由 UI 提示）。
  Future<void> createFolder(
    RemoteStorageAccount account, {
    required String parentPath,
    required String name,
  }) async {
    final safe = sanitizeRemoteSegment(name);
    if (safe == null) {
      final why = remoteSegmentRejectionReason(name);
      throw RemoteStorageException(
        RemoteStorageError.unknown,
        '文件夹名不可用：$name（${why ?? '未知原因'}）',
      );
    }
    final client = clientFor(account);
    final target = joinRemotePath(parentPath, safe);
    if (await client.exists(target)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '已存在同名文件夹：$safe',
      );
    }
    await client.createDirectory(target);
    invalidateListing(account, parentPath);
  }

  /// 重命名（同目录内 MOVE）。[newName] 与原名相同则直接返回。
  Future<void> renameEntry(
    RemoteStorageAccount account, {
    required RemoteStorageEntry entry,
    required String newName,
    bool overwrite = false,
  }) async {
    final safe = sanitizeRemoteSegment(newName);
    if (safe == null) {
      final why = remoteSegmentRejectionReason(newName);
      throw RemoteStorageException(
        RemoteStorageError.unknown,
        '名称不可用：$newName（${why ?? '未知原因'}）',
      );
    }
    if (safe == entry.name) return;

    final client = clientFor(account);
    final parentPath = parentRemotePath(entry.path);
    final target = joinRemotePath(parentPath, safe);
    if (!overwrite && await client.exists(target)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标已存在：$safe',
      );
    }
    await client.move(entry.path, target, overwrite: overwrite);
    invalidateListing(account, parentPath);
  }

  /// 移动到另一个目录（跨目录 MOVE）。
  Future<void> moveEntry(
    RemoteStorageAccount account, {
    required RemoteStorageEntry entry,
    required String targetDir,
    bool overwrite = false,
  }) async {
    final client = clientFor(account);
    final sourceDir = parentRemotePath(entry.path);
    final target = joinRemotePath(targetDir, remoteBasename(entry.path));
    if (target == entry.path) return;

    if (!overwrite && await client.exists(target)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标目录已有同名项：${remoteBasename(entry.path)}',
      );
    }
    await client.move(entry.path, target, overwrite: overwrite);
    invalidateListing(account, sourceDir);
    invalidateListing(account, targetDir);
  }

  /// 账户内复制到另一个目录（COPY 与 MOVE 同一套代码路径）。
  Future<void> copyEntry(
    RemoteStorageAccount account, {
    required RemoteStorageEntry entry,
    required String targetDir,
    bool overwrite = false,
  }) async {
    final client = clientFor(account);
    final target = joinRemotePath(targetDir, remoteBasename(entry.path));
    if (target == entry.path) return;

    if (!overwrite && await client.exists(target)) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标目录已有同名项：${remoteBasename(entry.path)}',
      );
    }
    await client.copy(entry.path, target, overwrite: overwrite);
    invalidateListing(account, targetDir);
  }

  /// 删除一个条目（目录是否递归由服务器决定）。
  Future<void> deleteEntry(
    RemoteStorageAccount account, {
    required RemoteStorageEntry entry,
  }) async {
    await clientFor(account).delete(entry.path);
    invalidateListing(account, parentRemotePath(entry.path));
  }

  /// 批量删除：逐项执行，单项失败不中断整批（返回成功数与失败明细）。
  Future<RemoteBatchResult> deleteEntries(
    RemoteStorageAccount account,
    List<RemoteStorageEntry> entries,
  ) {
    return _runBatch(
      entries,
      (entry) => deleteEntry(account, entry: entry),
    );
  }

  /// 批量移动到同一目录。
  Future<RemoteBatchResult> moveEntries(
    RemoteStorageAccount account, {
    required List<RemoteStorageEntry> entries,
    required String targetDir,
    bool overwrite = false,
  }) {
    return _runBatch(
      entries,
      (entry) => moveEntry(
        account,
        entry: entry,
        targetDir: targetDir,
        overwrite: overwrite,
      ),
    );
  }

  /// 批量复制到同一目录。
  Future<RemoteBatchResult> copyEntries(
    RemoteStorageAccount account, {
    required List<RemoteStorageEntry> entries,
    required String targetDir,
    bool overwrite = false,
  }) {
    return _runBatch(
      entries,
      (entry) => copyEntry(
        account,
        entry: entry,
        targetDir: targetDir,
        overwrite: overwrite,
      ),
    );
  }

  /// 批量执行：单项失败记下原因继续，最后统一汇报（"能做的先做掉"）。
  Future<RemoteBatchResult> _runBatch(
    List<RemoteStorageEntry> entries,
    Future<void> Function(RemoteStorageEntry entry) action,
  ) async {
    var succeeded = 0;
    final failures = <String>[];
    for (final entry in entries) {
      try {
        await action(entry);
        succeeded++;
      } on RemoteStorageException catch (e) {
        failures.add('${entry.name}：${e.message}');
      } catch (e) {
        failures.add('${entry.name}：$e');
      }
    }
    return RemoteBatchResult(succeeded: succeeded, failures: failures);
  }

  /// 图片预览（拍板6：20MB 上限；超限拒绝解码预览）。
  Future<PreviewPayload> readImagePreview(
    RemoteStorageAccount account,
    String path, {
    TransferCancelToken? cancel,
  }) async {
    final client = clientFor(account);
    int? size;
    try {
      size = (await client.head(path)).contentLength;
    } on RemoteStorageException catch (e) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '图片 HEAD 失败，改为直接读取: ${e.message}',
        level: LogLevel.debug,
      );
    }
    if (size != null && size > kPreviewImageMaxBytes) {
      return PreviewPayload(
        bytes: const <int>[],
        truncated: false,
        oversize: true,
        totalLength: size,
      );
    }
    final up = await client.readUpTo(
      path,
      kPreviewImageMaxBytes + 1,
      cancel: cancel,
    );
    final oversize = up.truncated || up.bytes.length > kPreviewImageMaxBytes;
    return PreviewPayload(
      bytes: oversize ? const <int>[] : up.bytes,
      truncated: up.truncated,
      oversize: oversize,
      totalLength: up.totalLength ?? size,
    );
  }

  // ---------------------------------------------------------- 列表缩略图

  /// 取列表缩略图（281+）。取不到返回 null —— 列表回退通用图标，不显示错误。
  ///
  /// 缩略图**只能整张取回来**再降采样解码（JPEG/PNG 要完整文件才能解），所以这里
  /// 先用条目大小挡一道（[isThumbnailableEntry]），再走缓存（内存/磁盘）避免重复
  /// 下载，最后由 [ThumbnailLoader] 限制并发。真正的降采样在 widget 层用
  /// `cacheWidth` 完成（解码尺寸小 → 内存小）。
  Future<Uint8List?> readThumbnail(
    RemoteStorageAccount account,
    RemoteStorageEntry entry, {
    TransferCancelToken? cancel,
  }) async {
    if (!isThumbnailableEntry(entry)) {
      // 超过整取上限（或大小未知）的 JPEG：试 EXIF 内嵌缩略图（283 D1）。
      // 代价有界（一次 [kExifProbeBytes] 的前缀读），比"整取一张 10MB 的图"便宜得多。
      return _readExifThumbnail(account, entry, cancel: cancel);
    }
    final key = thumbnailCacheKey(account.id, entry);
    return _thumbnails.load(key, () async {
      try {
        final up = await clientFor(
          account,
        ).readUpTo(entry.path, kThumbnailMaxBytes + 1, cancel: cancel);
        // 实际比条目声明的大（列表过期）或被截断 → 不缓存、不显示。
        if (up.truncated || up.bytes.length > kThumbnailMaxBytes) return null;
        if (up.bytes.isEmpty) return null;
        return Uint8List.fromList(up.bytes);
      } on RemoteStorageException catch (e) {
        AppLogger.instance.logTo(
          LogChannel.storage,
          '缩略图读取失败（${entry.path}）: ${e.message}',
          level: LogLevel.debug,
        );
        return null;
      }
    });
  }

  /// EXIF 内嵌缩略图（大图/未知大小的 JPEG 走这条）。
  Future<Uint8List?> _readExifThumbnail(
    RemoteStorageAccount account,
    RemoteStorageEntry entry, {
    TransferCancelToken? cancel,
  }) async {
    if (!isExifThumbnailCandidate(entry)) return null;
    final key = thumbnailCacheKey(account.id, entry);
    if (_exifProbeMisses.contains(key)) return null;
    return _thumbnails.load('$key|exif', () async {
      try {
        final up = await clientFor(
          account,
        ).readUpTo(entry.path, kExifProbeBytes, cancel: cancel);
        final thumb = parseExifThumbnail(Uint8List.fromList(up.bytes));
        if (thumb == null) {
          if (_exifProbeMisses.length >= kExifProbeMissLimit) {
            _exifProbeMisses.clear();
          }
          _exifProbeMisses.add(key);
          return null;
        }
        return thumb.bytes;
      } on RemoteStorageException catch (e) {
        AppLogger.instance.logTo(
          LogChannel.storage,
          'EXIF 缩略图探测失败（${entry.path}）: ${e.message}',
          level: LogLevel.debug,
        );
        return null;
      }
    });
  }

  /// 缩略图缓存占用（283 D3：让"看不见的磁盘占用"可观测）。
  Future<ThumbnailCacheUsage> thumbnailCacheUsage() =>
      _thumbnails.cache.usage();

  /// 清空缩略图缓存（内存 + 磁盘）。
  Future<void> clearThumbnailCache() => _thumbnails.cache.clear();

  /// 列表是否显示图片缩略图（持久化偏好）。
  Future<bool> loadThumbnailsEnabled() => _store.loadThumbnailsEnabled();

  Future<void> saveThumbnailsEnabled(bool enabled) =>
      _store.saveThumbnailsEnabled(enabled);

  /// 浏览页排序字段（283 D2，持久化；存枚举名字符串）。
  Future<String?> loadBrowserSortFieldName() =>
      _store.loadBrowserSortFieldName();

  Future<void> saveBrowserSortFieldName(String name) =>
      _store.saveBrowserSortFieldName(name);

  /// 各目录的滚动位置（283 D2，持久化）。
  Future<Map<String, double>> loadBrowserScrollOffsets() =>
      _store.loadBrowserScrollOffsets();

  Future<void> saveBrowserScrollOffsets(Map<String, double> offsets) =>
      _store.saveBrowserScrollOffsets(offsets);

  // ------------------------------------------------------- 播放通道（拍板7）

  /// 判定播放通道：http 明文或自签证书 → 回环中继；否则携带 Basic 直连。
  PlaybackPlan resolvePlayback(
    RemoteStorageAccount account,
    RemoteStorageEntry entry,
  ) {
    final client = clientFor(account);
    final uri = client.uriFor(entry.path);
    final needsRelay =
        uri.scheme.toLowerCase() == 'http' || account.allowBadCert;
    final headers = needsRelay
        ? const <String, String>{}
        : <String, String>{'authorization': _basicAuthHeader(account)};
    return PlaybackPlan(
      needsRelay: needsRelay,
      directUri: uri,
      headers: headers,
    );
  }

  /// 启动回环中继（播放结束务必 await relay.close()）。
  Future<PlaybackRelay> openRelay(
    RemoteStorageAccount account,
    RemoteStorageEntry entry,
  ) async {
    final client = clientFor(account);
    final path = entry.path;
    return PlaybackRelay.start(
      upstream: ({required bool head, String? rangeHeader}) =>
          client.openStream(path, head: head, rangeHeader: rangeHeader),
    );
  }

  static String _basicAuthHeader(RemoteStorageAccount account) {
    final token = base64.encode(
      utf8.encode('${account.username}:${account.password}'),
    );
    return 'Basic $token';
  }

  // ------------------------------------------------------------ 本地目录

  Future<Directory> _downloadDirFor(RemoteStorageAccount account) async {
    final base = await _docsDirProvider();
    final dir = Directory('${base.path}/remote_storage/${account.id}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

// -------------------------------------------------------------- 运行时单例

/// 目录列表缓存有效期（见 [RemoteStorageService.dirCacheTtl]）。
///
/// 取值理由：15s 足够覆盖"返回上一级再进来""来回切目录"这类最常见的重复请求，
/// 又短到不会让用户在两个设备间看到明显过期的内容；下拉刷新与所有写操作都会
/// 强制失效，用户永远有确定的"拿最新"手段。
const Duration kDirCacheTtl = Duration(seconds: 15);

/// 目录列表缓存条目上限（超出后淘汰最久未访问的目录）。
const int kDirCacheMaxEntries = 64;

/// 一个目录的缓存条目。
class _CachedListing {
  const _CachedListing(this.entries, this.storedAt);

  final List<RemoteStorageEntry> entries;
  final DateTime storedAt;
}

RemoteStorageService? _runtimeService;
TransferQueue? _runtimeQueue;

/// 页面共享的 service 实例。
RemoteStorageService remoteStorageService() => _runtimeService ??= RemoteStorageService();

/// 页面共享的传输队列实例。
TransferQueue transferQueue() => _runtimeQueue ??= TransferQueue();

@visibleForTesting
void debugSetRemoteStorageRuntime({
  RemoteStorageService? service,
  TransferQueue? queue,
}) {
  if (service != null) _runtimeService = service;
  if (queue != null) _runtimeQueue = queue;
}
