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
import '../domain/remote_storage_models.dart';
import '../domain/webdav_client.dart';
import 'playback_relay.dart';
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
  })  : _store = store ?? RemoteStorageStore(),
        _transportFactory = transportFactory,
        _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  final RemoteStorageStore _store;
  final WebdavTransport Function(RemoteStorageAccount account)? _transportFactory;
  final Future<Directory> Function() _docsDirProvider;

  final Map<String, String> _clientKeys = {};
  final Map<String, WebdavClient> _clients = {};

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
  }

  Future<void> deleteAccount(String id) async {
    final all = await _store.loadAccounts();
    all.removeWhere((a) => a.id == id);
    await _store.saveAccounts(all);
    _invalidateClient(id);
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
    String path,
  ) {
    return clientFor(account).list(
      path,
      filterSystemNames: !account.showSystemFolders,
    );
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
      final entries = await client.list(
        targetDir,
        filterSystemNames: !account.showSystemFolders,
      );
      final existing = <String>{
        for (final entry in entries)
          if (!entry.isDirectory) _basenameOfRemotePath(entry.path),
      };
      return [
        for (final candidate in wanted.entries)
          if (existing.contains(candidate.key)) candidate.value,
      ];
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
    final target = await _uniqueFile(dir, safe);
    final temp = File('${target.path}.part');
    try {
      await client.downloadTo(
        remotePath,
        temp,
        onProgress: onProgress,
        cancel: cancel,
      );
      await temp.rename(target.path);
    } catch (e) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
    return target.path;
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
      throw RemoteStorageException(
        RemoteStorageError.unknown,
        '文件名不合法：${file.name}',
      );
    }
    final remotePath = joinRemotePath(targetDir, safe);
    if (!overwrite) {
      if (await client.exists(remotePath)) return false; // 拍板3：默认跳过
    }
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

  static Future<File> _uniqueFile(Directory dir, String baseName) async {
    var candidate = File('${dir.path}/$baseName');
    if (!await candidate.exists()) return candidate;
    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    final ext = dot > 0 ? baseName.substring(dot) : '';
    for (var i = 1; i <= 200; i++) {
      candidate = File('${dir.path}/$stem ($i)$ext');
      if (!await candidate.exists()) return candidate;
    }
    return candidate;
  }
}

// -------------------------------------------------------------- 运行时单例

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
