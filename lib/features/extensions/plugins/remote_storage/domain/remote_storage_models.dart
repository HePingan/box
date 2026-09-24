// 远程存储（WebDAV）插件：模型、常量与纯函数。
//
// 本文件不依赖 Flutter / dio / 网络，全部逻辑可在单测里直接验证。
// 设计文档：docs/remote_storage_plugin_plan.md（拍板于 2026-09-20）。

import 'dart:convert';
import 'dart:math' as math;

/// 连接超时（拍板：可调；调大→弱网更稳但失败反馈变慢）。
const Duration kConnectTimeout = Duration(seconds: 10);

/// 读超时（同上方向）。
const Duration kReadTimeout = Duration(seconds: 30);

/// 图片预览上限：超过则不下载预览（调大→更大图可预览但内存风险上升）。
const int kPreviewImageMaxBytes = 20 * 1024 * 1024;

/// 文本预览前缀上限（调大→更完整但载入变慢）。
const int kPreviewTextMaxBytes = 512 * 1024;

/// 播放中继空闲自动关闭：无请求且无在途取流超过该时长即回收（调大→保留更久；调小→端口更快回收）。
const Duration kRelayIdleTimeout = Duration(minutes: 30);

/// 传输队列并发数（调大→更快但弱 NAS 失败率升高）。
const int kMaxConcurrentTransfers = 1;

/// 失败自动重试次数（不含首次；调大→更稳但失败等待变长）。
///
/// ⚠️ 不是所有失败都值得重试：401/403/404/405/409/507 这类"重试也是一样结果"
/// 的错误由 [isRetryableTransferError] 挡在重试之外，避免凭证错、空间不足时
/// 白等两个退避周期才报错。
const int kTransferRetries = 2;

/// 重试退避序列（第 n 次重试前等待 [n-1]）。固定 800ms 在弱网上等于连撞三次墙。
/// 服务端给了 `Retry-After` 时取二者较大值（见 [parseRetryAfterHeader]）。
const List<Duration> kTransferRetryDelays = [
  Duration(milliseconds: 800),
  Duration(seconds: 2),
];

/// WebDAV 系统目录过滤名单（启发式；名单调大→列表更干净但可能误伤同名真实目录）。
const Set<String> kWebdavSystemDirNames = {
  '@eaDir',
  '#recycle',
  '.DS_Store',
  '.Trashes',
};

/// 内网主机判定（RFC1918 / 回环 / 链路本地 / CGNAT / .local / 单标签主机名）。
///
/// 用于拍板 5「私网默认允许 http 与自签」。单标签主机名（如 `nas`）只能经
/// 局域网 DNS/mDNS 解析，按内网对待；带点域名按公网对待。
bool isPrivateHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  final bare = h.startsWith('[') && h.endsWith(']')
      ? h.substring(1, h.length - 1)
      : h;
  if (bare == 'localhost' || bare == '::1') return true;
  if (bare.contains(':')) {
    // IPv6：链路本地 fe80::/10 与唯一本地地址 fc00::/7。
    return bare.startsWith('fe80:') ||
        bare.startsWith('fc') ||
        bare.startsWith('fd');
  }
  final parts = bare.split('.');
  if (parts.length == 4) {
    final nums = <int>[];
    for (final p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
      nums.add(v);
    }
    final a = nums[0];
    final b = nums[1];
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 127) return true;
    if (a == 169 && b == 254) return true;
    // 100.64.0.0/10：运营商级 NAT 段，Tailscale 等亦使用。
    if (a == 100 && b >= 64 && b <= 127) return true;
    return false;
  }
  if (bare.endsWith('.local')) return true;
  if (!bare.contains('.')) return true;
  return false;
}

/// TLS 模式（拍板 5）：auto=私网自动放行；allow=始终允许 http；deny=始终禁止。
enum RemoteTlsMode {
  auto,
  allow,
  deny;

  String get label {
    switch (this) {
      case RemoteTlsMode.auto:
        return '自动（私网允许）';
      case RemoteTlsMode.allow:
        return '始终允许不安全连接';
      case RemoteTlsMode.deny:
        return '始终禁止 http';
    }
  }

  static RemoteTlsMode fromName(String? name) {
    for (final v in RemoteTlsMode.values) {
      if (v.name == name) return v;
    }
    return RemoteTlsMode.auto;
  }
}

/// 一个已保存的存储账户。
class RemoteStorageAccount {
  const RemoteStorageAccount({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.username,
    required this.password,
    this.tlsMode = RemoteTlsMode.auto,
    this.allowBadCert = false,
    this.showSystemFolders = false,
    this.createdAt = 0,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String username;
  final String password;

  /// http 明文策略。
  final RemoteTlsMode tlsMode;

  /// 允许自签名证书（仅对该账户主机放行）。
  final bool allowBadCert;

  /// 是否在列表中显示系统目录（@eaDir 等）。
  final bool showSystemFolders;

  final int createdAt;

  Uri? get baseUri => Uri.tryParse(baseUrl);

  String get host => baseUri?.host ?? '';

  String get scheme => (baseUri?.scheme ?? '').toLowerCase();

  bool get isHttp => scheme == 'http';

  String get displayHost {
    final uri = baseUri;
    if (uri == null) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// http 是否实际放行：auto 且私网 → 放行；allow → 放行；deny → 禁止。
  bool get httpEffectiveAllowed {
    if (!isHttp) return false;
    switch (tlsMode) {
      case RemoteTlsMode.allow:
        return true;
      case RemoteTlsMode.deny:
        return false;
      case RemoteTlsMode.auto:
        return isPrivateHost(host);
    }
  }

  /// 是否属于「不安全连接」（卡片提示徽标用，仅提示不拦截）。
  bool get isInsecure => isHttp || allowBadCert;

  RemoteStorageAccount copyWith({
    String? label,
    String? baseUrl,
    String? username,
    String? password,
    RemoteTlsMode? tlsMode,
    bool? allowBadCert,
    bool? showSystemFolders,
  }) {
    return RemoteStorageAccount(
      id: id,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      tlsMode: tlsMode ?? this.tlsMode,
      allowBadCert: allowBadCert ?? this.allowBadCert,
      showSystemFolders: showSystemFolders ?? this.showSystemFolders,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    'tlsMode': tlsMode.name,
    'allowBadCert': allowBadCert,
    'showSystemFolders': showSystemFolders,
    'createdAt': createdAt,
  };

  static RemoteStorageAccount? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final baseUrl = raw['baseUrl']?.toString().trim() ?? '';
    if (id.isEmpty || baseUrl.isEmpty) return null;
    return RemoteStorageAccount(
      id: id,
      label: raw['label']?.toString().trim() ?? '',
      baseUrl: baseUrl,
      username: raw['username']?.toString() ?? '',
      password: raw['password']?.toString() ?? '',
      tlsMode: RemoteTlsMode.fromName(raw['tlsMode']?.toString()),
      allowBadCert: raw['allowBadCert'] == true,
      showSystemFolders: raw['showSystemFolders'] == true,
      createdAt:
          int.tryParse(raw['createdAt']?.toString() ?? '') ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String newId() {
    final rand = math.Random.secure();
    final tail = List.generate(
      6,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    return 'rs_${DateTime.now().microsecondsSinceEpoch}_$tail';
  }

  /// 服务器地址校验；返回 null 表示合法，否则返回中文错误文案。
  static String? validateBaseUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '请输入服务器地址';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '地址无法解析，请包含 http:// 或 https:// 前缀';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return '仅支持 http:// 与 https://';
    }
    return null;
  }
}

/// 远端目录条目。
class RemoteStorageEntry {
  const RemoteStorageEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.etag,
  });

  final String name;

  /// 相对于账户 baseUrl 的路径，如 `Box/笔记.txt`。
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;

  /// 服务端的 `getetag`（含引号，原样保留）。
  ///
  /// 用途：[RemoteStorageService] 的目录缓存失效判定、以及后续「上传前
  /// 条件写（If-Match）」「跳过未变化文件」的基础。服务器不返回该属性时为 null
  /// —— 不要用它做唯一判据，缺失是常态（Apache mod_dav 默认不发）。
  final String? etag;
}

/// 配额信息（WebDAV `quota-available-bytes` / `quota-used-bytes`）。
///
/// 两者都可能缺失（不是所有服务器实现 RFC4331，Nextcloud/MinIO 支持较好）。
class RemoteStorageQuota {
  const RemoteStorageQuota({this.availableBytes, this.usedBytes});

  final int? availableBytes;
  final int? usedBytes;

  /// 是否拿到了可用信息（用于决定 UI 显不显示这一行）。
  bool get hasAny => availableBytes != null || usedBytes != null;
}

/// 条目大类（决定预览/播放/下载后打开）。
enum RemoteEntryKind { folder, image, video, audio, text, other }

const Set<String> _imageExts = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'avif',
};

const Set<String> _videoExts = {
  'mp4',
  'mkv',
  'mov',
  'avi',
  'webm',
  '3gp',
  'm4v',
  'ts',
  'flv',
  'wmv',
  'mpg',
  'mpeg',
};

const Set<String> _audioExts = {
  'mp3',
  'flac',
  'wav',
  'aac',
  'm4a',
  'ogg',
  'opus',
  'wma',
  'amr',
  'ape',
};

const Set<String> _textExts = {
  'txt',
  'md',
  'markdown',
  'json',
  'xml',
  'yaml',
  'yml',
  'log',
  'csv',
  'tsv',
  'ini',
  'cfg',
  'conf',
  'dart',
  'js',
  'mjs',
  'ts',
  'tsx',
  'jsx',
  'py',
  'java',
  'kt',
  'kts',
  'c',
  'h',
  'cpp',
  'hpp',
  'cs',
  'go',
  'rs',
  'rb',
  'php',
  'swift',
  'sh',
  'bash',
  'zsh',
  'bat',
  'cmd',
  'ps1',
  'sql',
  'html',
  'htm',
  'css',
  'scss',
  'less',
  'vue',
  'svelte',
  'gradle',
  'properties',
  'toml',
  'env',
};

String _extensionOf(String name) {
  final idx = name.lastIndexOf('.');
  if (idx <= 0 || idx == name.length - 1) return '';
  return name.substring(idx + 1).toLowerCase();
}

RemoteEntryKind remoteEntryKind(RemoteStorageEntry entry) {
  if (entry.isDirectory) return RemoteEntryKind.folder;
  final ext = _extensionOf(entry.name);
  if (_imageExts.contains(ext)) return RemoteEntryKind.image;
  if (_videoExts.contains(ext)) return RemoteEntryKind.video;
  if (_audioExts.contains(ext)) return RemoteEntryKind.audio;
  if (_textExts.contains(ext)) return RemoteEntryKind.text;
  return RemoteEntryKind.other;
}

/// 字节数格式化（列表副标题）。
String formatRemoteBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 单个路径段的**字节**上限。
///
/// 为什么按字节判而不是按字符：旧实现用 `String.length`（UTF-16 单元数）判 255，
/// "200 个汉字"在那里算 200 通过，但服务端收到的是 600 字节 → ext4/SMB/NFS 后端
/// 直接拒收，而客户端以为传得动（用户看到的是莫名其妙的失败）。
const int kMaxRemoteSegmentBytes = 255;

/// UTF-8 字节数（长度判定与提示文案共用）。
int remoteSegmentByteLength(String text) => utf8.encode(text).length;

/// Windows/SMB 保留设备名：DAV 后面挂 SMB 共享时会被拒收或截断。
const Set<String> kWindowsReservedNames = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// 归一化一个路径段：去首尾空白，再削掉结尾的点/空格。
///
/// 削而不是拒：`报告.` 在 Linux 后端合法、在 SMB 后端会被静默截断成 `报告`，
/// 统一削掉后两种后端落地的名字一致，且用户至少能传上去（拒收则完全没法传）。
String _normalizeSegment(String raw) {
  var text = raw.trim();
  while (text.isNotEmpty && (text.endsWith('.') || text.endsWith(' '))) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 取保留名判定用的主名（到第一个点为止，`NUL.txt` 也算保留名）。
String _reservedStem(String name) {
  final idx = name.indexOf('.');
  return (idx < 0 ? name : name.substring(0, idx)).toLowerCase();
}

/// 文件名不可用的原因；返回 null 表示可用。
///
/// 与 [sanitizeRemoteSegment] 必须同步改：两处判据不一致就会出现
/// "提示说合法、实际传不上去"或反过来的情况。
String? remoteSegmentRejectionReason(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '文件名为空';
  if (trimmed == '.' || trimmed == '..') return '文件名不能是「.」或「..」';
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    return '文件名不能包含路径分隔符';
  }
  if (trimmed.runes.any((r) => r < 0x20)) return '文件名包含控制字符';

  final text = _normalizeSegment(raw);
  if (text.isEmpty) return '文件名只由点/空格组成';

  final bytes = remoteSegmentByteLength(text);
  if (bytes > kMaxRemoteSegmentBytes) {
    return '文件名太长（$bytes 字节，服务端上限 $kMaxRemoteSegmentBytes 字节）';
  }
  if (kWindowsReservedNames.contains(_reservedStem(text))) {
    return '「${_reservedStem(text)}」是 Windows 保留名，服务端可能拒收';
  }
  return null;
}

/// 路径与文件名清洗：返回 null 表示不可用（判据见 [remoteSegmentRejectionReason]）。
///
/// **未做 Unicode 归一化（NFC/NFD）**：dart:core 没有归一化实现，引入
/// `unorm_dart` 这类依赖需要单独评估。群晖/macOS 后端以 NFD 存名时，同名文件
/// 可能显示成两份或按 NFC 名取回 404——这是已知缺口，不是遗漏（方案文档 O6）。
String? sanitizeRemoteSegment(String raw) {
  if (remoteSegmentRejectionReason(raw) != null) return null;
  final text = _normalizeSegment(raw);
  return text.isEmpty ? null : text;
}

/// 把相对路径按段做百分号编码（保留 `/`），供 WebDAV URL 拼接。
String encodeRemotePath(String relative) {
  return relative
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
}

/// 拼接远端路径（base 可为空表示根）。
String joinRemotePath(String base, String name) {
  final b = base.trim();
  return b.isEmpty ? name : '$b/$name';
}

/// 取父目录路径；根目录返回空串。
String parentRemotePath(String path) {
  final idx = path.lastIndexOf('/');
  if (idx <= 0) return '';
  return path.substring(0, idx);
}

/// 传输取消令牌（与 dio 解耦，便于单测）。
class TransferCancelToken {
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() => _canceled = true;

  /// 在流处理循环中调用：已取消则抛 [TransferCanceledException]。
  void throwIfCanceled() {
    if (_canceled) throw const TransferCanceledException();
  }
}

/// 传输被用户取消。
class TransferCanceledException implements Exception {
  const TransferCanceledException();

  @override
  String toString() => 'transfer canceled';
}

/// 错误归一：错误种类。
enum RemoteStorageError {
  unauthorized,
  forbidden,
  notFound,
  methodNotAllowed,
  conflict,
  insufficientStorage,
  certificate,
  timeout,
  network,
  canceled,
  http,
  unknown,
}

/// 面向用户的中文错误（§5.5 映射表的单一事实源）。
String remoteStorageErrorMessage(
  RemoteStorageError error, {
  int? statusCode,
  String? detail,
}) {
  switch (error) {
    case RemoteStorageError.unauthorized:
      return '用户名或密码不正确；坚果云请使用网页端生成的「应用密码」';
    case RemoteStorageError.forbidden:
      return '服务器拒绝访问（检查账号权限）';
    case RemoteStorageError.notFound:
      return '路径不存在（服务器地址可能缺少 WebDAV 前缀，如 /dav）';
    case RemoteStorageError.methodNotAllowed:
      return '服务器未启用 WebDAV 或不允许该方法';
    case RemoteStorageError.conflict:
      return '服务器返回冲突（目录可能已存在）';
    case RemoteStorageError.insufficientStorage:
      return '服务器空间不足';
    case RemoteStorageError.certificate:
      return '证书校验失败。如为自建/群晖自签证书，请在账户里开启「允许自签名证书」';
    case RemoteStorageError.timeout:
      return '连接超时，网络不可达（已记入调试日志）';
    case RemoteStorageError.network:
      return '网络错误，无法连接服务器';
    case RemoteStorageError.canceled:
      return '操作已取消';
    case RemoteStorageError.http:
      return '服务器返回 HTTP ${statusCode ?? '?'}';
    case RemoteStorageError.unknown:
      final extra = detail?.trim();
      return extra == null || extra.isEmpty ? '操作失败' : '操作失败：$extra';
  }
}

/// 由 HTTP 状态码构造归一化异常。
///
/// [retryAfter] 来自响应头 `Retry-After`（秒数或 HTTP-date），供传输队列决定
/// 退避时长——服务端说"等 30 秒"时就别 800ms 后硬撞第二次。
RemoteStorageException remoteStorageExceptionForStatus(
  int status, {
  Duration? retryAfter,
}) {
  final RemoteStorageError kind;
  switch (status) {
    case 401:
      kind = RemoteStorageError.unauthorized;
    case 403:
      kind = RemoteStorageError.forbidden;
    case 404:
      kind = RemoteStorageError.notFound;
    case 405:
      kind = RemoteStorageError.methodNotAllowed;
    case 409:
      kind = RemoteStorageError.conflict;
    case 507:
      kind = RemoteStorageError.insufficientStorage;
    default:
      kind = RemoteStorageError.http;
  }
  return RemoteStorageException(
    kind,
    remoteStorageErrorMessage(kind, statusCode: status),
    statusCode: status,
    retryAfter: retryAfter,
  );
}

/// 该错误是否值得重试。
///
/// 判据是"重试是否会得到不同结果"：网络类抖动与 429/5xx 值得再试；
/// 凭证、权限、路径、空间、协议不支持类错误重试多少次都一样，只会让用户
/// 多等两个退避周期。
///
/// `http` 且**没有状态码**时按可重试处理（保守：状态码缺失说明错误来自更底层，
/// 与网络抖动无法区分）。
bool isRetryableTransferError(Object error) {
  if (error is TransferCanceledException) return false;
  if (error is! RemoteStorageException) return true; // 未知异常：按网络类保守重试
  switch (error.kind) {
    case RemoteStorageError.timeout:
    case RemoteStorageError.network:
      return true;
    case RemoteStorageError.http:
      final status = error.statusCode;
      if (status == null) return true;
      return status == 408 ||
          status == 425 ||
          status == 429 ||
          status >= 500;
    case RemoteStorageError.unauthorized:
    case RemoteStorageError.forbidden:
    case RemoteStorageError.notFound:
    case RemoteStorageError.methodNotAllowed:
    case RemoteStorageError.conflict:
    case RemoteStorageError.insufficientStorage:
    case RemoteStorageError.certificate:
    case RemoteStorageError.canceled:
    case RemoteStorageError.unknown:
      return false;
  }
}

/// 第 [attempt] 次重试（1 起）前应等待多久：退避序列与 `Retry-After` 取较大值。
/// [attempt] 越界（≤0 或超过序列长度）时取序列两端，避免调用方传错就崩。
Duration retryDelayFor(int attempt, {Duration? retryAfter}) {
  var index = attempt - 1;
  if (index < 0) index = 0;
  if (index >= kTransferRetryDelays.length) {
    index = kTransferRetryDelays.length - 1;
  }
  final backoff = kTransferRetryDelays[index];
  if (retryAfter == null) return backoff;
  return retryAfter > backoff ? retryAfter : backoff;
}

/// 插件统一异常。
class RemoteStorageException implements Exception {
  const RemoteStorageException(
    this.kind,
    this.message, {
    this.statusCode,
    this.detail,
    this.retryAfter,
  });

  final RemoteStorageError kind;
  final String message;
  final int? statusCode;
  final String? detail;

  /// 服务端要求的等待时长（`Retry-After`）；无则 null。
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// 本地待上传文件（从 file_picker 的 PlatformFile 转换而来，域层不依赖插件包）。
class LocalUploadFile {
  const LocalUploadFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

/// 预览数据（图片/文本共用）。
class PreviewPayload {
  const PreviewPayload({
    required this.bytes,
    required this.truncated,
    required this.oversize,
    this.totalLength,
  });

  final List<int> bytes;
  final bool truncated;
  final bool oversize;
  final int? totalLength;

  String? get textOrNull =>
      oversize ? null : utf8.decode(bytes, allowMalformed: true);
}
