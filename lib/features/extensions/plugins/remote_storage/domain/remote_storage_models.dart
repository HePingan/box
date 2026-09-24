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

/// 图片预览的解码宽度倍数（279 C4）。
///
/// [kPreviewImageMaxBytes] 只挡"文件有多大"，挡不住"解码后有多大"：一张 20MB 的
/// JPEG 可以是 8000×6000，解码成 RGBA 就是 8000×6000×4 ≈ 192MB——比原文件大十几倍，
/// 小内存设备直接 OOM。按 2 倍屏幕宽度解码：视网膜屏上肉眼已看不出差别，
/// 内存却降到几 MB 量级。
const double kPreviewImageDecodeWidthFactor = 2;

/// 计算图片预览的目标解码宽度（像素）；null 表示不限制。
///
/// 设备信息拿不到时返回 null（不猜）：宁可按原尺寸解码，也不要用一个错误的宽度
/// 把用户想看清的图糊掉。
int? previewImageDecodeWidth({
  required double logicalWidth,
  required double devicePixelRatio,
}) {
  if (logicalWidth <= 0 || devicePixelRatio <= 0) return null;
  final pixels =
      (logicalWidth * devicePixelRatio * kPreviewImageDecodeWidthFactor).round();
  return pixels > 0 ? pixels : null;
}

/// 文本预览前缀上限（调大→更完整但载入变慢）。
const int kPreviewTextMaxBytes = 512 * 1024;

// ---------------------------------------------------------- 列表缩略图（281+）

/// 列表里给图片显示缩略图时，最多为此大小的图片才去取原图。
///
/// **为什么不能只取"文件开头"**：JPEG/PNG 都要求完整文件才能解码（渐进式 JPEG
/// 也至少要读到扫描结束），截断的字节解不出来。所以缩略图只能整张取回来再降采样
/// 解码——网络代价等于原图。于是给一个上限：超过这个大小就保持通用图标，
/// 不为一行 40dp 的缩略图去拉一张 10MB 的原图（那是用户流量，不是我们的）。
const int kThumbnailMaxBytes = 3 * 1024 * 1024;

/// 缩略图解码宽度（物理像素）。
///
/// 行内图标位约 40dp，3 倍屏 = 120px；留一点余量取 128。列表里同时可见十几行，
/// 每行都按原尺寸解码（4MB 的 JPEG 可能是 4000×3000 ≈ 48MB 位图）会直接把内存打满。
const int kThumbnailDecodeWidth = 128;

/// 内存里最多保留多少张缩略图（LRU；约 128px 的缩略图每张几十 KB）。
const int kThumbnailMemoryEntries = 120;

/// 缩略图磁盘缓存上限（字节）与最多文件数——滚动、返回目录时不重复下载。
const int kThumbnailDiskMaxBytes = 32 * 1024 * 1024;
const int kThumbnailDiskMaxFiles = 400;

/// 同时最多几张缩略图在取（别把带宽占满：缩略图是"顺便看看"，不该压过用户正在做的事）。
const int kThumbnailMaxConcurrent = 3;

/// EXIF 探测读多少字节：内嵌缩略图在文件开头的 EXIF 段里（通常前几 KB），
/// 256KB 是很宽裕的上界；读到这里还没找到就不再读。
const int kExifProbeBytes = 256 * 1024;

/// "探测过但没有内嵌缩略图"的内存记录上限；超了整表清空（宁可多探几次，
/// 也不要让这个集合无限增长）。
const int kExifProbeMissLimit = 500;

/// 递归下载的上限（284 D6）。
///
/// 为什么要上限：用户可能选中一个几千文件的目录（相册根目录就是这样）。没有上限
/// 的后果是——先把手机和服务器一起拖住，再在队列里堆几千个任务，取消都取消不过来。
/// 命中上限时**明确告知**"只下载了前 N 个"，而不是静默截断。
const int kRecursiveDownloadMaxFiles = 300;

/// 递归扫描的目录数上限（防止深/宽的目录树把一次列表变成几十次请求）。
const int kRecursiveDownloadMaxDirs = 200;

/// 递归收集的结果（284 D6）。
class RecursiveListing {
  const RecursiveListing({
    required this.files,
    required this.dirsScanned,
    required this.truncated,
    required this.unreadableDirs,
  });

  final List<RemoteStorageEntry> files;

  /// 走过的目录数（含起点）。
  final int dirsScanned;

  /// 命中上限被截断——界面**必须**把这件事告诉用户，不能静默少下。
  final bool truncated;

  /// 读取失败被跳过的子目录数（权限不足/被服务端拒绝等）。
  final int unreadableDirs;

  bool get isEmpty => files.isEmpty;
}

/// 递归下载时单个文件在本地要落的位置（284 D6）。
class RecursiveDownloadTarget {
  const RecursiveDownloadTarget({
    required this.subDir,
    required this.fileName,
  });

  /// 相对下载根目录的子目录（含选中目录名，保持结构），如 `相册/2021`。
  final String subDir;

  /// 文件名（最后一段）。
  final String fileName;
}

/// 算出递归下载的落点；[filePath] 不在 [rootPath] 之下时返回 null（调用方跳过）。
///
/// 纯函数：路径拼接是最容易错、又最难在真机上发现的地方（错一层就写进别的目录），
/// 所以放在 domain 层单测，而不是散在页面里。
///
/// 例子（选中 `相册`，rootPath=`相册`）：
///   `相册/a.jpg`        → subDir=`相册`、file=`a.jpg`
///   `相册/2021/b.jpg`   → subDir=`相册/2021`、file=`b.jpg`
///   `相册/2021/01/c.jpg`→ subDir=`相册/2021/01`、file=`c.jpg`
RecursiveDownloadTarget? recursiveDownloadTarget({
  required String rootPath,
  required String rootName,
  required String filePath,
}) {
  final root = rootPath.endsWith('/')
      ? rootPath.substring(0, rootPath.length - 1)
      : rootPath;
  final prefix = root.isEmpty ? '' : '$root/';
  final relative = prefix.isEmpty
      ? (filePath.startsWith('/') ? filePath.substring(1) : filePath)
      : (filePath.startsWith(prefix) ? filePath.substring(prefix.length) : null);
  if (relative == null || relative.isEmpty) return null;
  final cut = relative.lastIndexOf('/');
  final dirPart = cut < 0 ? '' : relative.substring(0, cut);
  final name = cut < 0 ? relative : relative.substring(cut + 1);
  if (name.isEmpty) return null;
  final safeName = sanitizeRemoteSegment(name) ?? name;
  final parent = sanitizeLocalSubPath(dirPart);
  return RecursiveDownloadTarget(
    subDir: parent.isEmpty ? rootName : '$rootName/$parent',
    fileName: safeName,
  );
}

/// 把远端相对目录拼成**本地**子目录：逐段清洗，清洗不掉的段用 `_` 顶替。
///
/// 为什么不用 `sanitizeRemoteSegment` 直接把整串过一遍：它面向的是单个路径段。
/// 这里宁可名字丑一点，也不能让 `..` 或空段把文件写到下载目录之外——本地落盘的
/// 越界比远端命名不规范严重得多。
String sanitizeLocalSubPath(String relative) {
  final parts = <String>[];
  for (final raw in relative.split('/')) {
    if (raw.isEmpty || raw == '.' || raw == '..') continue;
    parts.add(sanitizeRemoteSegment(raw) ?? '_');
  }
  return parts.join('/');
}

/// 播放倍速档位（284 P4）。
///
/// 0.5–2.0 五档足够覆盖"听课调慢"和"跳过废话"；再细的档位只增加选择成本。
const List<double> kPlaybackSpeeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

/// 倍速文案：`1×` / `1.5×` / `0.75×`（整数档不带小数点，菜单里对齐好看）。
String formatPlaybackSpeed(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$text×';
}

/// EXIF 内嵌缩略图的探测统计（284 P3）。
///
/// 为什么要它：283 D1 的"大图走 EXIF 内嵌缩略图"是没法只靠单测自证的改动——
/// 到底命中多少，只有把数字摆出来才能判断（也才知道要不要回去动 3MB 上限）。
/// 计数按**条目去重**、只统计本次运行：跨会话靠缩略图缓存，不重复探测，
/// 所以跨会话的数字会偏小，界面文案上写清了"本次运行"。
class ExifThumbnailStats {
  const ExifThumbnailStats({required this.hits, required this.misses});

  /// 探测成功、拿到内嵌缩略图的条目数。
  final int hits;

  /// 探测过、文件里没有内嵌缩略图的条目数。
  final int misses;

  int get probed => hits + misses;

  bool get isEmpty => probed == 0;

  /// 命中率文案（没探测过给 `—`，不编一个 0% 出来）。
  String get hitRateLabel =>
      probed == 0 ? '—' : '${(hits * 100 / probed).round()}%';
}

/// 列表要不要为这个条目**尝试**取缩略图（纯判定，便于单测）。
///
/// 两个来源：[isThumbnailableEntry]（整取，3MB 以内）与 [isExifThumbnailCandidate]
/// （大图/未知大小的 JPEG，走 EXIF 内嵌缩略图）。
///
/// 为什么要合成一个函数：页面若只按 `isThumbnailableEntry` 决定要不要显示缩略图槽位，
/// 那"大图走 EXIF"这条路在真机上永远走不到——service 层的单测会全绿，功能却不生效。
bool canHaveThumbnail(RemoteStorageEntry entry) =>
    isThumbnailableEntry(entry) || isExifThumbnailCandidate(entry);

/// 这个条目要不要走"EXIF 内嵌缩略图"这条路（纯判定，便于单测）。
///
/// 适用条件：
/// - 是图片，且扩展名是 JPEG（EXIF 只在 JPEG/TIFF/HEIC 这类容器里；PNG 没有内嵌缩略图）；
/// - **超过整取上限**（3MB 以内直接整取更可靠，能覆盖所有格式），**或大小未知**
///   （未知大小原本一律不取；EXIF 探测的代价有界，值得一试）。
bool isExifThumbnailCandidate(RemoteStorageEntry entry) {
  if (entry.isDirectory) return false;
  if (remoteEntryKind(entry) != RemoteEntryKind.image) return false;
  final name = entry.name.toLowerCase();
  if (!name.endsWith('.jpg') && !name.endsWith('.jpeg')) return false;
  final size = entry.size;
  if (size == null) return true;
  return size > kThumbnailMaxBytes;
}

/// 这个条目要不要取缩略图（纯判定，便于单测）。
///
/// 只对**图片**且大小已知且在 [kThumbnailMaxBytes] 以内的取；大小未知（0）时不取——
/// 宁可显示通用图标，也不要为了猜大小而多发一次请求。
bool isThumbnailableEntry(RemoteStorageEntry entry) {
  final size = entry.size;
  return !entry.isDirectory &&
      remoteEntryKind(entry) == RemoteEntryKind.image &&
      size != null &&
      size > 0 &&
      size <= kThumbnailMaxBytes;
}

/// 缩略图缓存键：账户 + 路径 + 大小 + 修改时间。
///
/// 带上大小与修改时间：远端文件被替换后（同名同路径）旧缩略图自然失效，
/// 不会把上一版的内容贴在新文件上。
String thumbnailCacheKey(String accountId, RemoteStorageEntry entry) =>
    '$accountId|${entry.path}|${entry.size}'
    '|${entry.modifiedAt?.toIso8601String() ?? ''}';

/// 播放中继空闲自动关闭：无请求且无在途取流超过该时长即回收（调大→保留更久；调小→端口更快回收）。
const Duration kRelayIdleTimeout = Duration(minutes: 30);

/// 传输队列并发数（调大→更快但弱 NAS 失败率升高）。
///
/// 279 C7：原来这里是 1 且**没人读**（死常量），队列实际上写死串行——一次只跑一个
/// 任务，选 10 个文件就是 10 次串行往返。批量下载/上传因此慢得没有必要。
///
/// 取 3 的理由：多文件场景的收益主要来自"把网络往返叠起来"，3 个已经能把带宽吃满；
/// 再往上对弱 NAS（群晖低端型号、老机械盘）是纯粹的失败率来源——同一时刻 8 个
/// 连接会把它的 IO 队列打散，每个都变慢且更容易超时。要更快应该调这个常量，
/// 而不是在别处偷偷并发。
const int kMaxConcurrentTransfers = 3;

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

/// 目录快照：上次列出的结果 + 时间（284 D7）。
///
/// 用途：冷启动/切目录时**先显示上次的内容**，同时后台刷新——直接把用户丢进
/// 一个转圈的空页面，是那种"每一处都让你多等一秒"的手感问题。
///
/// 关键约束：快照必须**看得见是旧的**（[isStale] + 界面横幅）。
/// 静默拿旧数据当最新，比转圈更糟：用户会以为远端删掉的东西还在。
class DirSnapshot {
  const DirSnapshot({required this.entries, required this.at});

  final List<RemoteStorageEntry> entries;
  final DateTime at;

  Duration age(DateTime now) => now.difference(at);

  /// 超过 [kDirSnapshotStaleAfter] 就算旧——界面据此显示"上次的内容"横幅。
  bool isStale(
    DateTime now, {
    Duration threshold = kDirSnapshotStaleAfter,
  }) =>
      age(now) >= threshold;
}

/// 快照超过这个时长就明说是旧的（哪怕正在刷新）。
const Duration kDirSnapshotStaleAfter = Duration(minutes: 5);

/// 单个目录快照最多存多少条：超了**不存快照**。
///
/// 为什么不截断到 200 条存下去：截断后的列表比"没有快照"更容易骗人
/// （用户会以为目录里只有这 200 个文件）。
const int kDirSnapshotMaxEntries = 200;

/// 最多记住多少个目录的快照，超了按时间丢最早的。
const int kDirSnapshotMaxDirs = 30;

/// 快照序列化（纯函数：坏数据一律当没有，不抛异常）。
String encodeDirSnapshot(DirSnapshot snapshot) => jsonEncode(<String, Object?>{
      'at': snapshot.at.toIso8601String(),
      'entries': snapshot.entries
          .map((e) => <String, Object?>{
                'n': e.name,
                'p': e.path,
                'd': e.isDirectory ? 1 : 0,
                if (e.size != null) 's': e.size,
                if (e.modifiedAt != null) 'm': e.modifiedAt!.toIso8601String(),
                if (e.etag != null) 'e': e.etag,
              })
          .toList(),
    });

/// 反序列化：[raw] 是坏数据/缺字段时返回 null（宁可没有快照，也不能让页面崩）。
DirSnapshot? decodeDirSnapshot(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final at = DateTime.tryParse('${decoded['at'] ?? ''}');
    final list = decoded['entries'];
    if (at == null || list is! List) return null;
    final entries = <RemoteStorageEntry>[];
    for (final item in list) {
      if (item is! Map) return null;
      final name = item['n'];
      final path = item['p'];
      if (name is! String || path is! String || name.isEmpty) return null;
      entries.add(
        RemoteStorageEntry(
          name: name,
          path: path,
          isDirectory: item['d'] == 1,
          size: item['s'] is int ? item['s'] as int : null,
          modifiedAt: item['m'] is String
              ? DateTime.tryParse(item['m'] as String)
              : null,
          etag: item['e'] is String ? item['e'] as String : null,
        ),
      );
    }
    return DirSnapshot(entries: entries, at: at);
  } catch (_) {
    return null;
  }
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

/// 本次上传是否超出服务端剩余配额（O5）。
///
/// 只在**服务端确实给了可用配额**、且总量超过它时返回 true。配额未知（服务器
/// 未实现 RFC 4331、或属性缺失）时一律不提示——宁可不提示，也不要拿猜出来的
/// 数字去吓用户。
bool uploadExceedsQuota(RemoteStorageQuota? quota, int totalBytes) {
  final available = quota?.availableBytes;
  if (available == null || available < 0) return false;
  return totalBytes > available;
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

/// 预组合字符 → "基字符 + 组合记号"的对照表（279 O6）。
///
/// dart:core 没有 NFC/NFD 归一化实现（要真做就得引 `unorm_dart` 这类表驱动依赖，
/// 见 [sanitizeRemoteSegment] 的说明）。但"两个名字是不是同一个名字的不同归一化
/// 形式"这个问题不需要完整的 Unicode 表：只需知道哪些字符是"基字符 + 一个组合
/// 记号"。这里按组合记号分组，每行是"基字符、预组合字符"交替的串——由 Unicode
/// NFD 数据生成，覆盖文件名里真实会出现的拉丁/希腊/西里尔字母。
///
/// 已知不含：双记号字符（ǘ = u + ̈ + ́ 等 24 个）、韩文音节、以及拉丁/希腊/西里尔
/// 之外的文字。这些情况下判定会返回"不是变体"（宁可漏判、不误判——误判会让
/// 上传把不同文件当同名跳过）。
const String _nfdGroups = r'''
\u0300: AÀEÈIÌNǸOÒUÙaàeèiìnǹoòuùЕЀИЍеѐиѝ
\u0301: AÁCĆEÉGǴIÍLĹNŃOÓRŔSŚUÚYÝZŹaácćeégǵiílĺnńoórŕsśuúyýzźÆǼØǾæǽøǿΑΆΕΈΗΉΙΊΟΌΥΎΩΏαάεέηήιίοόυύωώГЃКЌгѓкќ
\u0302: AÂCĈEÊGĜHĤIÎJĴOÔSŜUÛWŴYŶaâcĉeêgĝhĥiîjĵoôsŝuûwŵyŷ
\u0303: AÃIĨNÑOÕUŨaãiĩnñoõuũ
\u0304: AĀEĒIĪOŌUŪYȲaāeēiīoōuūyȳÆǢæǣ
\u0306: AĂEĔGĞIĬOŎUŬaăeĕgğiĭoŏuŭИЙУЎийуў
\u0307: AȦCĊEĖGĠIİOȮZŻaȧcċeėgġoȯzż
\u0308: AÄEËIÏOÖUÜYŸaäeëiïoöuüyÿΙΪΥΫιϊυϋІЇЕЁеёії
\u030a: AÅUŮaåuů
\u030b: OŐUŰoőuű
\u030c: AǍCČDĎEĚGǦHȞIǏKǨLĽNŇOǑRŘSŠTŤUǓZŽaǎcčdďeěgǧhȟiǐjǰkǩlľnňoǒrřsštťuǔzžƷǮʒǯ
\u030f: AȀEȄIȈOȌRȐUȔaȁeȅiȉoȍrȑuȕ
\u0311: AȂEȆIȊOȎRȒUȖaȃeȇiȋoȏrȓuȗ
\u031b: OƠUƯoơuư
\u0326: SȘTȚsștț
\u0327: CÇEȨGĢKĶLĻNŅRŖSŞTŢcçeȩgģkķlļnņrŗsştţ
\u0328: AĄEĘIĮOǪUŲaąeęiįoǫuų
''';

/// 预组合字符 → (基字符, 组合记号) 的查找表；由 [_nfdGroups] 懒解析一次。
final Map<int, (int, String)> _nfdTable = () {
  final out = <int, (int, String)>{};
  for (final line in _nfdGroups.trim().split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final mark = String.fromCharCode(
      int.parse(line.substring(0, idx).trim().substring(2), radix: 16),
    );
    final pairs = line.substring(idx + 1).replaceAll(' ', '');
    for (var i = 0; i + 1 < pairs.length; i += 2) {
      out[pairs.codeUnitAt(i + 1)] = (pairs.codeUnitAt(i), mark);
    }
  }
  return out;
}();

/// 把预组合字符拆成"基字符 + 组合记号"（NFD 形态）；表外字符原样保留。
///
/// 只用于**比较**，不用于出站路径改写：把用户的 NFC 名字改成 NFD 再传，在只认
/// NFC 的服务器上反而会取不到。
String toNfd(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final entry = _nfdTable[rune];
    if (entry == null) {
      out.writeCharCode(rune);
    } else {
      out
        ..writeCharCode(entry.$1)
        ..write(entry.$2);
    }
  }
  return out.toString();
}

/// [a] 与 [b] 是否只是同一个名字的不同归一化形式（279 O6）。
///
/// 判据：拆成 NFD 后相等（且原形态不同）。这个判据是**精确**的：
///  - `café`（NFC） vs `cafe` + U+0301（NFD）→ 变体 ✓
///  - `resume` vs `résumé` → 不是变体 ✓（真的两个不同名字，不能当同名跳过）
///  - `café` vs `cafè` → 不是变体 ✓
bool isNormalizationVariant(String a, String b) {
  if (a == b) return false;
  if (a.isEmpty || b.isEmpty) return false;
  return toNfd(a) == toNfd(b);
}

/// 在 [candidates] 里找 [name] 的归一化变体；没有则返回 null。
///
/// 上传前用它判"服务器上是不是已经有同一个名字的另一形态"——命中就该当冲突跳过，
/// 否则会在群晖/macOS（NFD 存储）上悄悄造出第二份看起来同名的文件。
String? normalizationVariantOf(String name, Iterable<String> candidates) {
  for (final candidate in candidates) {
    if (isNormalizationVariant(name, candidate)) return candidate;
  }
  return null;
}

/// 路径与文件名清洗：返回 null 表示不可用（判据见 [remoteSegmentRejectionReason]）。
///
/// **不做 NFC/NFD 归一化改写**：dart:core 没有归一化实现，引入 `unorm_dart`
/// 这类表驱动依赖需要单独评估。而且"改写"本身有风险——把用户的 NFC 名改成 NFD
/// 再传，在只认 NFC 的服务器上反而取不到。
///
/// 能确定判断的部分已经做了（见 [toNfd] / [isNormalizationVariant]）：上传前把
/// 服务器上"同一名字的另一归一化形态"按同名处理，避免在群晖/macOS（NFD 存储）
/// 上造出第二份看起来同名的文件。
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

/// 取路径最后一段（文件名/目录名）。
String remoteBasename(String path) {
  final idx = path.lastIndexOf('/');
  return idx < 0 ? path : path.substring(idx + 1);
}

/// SAF「另存到…」的大小上限（279 B2）。
///
/// file_picker 的 `saveFile` 接口本身就是 `required Uint8List bytes`——要先把整个
/// 文件读进内存。超大文件走这条路会直接 OOM，所以超过阈值的改走
/// 「下载到应用目录 + 分享/打开」这条流式路径。
const int kSafExportMaxBytes = 64 * 1024 * 1024;

/// 导出策略（B2）。
enum RemoteExportStrategy {
  /// 读进内存后调系统「另存为」（SAF / 文件选择器）。
  safSave,

  /// 只能靠「下载到应用目录 → 分享 / 打开」由用户另存。
  shareFromAppDir,
}

/// 该大小该走哪条导出路径。
///
/// **大小未知时选保守路径**：拿不准就别赌内存——用户还能用分享另存，
/// 而 OOM 是直接把 App 干掉。
RemoteExportStrategy exportStrategyFor(int? sizeBytes) {
  if (sizeBytes == null || sizeBytes <= 0) {
    return RemoteExportStrategy.shareFromAppDir;
  }
  return sizeBytes <= kSafExportMaxBytes
      ? RemoteExportStrategy.safSave
      : RemoteExportStrategy.shareFromAppDir;
}

/// 另存时的 MIME（SAF 用它决定默认过滤与缩略图；拿不准就给二进制流）。
String mimeTypeForFileName(String name) {
  final lower = name.toLowerCase();
  const table = <String, String>{
    '.mp4': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.flac': 'audio/flac',
    '.wav': 'audio/wav',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.pdf': 'application/pdf',
    '.epub': 'application/epub+zip',
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.json': 'application/json',
    '.zip': 'application/zip',
    '.apk': 'application/vnd.android.package-archive',
  };
  for (final entry in table.entries) {
    if (lower.endsWith(entry.key)) return entry.value;
  }
  return 'application/octet-stream';
}

/// `Content-Range` 的解析结果（RFC 7233：`bytes 100-199/200`）。
///
/// [total] 为 null 表示服务端给的是 `bytes 100-199/*`（无法从这一段推全长）。
class RemoteContentRange {
  const RemoteContentRange({
    required this.start,
    required this.end,
    this.total,
  });

  final int start;
  final int end;
  final int? total;

  /// 这一段有多少字节。
  int get length => end - start + 1;
}

/// 解析 `Content-Range`。无法解析（含 `bytes */200` 这种"范围不可满足"）时返回 null
/// ——调用方据此退化为"从头下载"，而不是猜一个偏移。
RemoteContentRange? parseContentRange(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (!text.toLowerCase().startsWith('bytes')) return null;
  final value = text.substring(5).trim();
  final slash = value.indexOf('/');
  if (slash <= 0) return null;
  final rangePart = value.substring(0, slash).trim();
  final totalPart = value.substring(slash + 1).trim();
  final dash = rangePart.indexOf('-');
  if (dash <= 0) return null; // `*` 或空
  final start = int.tryParse(rangePart.substring(0, dash).trim());
  final end = int.tryParse(rangePart.substring(dash + 1).trim());
  if (start == null || end == null || end < start) return null;
  final total = totalPart == '*' ? null : int.tryParse(totalPart);
  return RemoteContentRange(start: start, end: end, total: total);
}

/// 断点续传的归属元数据（与 `.part` 同放一个 `.part.meta`）。
///
/// 为什么需要它：`.part` 只按文件名复用，而同一个文件名完全可能来自**另一个账户或
/// 另一个远端路径**（两个网盘里都有 `notes.zip` 很常见）。不加归属校验就续传，会把
/// 两份不同文件的字节拼成一个"能打开但内容是坏的"包——比重新下载危险得多。
class PartialDownload {
  const PartialDownload({required this.accountId, required this.remotePath});

  final String accountId;
  final String remotePath;

  /// 这份断点是否属于当前这次下载。
  bool matches({required String accountId, required String remotePath}) =>
      this.accountId == accountId && this.remotePath == remotePath;

  String toJsonString() =>
      jsonEncode({'accountId': accountId, 'remotePath': remotePath});

  /// 解析失败（文件被手改、写了一半）一律返回 null → 调用方丢弃断点重下。
  static PartialDownload? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final accountId = data['accountId']?.toString() ?? '';
      final remotePath = data['remotePath']?.toString() ?? '';
      if (accountId.isEmpty) return null;
      return PartialDownload(accountId: accountId, remotePath: remotePath);
    } catch (_) {
      return null;
    }
  }
}

/// 本地筛选（279 C3）：在已取回的目录内容里按名字过滤，**不发任何请求**。
///
/// 规则：
///  - 大小写不敏感的子串匹配（`REPORT` 能命中 `report.pdf`）；
///  - 空格分隔多个关键词是"与"关系（`报告 2024` 要求两个词都出现），方便在
///    上千项目录里逐步收窄；
///  - 纯空白视为未筛选，原样返回（连列表都不用重建）。
///
/// 为什么不走服务端搜索：WebDAV 没有标准的目录内搜索，各家实现的 `SEARCH`
/// 方法支持度参差；而"过滤已取回的这一屏目录"是零请求、零延迟的，正好解决
/// "大目录里肉眼找文件"这个实际痛点。
List<RemoteStorageEntry> filterRemoteEntries(
  List<RemoteStorageEntry> entries,
  String query,
) {
  final tokens = <String>[
    for (final token in query.trim().toLowerCase().split(RegExp(r'\s+')))
      if (token.isNotEmpty) token,
  ];
  if (tokens.isEmpty) return entries;
  return <RemoteStorageEntry>[
    for (final entry in entries)
      if (_nameMatchesAll(entry.name.toLowerCase(), tokens)) entry,
  ];
}

bool _nameMatchesAll(String lowerName, List<String> tokens) {
  for (final token in tokens) {
    if (!lowerName.contains(token)) return false;
  }
  return true;
}

/// 批量操作结果：逐项失败不中断整批，最后统一汇报。
///
/// 为什么不让批量操作"一错全停"：多选删除/移动时，用户要的是"能做的先做掉"，
/// 单项失败（权限、已不存在）不该把其余 9 项一起卡住。
class RemoteBatchResult {
  const RemoteBatchResult({required this.succeeded, required this.failures});

  const RemoteBatchResult.empty()
      : succeeded = 0,
        failures = const <String>[];

  /// 成功条数。
  final int succeeded;

  /// 失败明细（形如 `文件名：原因`），顺序与入参一致。
  final List<String> failures;

  bool get hasFailures => failures.isNotEmpty;

  /// 给 SnackBar 用的一句话（只陈述事实，措辞由 UI 决定）。
  String get summary =>
      failures.isEmpty ? '已完成 $succeeded 项' : '成功 $succeeded 项，失败 ${failures.length} 项';
}

/// 传输取消令牌（与 dio 解耦，便于单测）。
class TransferCancelToken {
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() => _canceled = true;

  /// 复位标记（283 D4：重试一个失败任务时用）。
  ///
  /// token 是一次性的——被取消过一次就永远是取消态，重试会立刻被判成取消。
  /// 复位只用于"用户明确要求重试"这条路径。
  void reset() => _canceled = false;

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
    case 412:
      // MOVE/COPY 带 `Overwrite: F` 且目标已存在（RFC 4918 §9.9.4）。
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
  final override = error.retryable;
  if (override != null) return override; // 显式指定优先（见字段注释）
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
    this.retryable,
  });

  final RemoteStorageError kind;
  final String message;
  final int? statusCode;
  final String? detail;

  /// 服务端要求的等待时长（`Retry-After`）；无则 null。
  final Duration? retryAfter;

  /// 显式指定"这个错误重试一次就有意义"，覆盖 [isRetryableTransferError] 按
  /// [kind] 的默认判断（C5：服务器要 Digest 时首次请求必被 401 拒绝，但挑战已
  /// 记住，重试就能成功——按 kind=credentials 判"不重试"反而让用户白点一次）。
  final bool? retryable;

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
