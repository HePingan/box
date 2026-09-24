// WebDAV 客户端：传输抽象 + PROPFIND 解析 + 流式上传/下载。
//
// - domain 层不依赖 dio：生产传输实现在 remote_storage_service.dart（DioWebdavTransport），
//   测试注入假传输实现，全部逻辑可离线验证。
// - 网络错误 → RemoteStorageException（错误文案见 remote_storage_models.dart）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:xml/xml.dart';

import 'digest_auth.dart';
import 'remote_storage_models.dart';

/// 超过这个字符数才把 PROPFIND 解析丢到后台 isolate（见
/// [WebdavClient.parseListingMaybeIsolated]）。
const int kParseIsolateThresholdChars = 64 * 1024;

/// 一次 WebDAV 请求（传输层无关）。
class WebdavRequest {
  const WebdavRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.bodyStream,
    this.contentLength,
    this.readTextResponse = false,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;

  /// PUT 等写请求的请求体流；GET 时为 null。
  final Stream<List<int>>? bodyStream;
  final int? contentLength;

  /// true 时传输层把响应体读为字符串（PROPFIND/OPTIONS），否则保持流式（GET 文件）。
  final bool readTextResponse;
}

/// 一次 WebDAV 响应（传输层无关）。headers 的 key 一律小写。
class WebdavResponse {
  const WebdavResponse({
    required this.statusCode,
    required this.headers,
    this.bodyText,
    this.bodyStream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String? bodyText;
  final Stream<List<int>>? bodyStream;

  int? get contentLength {
    final raw = headers['content-length'];
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  String? get contentType => headers['content-type'];
}

/// 传输层抽象：生产实现走 dio；测试注入假实现。
abstract class WebdavTransport {
  Future<WebdavResponse> send(WebdavRequest request);
}

/// 连接探测结果（「测试连接」按钮与首次保存时使用）。
class WebdavProbeResult {
  const WebdavProbeResult({
    this.optionsStatus,
    this.davHeader,
    this.allowHeader,
    this.rootListable = false,
    this.rootEntryCount = 0,
    this.errorMessage,
  });

  final int? optionsStatus;
  final String? davHeader;
  final String? allowHeader;
  final bool rootListable;
  final int rootEntryCount;
  final String? errorMessage;

  bool get ok => rootListable;
}

/// WebDAV 客户端。一个账户一个实例（由 service 缓存）。
class WebdavClient {
  WebdavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    required WebdavTransport transport,
    this.connectTimeout = kConnectTimeout,
    this.readTimeout = kReadTimeout,
  }) : _transport = transport {
    _baseUri = _normalizeBaseUri(baseUrl);
  }

  /// 形如 https://dav.jianguoyun.com/dav/ 的根地址（自动补尾斜杠）。
  final String baseUrl;
  final String username;
  final String password;
  final WebdavTransport _transport;
  final Duration connectTimeout;
  final Duration readTimeout;

  late final Uri _baseUri;

  static Uri _normalizeBaseUri(String raw) {
    var s = raw.trim();
    if (!s.endsWith('/')) s = '$s/';
    final uri = Uri.parse(s);
    return uri;
  }

  /// Digest 挑战缓存（C5）：服务器要 Digest 时记住它，后续请求直接带，不再
  /// 每次都先吃一个 401。换账户/密码时客户端实例会被重建（见 service 的
  /// `_clientKeys`），所以这里不需要额外的失效逻辑。
  DigestChallenge? _digestChallenge;

  /// 同一 nonce 下的请求序号（Digest 的 `nc`，服务端用它防重放）。
  int _digestNc = 0;

  Map<String, String> _authHeaders(String method, Uri uri) {
    // 服务器要 Digest 且我们已经拿到挑战 → 直接带 Digest（省掉每请求一次 401）。
    final challenge = _digestChallenge;
    if (challenge != null) {
      final header = _digestAuthorization(challenge, method, uri);
      if (header != null) return {'authorization': header};
    }
    final token = base64.encode(utf8.encode('$username:$password'));
    return {'authorization': 'Basic $token'};
  }

  /// 构造 Digest 响应头；不支持的算法/qop 返回 null（退回 Basic，让上层给出
  /// 明确提示而不是发一个服务器看不懂的头）。
  String? _digestAuthorization(
    DigestChallenge challenge,
    String method,
    Uri uri,
  ) {
    _digestNc += 1;
    try {
      return buildDigestAuthorization(
        challenge: challenge,
        username: username,
        password: password,
        method: method,
        uri: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
        cnonce: newDigestCnonce(),
        nc: _digestNc,
      );
    } on DigestUnsupported {
      return null;
    }
  }

  /// 把账户内的相对路径转成完整 URL（逐段百分号编码）。
  ///
  /// 用归一化后的 [_baseUri]（已保证尾斜杠）拼接；直接用原始 [baseUrl]
  /// 会在用户填了无尾斜杠地址（如 https://dav.example.com/dav）时
  /// 拼出 https://dav.example.com/davBox/a.txt 这类坏 URL。
  Uri uriFor(String relativePath) {
    final encoded = encodeRemotePath(relativePath);
    return Uri.parse('${_baseUri.toString()}$encoded');
  }

  /// 列目录（Depth: 1）。[filterSystemNames] 为 true 时过滤 @eaDir 等系统目录。
  Future<List<RemoteStorageEntry>> list(
    String path, {
    bool filterSystemNames = true,
  }) async {
    final resp = await _send(
      'PROPFIND',
      path,
      headers: {
        'depth': '1',
        'content-type': 'application/xml; charset=utf-8',
      },
      bodyText: _propfindBody,
      readTextReply: true,
    );
    _expect(resp, const {200, 207}, path);

    final xmlText = resp.bodyText ?? '';
    final entries = await parseListingMaybeIsolated(
      xmlText,
      basePath: path,
      baseUri: _baseUri,
      filterSystemNames: filterSystemNames,
    );

    // O6 诊断：目录里出现"看着同名、实为 Unicode 归一化差异"的条目时记一条日志。
    // 这类问题用户只会描述成"同一个文件有两份"，没有这条日志就只能靠猜是服务器
    // 以 NFD 存名、还是真的存在两个文件。
    final pair = _findNormalizationPair(entries);
    if (pair != null) {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '目录「${path.isEmpty ? '/' : path}」里有 Unicode 归一化差异的两个名字：'
        '「${pair.$1}」/「${pair.$2}」',
        level: LogLevel.debug,
      );
    }
    return entries;
  }

  /// 响应较小就在本 isolate 解析，超过阈值才起后台 isolate。
  ///
  /// 阈值取 64KB 的理由：普通目录（几十条）响应只有几 KB，起 isolate 的固定
  /// 开销（约 1–3ms + 一次内存拷贝）比解析本身还贵；而 64KB 大约是 500–800 条
  /// 条目，从这里开始 DOM 解析会出现可感知的卡顿。按字符数近似估算，不做解码。
  static Future<List<RemoteStorageEntry>> parseListingMaybeIsolated(
    String xmlText, {
    required String basePath,
    required Uri baseUri,
    required bool filterSystemNames,
  }) {
    if (xmlText.length < kParseIsolateThresholdChars) {
      return Future<List<RemoteStorageEntry>>.value(
        parseListing(
          xmlText,
          basePath,
          baseUri,
          filterSystemNames: filterSystemNames,
        ),
      );
    }
    return Isolate.run(
      () => parseListing(
        xmlText,
        basePath,
        baseUri,
        filterSystemNames: filterSystemNames,
      ),
    );
  }

  /// 目录里是否存在"看着同名、实为归一化差异"的条目（O6 诊断用）。
  ///
  /// 返回第一对，没有则 null。用户报"同一个文件出现两份"时，这条日志能直接
  /// 判定是服务器以 NFD 存名还是真的有两个文件。
  static (String, String)? _findNormalizationPair(
    List<RemoteStorageEntry> entries,
  ) {
    final names = <String>[
      for (final entry in entries) _basename(entry.path),
    ];
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        if (isNormalizationVariant(names[i], names[j])) {
          return (names[i], names[j]);
        }
      }
    }
    return null;
  }

  /// 判断文件/目录是否存在（HEAD）。
  Future<bool> exists(String path) async {
    final resp = await _send('HEAD', path);
    if (resp.statusCode == 404) return false;
    if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
    if (resp.statusCode == 405 || resp.statusCode == 501) {
      // 个别服务器不支持 HEAD，退回 PROPFIND Depth: 0。
      final probe = await _send(
        'PROPFIND',
        path,
        headers: {'depth': '0'},
        bodyText: _propfindBody,
        readTextReply: true,
      );
      if (probe.statusCode == 404) return false;
      _expect(probe, const {200, 207}, path);
      return true;
    }
    throw _statusToException(resp);
  }

  /// HEAD 探测：大小 / 类型 / 是否支持 Range。
  Future<WebdavHeadInfo> head(String path) async {
    final resp = await _send('HEAD', path);
    if (resp.statusCode == 404) {
      throw const RemoteStorageException(
        RemoteStorageError.notFound,
        '文件不存在（可能已被移动或删除）',
      );
    }
    _expect(resp, const {200, 206}, path);
    return WebdavHeadInfo(
      contentLength: resp.contentLength,
      contentType: resp.contentType,
      acceptRanges: (resp.headers['accept-ranges'] ?? '').isNotEmpty,
    );
  }

  /// 读取文件开头最多 [maxBytes] 字节（用于文本/图片预览）。
  ///
  /// 优先使用 Range 请求；服务器忽略 Range 时读到的流会截断在 maxBytes+1 处，
  /// 由调用方通过 [ReadUpTo.truncated] 判断（截断标记为「已读满/超限」）。
  Future<ReadUpTo> readUpTo(
    String path,
    int maxBytes, {
    TransferCancelToken? cancel,
  }) async {
    final resp = await _send('GET', path, headers: {
      'range': 'bytes=0-${maxBytes - 1}',
    });
    // 206：分段成功；200：服务器忽略 Range，仍可读但需要截断。
    _expect(resp, const {200, 206}, path);

    final builder = BytesBuilder(copy: false);
    var over = false;
    final stream = resp.bodyStream;
    if (stream != null) {
      await for (final chunk in stream) {
        cancel?.throwIfCanceled();
        if (builder.length + chunk.length > maxBytes) {
          final keep = maxBytes - builder.length;
          if (keep > 0) builder.add(chunk.sublist(0, keep));
          over = true;
          break;
        }
        builder.add(chunk);
      }
    } else if (resp.bodyText != null) {
      final bytes = utf8.encode(resp.bodyText!);
      final keep = math.min(bytes.length, maxBytes);
      builder.add(bytes.sublist(0, keep));
      over = bytes.length > maxBytes;
    }
    cancel?.throwIfCanceled();

    final bytes = builder.takeBytes();
    final total = resp.contentLength;
    final truncated = over || (total != null && total > bytes.length);
    return ReadUpTo(
      bytes: Uint8List.fromList(bytes),
      truncated: truncated,
      totalLength: total,
    );
  }

  /// 下载到 [destFile]。
  ///
  /// [resumeFrom] > 0 时带 `Range: bytes=N-` 续传（OSS/C2）：
  ///  - 服务端返回 **206** → 追加写入 `.part` 剩余部分；
  ///  - 返回 **200** → 说明它忽略了 Range（或 Range 已失效），**必须截断重写**，
  ///    否则会在文件头部叠一份重复内容；
  ///  - 拿到全长（`Content-Range` 的 total 或 200 的 `content-length`）时校验最终
  ///    字节数，不足即抛错并保留断点——宁可下一轮续传，也不要交出半截文件。
  Future<void> downloadTo(
    String path,
    File destFile, {
    void Function(int received, int total)? onProgress,
    TransferCancelToken? cancel,
    int resumeFrom = 0,
  }) async {
    final canResume =
        resumeFrom > 0 &&
        await destFile.exists() &&
        await destFile.length() == resumeFrom;
    final resp = await _send(
      'GET',
      path,
      headers: canResume ? {'range': 'bytes=$resumeFrom-'} : const {},
    );
    _expect(resp, const {200, 206}, path);

    final partial = parseContentRange(resp.headers['content-range']);
    // 只有"确实按 Range 返回"才算续传：206 且 Content-Range 起点与请求一致。
    final appending =
        canResume && resp.statusCode == 206 && partial?.start == resumeFrom;
    final startAt = appending ? resumeFrom : 0;
    final total = appending
        ? (partial?.total ?? resumeFrom + (resp.contentLength ?? 0))
        : (resp.contentLength ?? -1);

    var received = startAt;
    IOSink? sink;
    try {
      sink = appending
          ? destFile.openWrite(mode: FileMode.append)
          : destFile.openWrite();
      final stream = resp.bodyStream;
      if (stream != null) {
        await for (final chunk in stream) {
          cancel?.throwIfCanceled();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } else if (resp.bodyText != null) {
        final bytes = utf8.encode(resp.bodyText!);
        sink.add(bytes);
        received += bytes.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink?.close();
    }

    if (total > 0 && received != total) {
      // 保留 .part（下一轮还能续），但这一轮必须算失败：把不完整的文件当成成果
      // 交给上层，用户拿到的是"能打开但内容是坏的"包。
      throw RemoteStorageException(
        RemoteStorageError.http,
        '下载不完整（$received/$total 字节），已保留断点可续传',
        statusCode: resp.statusCode,
      );
    }
  }

  /// 流式上传 [srcFile] 到 [relativePath]（PUT）。
  Future<void> uploadFrom(
    File srcFile,
    String relativePath, {
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancel,
  }) async {
    final length = await srcFile.length();

    Stream<List<int>> body() {
      var sent = 0;
      return srcFile.openRead().map((chunk) {
        cancel?.throwIfCanceled();
        sent += chunk.length;
        onProgress?.call(sent, length);
        return chunk;
      });
    }

    final resp = await _send(
      'PUT',
      relativePath,
      headers: {'content-type': 'application/octet-stream'},
      bodyStream: body(),
      // 文件还在本地，被 401（Digest 挑战）打断时能重开一次流再传，
      // 否则只能传个空文件或者白失败一次。
      reopenBody: body,
      contentLength: length,
    );
    // 201 新建 / 200、204 覆盖成功 / 507 空间不足等由 _expect 统一处理。
    _expect(resp, const {200, 201, 204}, relativePath);
  }

  /// 删除文件或目录（DELETE）。
  ///
  /// 目录是否递归删除由服务器决定（多数实现递归）——UI 的确认文案必须写清
  /// "目录内所有内容一并删除"。
  Future<void> delete(String path) async {
    final resp = await _send('DELETE', path);
    if (resp.statusCode == 404) {
      throw RemoteStorageException(
        RemoteStorageError.notFound,
        '远端已不存在：${_basename(path)}',
        statusCode: 404,
      );
    }
    if (resp.statusCode == 403) {
      throw const RemoteStorageException(
        RemoteStorageError.forbidden,
        '服务器拒绝删除（只读挂载或权限不足）',
        statusCode: 403,
      );
    }
    _expect(resp, const {200, 202, 204}, path);
  }

  /// 新建目录（MKCOL）。
  ///
  /// `405` 在 MKCOL 上的含义是"目录已存在"（不是"服务器不支持该方法"），
  /// 因此单独给出冲突文案，避免用户以为是 DAV 没开。
  Future<void> createDirectory(String path) async {
    final resp = await _send('MKCOL', path);
    if (resp.statusCode == 405 || resp.statusCode == 409) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目录已存在：${_basename(path)}',
        statusCode: resp.statusCode,
      );
    }
    if (resp.statusCode == 403) {
      throw const RemoteStorageException(
        RemoteStorageError.forbidden,
        '服务器拒绝新建目录（只读挂载或权限不足）',
        statusCode: 403,
      );
    }
    _expect(resp, const {201}, path);
  }

  /// 重命名 / 移动（MOVE）。[overwrite] 为 false 时目标已存在会失败（412）。
  Future<void> move(String from, String to, {bool overwrite = false}) =>
      _relocate('MOVE', from, to, overwrite: overwrite);

  /// 账户内复制（COPY）。跨账户复制服务端不支持，只能下载再上传。
  Future<void> copy(String from, String to, {bool overwrite = false}) =>
      _relocate('COPY', from, to, overwrite: overwrite);

  /// MOVE/COPY 共用实现。
  ///
  /// 两个协议细节不能省：
  /// 1. `Destination` 必须是**绝对 URL 且已百分号编码**（相对路径会被拒）；
  /// 2. `Overwrite: F` 明确"不许静默覆盖"——默认行为各服务器不一致，显式声明后
  ///    目标存在时统一返回 412，UI 的"目标已存在"提示才有确定语义。
  Future<void> _relocate(
    String method,
    String from,
    String to, {
    required bool overwrite,
  }) async {
    final resp = await _send(
      method,
      from,
      headers: {
        'destination': uriFor(to).toString(),
        'overwrite': overwrite ? 'T' : 'F',
      },
    );
    if (resp.statusCode == 412) {
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标已存在：${_basename(to)}',
        statusCode: 412,
      );
    }
    if (resp.statusCode == 409) {
      // 409：目标父目录不存在，或 Destination 指向另一个命名空间。
      throw RemoteStorageException(
        RemoteStorageError.conflict,
        '目标路径不可用（上级目录不存在？）：${_basename(to)}',
        statusCode: 409,
      );
    }
    _expect(resp, const {200, 201, 204}, from);
  }

  /// 打开原始响应流（播放中继/直连用）：不抛错，状态码原样透传。
  Future<WebdavResponse> openStream(
    String path, {
    bool head = false,
    String? rangeHeader,
  }) async {
    final headers = <String, String>{};
    if (rangeHeader != null && rangeHeader.isNotEmpty) {
      headers['range'] = rangeHeader;
    }
    return _send(head ? 'HEAD' : 'GET', path, headers: headers);
  }

  /// OPTIONS + PROPFIND 探测（「测试连接」）。
  Future<WebdavProbeResult> probe() async {
    int? optionsStatus;
    String? davHeader;
    String? allowHeader;
    try {
      final resp = await _send('OPTIONS', '');
      optionsStatus = resp.statusCode;
      davHeader = resp.headers['dav'];
      allowHeader = resp.headers['allow'];
    } on RemoteStorageException {
      // OPTIONS 失败不致命：部分服务器禁用 OPTIONS，继续用 PROPFIND 探测。
      optionsStatus = null;
    }
    try {
      final entries = await list('');
      return WebdavProbeResult(
        optionsStatus: optionsStatus,
        davHeader: davHeader,
        allowHeader: allowHeader,
        rootListable: true,
        rootEntryCount: entries.length,
      );
    } on RemoteStorageException catch (e) {
      return WebdavProbeResult(
        optionsStatus: optionsStatus,
        davHeader: davHeader,
        allowHeader: allowHeader,
        rootListable: false,
        errorMessage: e.message,
      );
    }
  }

  /// 目录配额（RFC 4331：`quota-available-bytes` / `quota-used-bytes`）。
  ///
  /// 缺失是常态（不是所有服务器实现该扩展），所以：属性没返回就返回空对象，
  /// 由 UI 决定不显示——配额是锦上添花，绝不能因为它把页面搞成报错态。
  Future<RemoteStorageQuota> quota(String path) async {
    final resp = await _send(
      'PROPFIND',
      path,
      headers: {
        'depth': '0',
        'content-type': 'application/xml; charset=utf-8',
      },
      bodyText: _quotaPropfindBody,
      readTextReply: true,
    );
    _expect(resp, const {200, 207}, path);
    return parseQuotaMultistatus(resp.bodyText ?? '');
  }

  /// 配额 XML 解析（纯函数，便于用真样例做 fixture 测试）。
  static RemoteStorageQuota parseQuotaMultistatus(String xmlText) {
    if (xmlText.trim().isEmpty) return const RemoteStorageQuota();
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException {
      return const RemoteStorageQuota();
    }
    for (final response in _elementsByLocal(doc.rootElement, 'response')) {
      final prop = _propElementStatic(response);
      if (prop == null) continue;
      return RemoteStorageQuota(
        availableBytes: _intProp(prop, 'quota-available-bytes'),
        usedBytes: _intProp(prop, 'quota-used-bytes'),
      );
    }
    return const RemoteStorageQuota();
  }

  /// 取 prop 下的整数值；缺失、非法、负数（RFC 中 -3 等表示"未知"）一律 null。
  static int? _intProp(XmlElement prop, String local) {
    final raw = _firstTextByLocal(prop, local);
    if (raw == null) return null;
    final value = int.tryParse(raw.trim());
    if (value == null || value < 0) return null;
    return value;
  }

  /// 取 DAV:prop（优先取 propstat 状态为 200 的那个）。
  static XmlElement? _propElementStatic(XmlElement response) {
    XmlElement? fallback;
    for (final propstat in _elementsByLocal(response, 'propstat')) {
      final status = _firstTextByLocal(propstat, 'status') ?? '';
      final props = _elementsByLocal(propstat, 'prop');
      final prop = props.isEmpty ? null : props.first;
      if (prop == null) continue;
      if (status.contains(' 200 ')) return prop;
      fallback ??= prop;
    }
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:getcontentlength/><d:getlastmodified/>'
      '<d:resourcetype/><d:getcontenttype/><d:getetag/>'
      '</d:prop></d:propfind>';

  /// 配额探测（RFC 4331）：只问目录自己，Depth: 0。
  static const String _quotaPropfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:quota-available-bytes/><d:quota-used-bytes/>'
      '</d:prop></d:propfind>';

  Future<WebdavResponse> _send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? bodyText,
    Stream<List<int>>? bodyStream,
    /// 可重放的请求体（Digest 401 重试用）：与 [bodyStream] 同源、能再开一次。
    Stream<List<int>> Function()? reopenBody,
    int? contentLength,
    bool readTextReply = false,
  }) async {
    final resp = await _dispatch(
      method,
      path,
      headers: headers,
      bodyText: bodyText,
      bodyStream: bodyStream,
      contentLength: contentLength,
      readTextReply: readTextReply,
    );
    if (resp.statusCode != 401) return resp;

    // Digest 挑战（C5）：自建 nginx/apache 常只开 Digest，我们发的 Basic 会一直
    // 被拒（401）。拿到挑战就重试一次，并把挑战记住供后续请求直接用。
    final challenge =
        DigestChallenge.tryParse(resp.headers['www-authenticate']);
    if (challenge == null) return resp; // 真·密码错，或服务器只认 Basic
    _digestChallenge = challenge;

    final unsupported = challenge.unsupportedReason;
    if (unsupported != null) {
      throw RemoteStorageException(
        RemoteStorageError.unauthorized,
        '服务器要求 Digest 认证的$unsupported 形式，当前版本不支持；'
        '可在服务器上改用 Basic 认证',
        statusCode: 401,
      );
    }

    if (bodyStream != null && reopenBody == null) {
      // 流式请求体已经发出去、读不回来：盲目重发会传一个空文件。
      // 当前所有流式调用方（uploadFrom）都给了 [reopenBody]，所以这条分支是给
      // 将来新增流式调用方留的安全网——宁可报一次"重试即可"，也不要静默传空文件。
      // 挑战已记住，下一次请求（队列重试或用户再点一次）第一个请求就带 Digest，
      // 所以这里显式标记为"值得重试"。
      throw const RemoteStorageException(
        RemoteStorageError.unauthorized,
        '服务器要求 Digest 认证（已记住认证方式，重试即可）',
        statusCode: 401,
        retryable: true,
      );
    }

    return _dispatch(
      method,
      path,
      headers: headers,
      bodyText: bodyText,
      bodyStream: reopenBody?.call() ?? bodyStream,
      contentLength: contentLength,
      readTextReply: readTextReply,
    );
  }

  /// 真正发一次请求（认证头按当前状态选 Basic/Digest）。
  Future<WebdavResponse> _dispatch(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? bodyText,
    Stream<List<int>>? bodyStream,
    int? contentLength,
    bool readTextReply = false,
  }) {
    final uri = uriFor(path);
    final allHeaders = <String, String>{..._authHeaders(method, uri), ...headers};
    if (contentLength != null) {
      allHeaders['content-length'] = '$contentLength';
    }
    final body = bodyStream ??
        (bodyText != null ? Stream<List<int>>.value(utf8.encode(bodyText)) : null);
    if (body != null && !allHeaders.containsKey('content-type')) {
      allHeaders['content-type'] = 'application/xml; charset=utf-8';
    }
    final request = WebdavRequest(
      method: method,
      uri: uri,
      headers: allHeaders,
      bodyStream: body,
      contentLength: contentLength ??
          (bodyText != null ? utf8.encode(bodyText).length : null),
      readTextResponse: readTextReply,
    );
    return _transport.send(request).catchError((Object error) {
      throw mapTransportError(error);
    });
  }

  WebdavResponse _expect(
    WebdavResponse resp,
    Set<int> okStatuses,
    String path,
  ) {
    if (okStatuses.contains(resp.statusCode)) return resp;
    throw _statusToException(resp);
  }

  /// 状态码 → 归一异常；顺带解析 `Retry-After`，让传输队列按服务端要求退避
  /// （429/503 常见）。
  RemoteStorageException _statusToException(WebdavResponse resp) =>
      remoteStorageExceptionForStatus(
        resp.statusCode,
        retryAfter: parseRetryAfterHeader(resp.headers['retry-after']),
      );

  /// 解析 PROPFIND 响应，并完成系统目录过滤与排序。
  ///
  /// 静态纯函数（只吃参数、不读实例状态），因此可以在后台 isolate 里跑：
  /// 上千条的 multistatus 在 UI isolate 做 DOM 解析会直接掉帧（方案文档 O4）。
  static List<RemoteStorageEntry> parseListing(
    String xmlText,
    String basePath,
    Uri baseUri, {
    bool filterSystemNames = true,
  }) {
    if (xmlText.trim().isEmpty) {
      throw const RemoteStorageException(
        RemoteStorageError.unknown,
        '服务器返回内容无法解析（非 WebDAV 服务？）',
      );
    }
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException {
      throw const RemoteStorageException(
        RemoteStorageError.unknown,
        '服务器返回内容无法解析（非 WebDAV 服务？）',
      );
    }

    final selfPath = _normalizeCollectionPath(basePath);
    final entries = <RemoteStorageEntry>[];

    for (final response in _elementsByLocal(doc.rootElement, 'response')) {
      final href = _firstTextByLocal(response, 'href');
      if (href == null || href.trim().isEmpty) continue;

      final relPath = _relativizeHref(href.trim(), baseUri);
      if (relPath == null) continue;
      final normalized = relPath.isEmpty ? '' : relPath;
      if (normalized == selfPath) continue; // 目录自身

      final prop = _propElementStatic(response);
      final isCollection =
          prop != null && _hasCollectionChild(prop);
      final displayName = prop == null
          ? null
          : _firstTextByLocal(prop, 'displayname')?.trim();
      final name = (displayName == null || displayName.isEmpty)
          ? _basename(normalized)
          : displayName;
      if (name.isEmpty) continue;

      final sizeText =
          prop == null ? null : _firstTextByLocal(prop, 'getcontentlength');
      final size = sizeText == null ? null : int.tryParse(sizeText.trim());
      final modified =
          prop == null ? null : _parseHttpDate(_firstTextByLocal(prop, 'getlastmodified'));
      final etagText =
          prop == null ? null : _firstTextByLocal(prop, 'getetag')?.trim();
      final etag = (etagText == null || etagText.isEmpty) ? null : etagText;

      entries.add(RemoteStorageEntry(
        name: name,
        path: normalized,
        isDirectory: isCollection,
        size: isCollection ? null : size,
        modifiedAt: modified,
        etag: etag,
      ));
    }

    // 过滤与排序一并放在这里：后台 isolate 里做完再回传，避免把上千条又搬到
    // UI isolate 再排一遍。
    var result = entries;
    if (filterSystemNames) {
      result = entries
          .where((e) => !kWebdavSystemDirNames.contains(e.name))
          .toList(growable: false);
    }
    final sorted = List<RemoteStorageEntry>.from(result);
    sorted.sort(_entryComparator);
    return sorted;
  }

  static bool _hasCollectionChild(XmlElement prop) {
    final rts = _elementsByLocal(prop, 'resourcetype');
    if (rts.isEmpty) return false;
    return _elementsByLocal(rts.first, 'collection').isNotEmpty;
  }

  /// href → 相对账户根的路径（不含首斜杠）；不在根内时返回 null。
  ///
  /// 参数化 [baseUri] 而不是读实例字段：解析要在后台 isolate 里跑
  /// （见 [parseListing]），静态纯函数才送得进 isolate。
  static String? _relativizeHref(String href, Uri baseUri) {
    final basePrefix = baseUri.path; // 以 / 结尾
    String rawPath;
    try {
      final full = baseUri.resolve(href);
      rawPath = full.path;
      // 用解码后的段重建，避免 %E4%B8%AD 之类的编码进入名称。
      final decodedSegments = full.pathSegments;
      rawPath = decodedSegments.isEmpty ? '/' : '/${decodedSegments.join('/')}';
    } on FormatException {
      rawPath = href;
    }
    var normalized = rawPath.replaceAll('//', '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';

    var base = basePrefix.replaceAll('//', '/');
    if (!base.startsWith('/')) base = '/$base';
    if (!base.endsWith('/')) base = '$base/';

    String decodedBase;
    try {
      final baseSegments = baseUri.pathSegments;
      decodedBase = baseSegments.isEmpty ? '/' : '/${baseSegments.join('/')}/';
      decodedBase = decodedBase.replaceAll('//', '/');
    } on FormatException {
      decodedBase = base;
    }

    // 自身条目匹配：忽略尾斜杠差异（部分服务器返回 /dav 而非 /dav/，
    // 若不做去尾斜杠比较，根目录列表会出现名为 dav 的幻影条目）。
    final trimmedNormalized = normalized.replaceFirst(RegExp(r'/+$'), '');
    final trimmedBase = decodedBase.replaceFirst(RegExp(r'/+$'), '');
    if (normalized == decodedBase ||
        normalized == base ||
        trimmedNormalized == trimmedBase) {
      return '';
    }
    if (normalized.startsWith(decodedBase)) {
      var rest =
          normalized.substring(decodedBase.length).replaceAll(RegExp(r'/+$'), '');
      return _tryDecode(rest);
    }
    if (normalized.startsWith('/')) {
      // 个别服务器返回不含根前缀的路径，直接尝试相对化。
      var rest = normalized.substring(1);
      return _tryDecode(rest);
    }
    return null;
  }

  static String _tryDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } on ArgumentError {
      return s;
    } on FormatException {
      return s;
    }
  }

  static String _normalizeCollectionPath(String path) {
    var p = path;
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p.replaceAll(RegExp(r'/+$'), '');
  }

  static String _basename(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  static DateTime? _parseHttpDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    try {
      return HttpDate.parse(s);
    } catch (_) {
      return null;
    }
  }

  static List<XmlElement> _elementsByLocal(XmlElement parent, String local) {
    return parent.childElements
        .where((e) => e.name.local == local)
        .toList(growable: false);
  }

  static String? _firstTextByLocal(XmlElement parent, String local) {
    for (final e in parent.childElements) {
      if (e.name.local == local) {
        final t = e.innerText;
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  static int _entryComparator(RemoteStorageEntry a, RemoteStorageEntry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// HEAD 结果。
class WebdavHeadInfo {
  const WebdavHeadInfo({
    this.contentLength,
    this.contentType,
    this.acceptRanges = false,
  });

  final int? contentLength;
  final String? contentType;
  final bool acceptRanges;
}

/// readUpTo 结果。
class ReadUpTo {
  const ReadUpTo({
    required this.bytes,
    required this.truncated,
    this.totalLength,
  });

  final Uint8List bytes;
  final bool truncated;
  final int? totalLength;
}

/// 传输层抛出的原始错误 → 已归一的中文异常。
RemoteStorageException mapTransportError(Object error) {
  if (error is RemoteStorageException) return error;
  if (error is TransferCanceledException) {
    return const RemoteStorageException(RemoteStorageError.canceled, '已取消');
  }
  // 防御性加固：非 dio 传输直抛的原始错误也落「存储」频道，与 mapDioException
  // 的归一化落盘对称。生产 dio 路径不会重复：归一后的异常在上方已提前返回。
  AppLogger.instance.logChannelError(LogChannel.storage, error);
  if (error is SocketException) {
    return const RemoteStorageException(
      RemoteStorageError.network,
      '无法连接服务器：请检查网络与地址',
    );
  }
  if (error is HandshakeException) {
    return const RemoteStorageException(
      RemoteStorageError.certificate,
      '证书校验失败：可开启「允许自签名证书」后重试',
    );
  }
  if (error is TimeoutException) {
    return const RemoteStorageException(
      RemoteStorageError.timeout,
      '连接超时：请检查网络或服务器地址',
    );
  }
  if (error is HttpException) {
    return const RemoteStorageException(
      RemoteStorageError.network,
      '网络错误：无法完成请求',
    );
  }
  return RemoteStorageException(
    RemoteStorageError.unknown,
    '请求失败：${error.runtimeType}',
  );
}

/// `Retry-After` 头解析：支持秒数（`120`）与 HTTP-date 两种形式；无法解析、
/// 或解析结果非正值（已过期）时返回 null。
///
/// 放在协议层而非 models：models 保持零 dart:io 依赖，便于纯单测与 web 构建。
Duration? parseRetryAfterHeader(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final seconds = int.tryParse(text);
  if (seconds != null) {
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }
  try {
    final at = HttpDate.parse(text);
    final delta = at.difference(DateTime.now().toUtc());
    return delta.inSeconds > 0 ? delta : null;
  } catch (_) {
    return null;
  }
}

/// 请求级留痕：方法 / 路径 / 状态码 / 耗时。
///
/// 为什么连成功也要记：`404` 通常是"服务器地址少写了 /dav 前缀"，`401` 是
/// "用了登录密码而不是应用密码"，`507` 是"空间不足"——这些都必须看到**请求行**
/// 才能定位；原实现只在抛异常时落盘，用户报"连不上"时日志里往往一片空白。
///
/// 脱敏：只记路径，绝不记用户名/密码（凭据在请求头里，不进日志）；路径过长时
/// 保留尾部（文件名在尾部，更有诊断价值），避免超长文件名撑爆日志行。
void traceWebdavRequest(
  WebdavRequest request,
  int statusCode,
  Duration elapsed,
) {
  final path = request.uri.path;
  final shown =
      path.length > 200 ? '…${path.substring(path.length - 200)}' : path;
  AppLogger.instance.logTo(
    LogChannel.storage,
    '${request.method} $shown → $statusCode (${elapsed.inMilliseconds}ms)',
    level: statusCode >= 400 ? LogLevel.warn : LogLevel.debug,
  );
}
