/// GitHub 加速下载链接转换。
///
/// 纯逻辑、零 Flutter 依赖，方便单测。
///
/// 解决的实际问题：从 GitHub Release 页面右键复制到的下载地址是
/// `release-assets.githubusercontent.com` 的**签名长链** —— 带 `sig`/`jwt`/`se`
/// 参数，几十分钟就过期。拿这种链接去喂加速镜像没有意义：镜像回源时签名已失效。
///
/// 但签名链里有两条有用信息：
///   - 路径第三段是仓库的**数字 ID**（如 `1333629201`）；
///   - query 的 `rscd` / `response-content-disposition` 里带原始**文件名**。
///
/// 拿数字 ID 查一次 `api.github.com/repositories/<id>` 就能得到 `owner/repo`，
/// 再拼成稳定形态：
///
/// ```
/// https://github.com/<owner>/<repo>/releases/latest/download/<fileName>
/// ```
///
/// 最后前缀式套上镜像即可加速：`https://gh-proxy.com/<稳定链接>`。
library;

enum GithubLinkKind {
  /// release-assets 签名长链：需要查 API 才能重建。
  signedAsset,

  /// github.com/.../releases/{latest/,}download/... ：可直接加速。
  releaseDownload,

  /// raw.githubusercontent.com 或 github.com/.../raw/... 文件。
  rawFile,

  /// codeload 归档（zip/tar）。
  archive,

  /// 已经带镜像前缀，不能二次包装。
  alreadyAccelerated,

  /// 与 GitHub 下载无关。
  unsupported,
}

/// 可选加速镜像。
class GithubMirror {
  const GithubMirror(this.label, this.url);

  final String label;
  final String url;
}

class GithubAccelLink {
  const GithubAccelLink._({
    required this.kind,
    required this.originalInput,
    required this.mirror,
    this.owner = '',
    this.repo = '',
    this.repositoryId = '',
    this.fileName = '',
    this.tag = '',
    this.expired = false,
    this.stableUrl,
  });

  /// 内置镜像。gh-proxy.com 是用户实测可用的那个，放第一位作默认。
  static const List<GithubMirror> mirrors = [
    GithubMirror('gh-proxy.com', 'https://gh-proxy.com'),
    GithubMirror('ghfast.top', 'https://ghfast.top'),
    GithubMirror('ghproxy.net', 'https://ghproxy.net'),
    GithubMirror('hk.gh-proxy.com', 'https://hk.gh-proxy.com'),
  ];

  static const String defaultMirror = 'https://gh-proxy.com';

  /// 已知镜像域名。用于识别「已加速」的输入，避免套两层前缀导致 404。
  static const List<String> _knownMirrorHosts = [
    'gh-proxy.com',
    'hk.gh-proxy.com',
    'ghfast.top',
    'ghproxy.net',
    'ghproxy.com',
    'ghp.ci',
    'gh.ddlc.top',
    'mirror.ghproxy.com',
  ];

  final GithubLinkKind kind;
  final String originalInput;
  final String mirror;
  final String owner;
  final String repo;

  /// 签名链路径里的仓库数字 ID。非签名链为空。
  final String repositoryId;

  final String fileName;
  final String tag;

  /// 签名链的 `se`（过期时刻）已经过去。
  final bool expired;

  /// 可直接下载的稳定 GitHub 链接。
  final String? stableUrl;

  bool get canBuildDirectly => stableUrl != null && stableUrl!.isNotEmpty;

  /// 需要联网查 `owner/repo` 才能继续。
  bool get needsRepoLookup =>
      kind == GithubLinkKind.signedAsset && !canBuildDirectly;

  /// 最终加速地址。
  String? get accelUrl {
    if (kind == GithubLinkKind.alreadyAccelerated) return originalInput;
    final stable = stableUrl;
    if (stable == null || stable.isEmpty) return null;
    return '${_trimSlash(mirror)}/$stable';
  }

  /// 查询 `owner/repo` 的接口地址（保留单通道字段，向后兼容）。
  String? get repoLookupUrl {
    final urls = repoLookupUrls;
    return urls.isEmpty ? null : urls.first;
  }

  /// 查 `owner/repo` 的候选通道，按实测可靠度排序。
  ///
  /// 实测结论（对线上逐个 curl）：
  ///   - 直连 `api.github.com` → 200，最稳，优先。
  ///   - `gh-proxy.com` 代理 → 可用，但它用共享 GitHub 账号回源，
  ///     账号限额被打满时回 403；同一地址连打 6 次得到 403,403,403,200,403,403，
  ///     属于**间歇性**限流，所以值得重试而不是判死。
  ///   - `ghfast.top` → 403 "Invalid input."（不代理 api 子域）
  ///   - `hk.gh-proxy.com` → 302 到 .org 域，拿不到 JSON
  ///   - `ghproxy.net` → TLS 证书已过期
  /// 因此只保留直连 + gh-proxy 两条，其余不浪费用户时间。
  List<String> get repoLookupUrls {
    if (repositoryId.isEmpty) return const [];
    final api = 'https://api.github.com/repositories/$repositoryId';
    final channels = <String>[
      api, // 直连优先
      'https://gh-proxy.com/$api',
    ];
    // 用户选的镜像若不在清单里，作为最后兜底也试一把。
    final custom = '${_trimSlash(mirror)}/$api';
    if (!channels.contains(custom) && !_lookupDeadHosts.any(custom.contains)) {
      channels.add(custom);
    }
    return List.unmodifiable(channels);
  }

  /// 实测无法代理 api.github.com 的域名，不放进查询通道。
  static const List<String> _lookupDeadHosts = [
    'ghfast.top',
    'hk.gh-proxy.com',
    'ghproxy.net',
  ];

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// 解析任意用户输入。永不抛异常 —— 无法识别就返回 [GithubLinkKind.unsupported]。
  static GithubAccelLink parse(String input, {String mirror = defaultMirror}) {
    final cleaned = _clean(input);
    if (cleaned.isEmpty) {
      return GithubAccelLink._(
        kind: GithubLinkKind.unsupported,
        originalInput: cleaned,
        mirror: mirror,
      );
    }

    // 已加速：镜像域名 + 后面还套着一个 http(s) 链接。
    final mirrorHit = _detectMirror(cleaned);
    if (mirrorHit) {
      return GithubAccelLink._(
        kind: GithubLinkKind.alreadyAccelerated,
        originalInput: cleaned,
        mirror: mirror,
      );
    }

    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty) {
      return GithubAccelLink._(
        kind: GithubLinkKind.unsupported,
        originalInput: cleaned,
        mirror: mirror,
      );
    }

    final host = uri.host.toLowerCase();
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // 1. 签名长链
    if (host == 'release-assets.githubusercontent.com' ||
        host == 'objects.githubusercontent.com') {
      return _parseSignedAsset(cleaned, uri, segs, mirror);
    }

    // 2. raw 文件
    if (host == 'raw.githubusercontent.com') {
      return GithubAccelLink._(
        kind: GithubLinkKind.rawFile,
        originalInput: cleaned,
        mirror: mirror,
        owner: segs.isNotEmpty ? segs[0] : '',
        repo: segs.length > 1 ? segs[1] : '',
        fileName: segs.isNotEmpty ? segs.last : '',
        stableUrl: cleaned,
      );
    }

    // 3. codeload 归档
    if (host == 'codeload.github.com') {
      return GithubAccelLink._(
        kind: GithubLinkKind.archive,
        originalInput: cleaned,
        mirror: mirror,
        owner: segs.isNotEmpty ? segs[0] : '',
        repo: segs.length > 1 ? segs[1] : '',
        stableUrl: cleaned,
      );
    }

    // 4. github.com 各类可下载路径
    if (host == 'github.com' || host == 'www.github.com') {
      return _parseGithubCom(cleaned, segs, mirror);
    }

    return GithubAccelLink._(
      kind: GithubLinkKind.unsupported,
      originalInput: cleaned,
      mirror: mirror,
    );
  }

  static GithubAccelLink _parseSignedAsset(
    String cleaned,
    Uri uri,
    List<String> segs,
    String mirror,
  ) {
    // 路径形如 /github-production-release-asset/<repoId>/<uuid>
    var repoId = '';
    for (final s in segs) {
      if (RegExp(r'^\d{4,}$').hasMatch(s)) {
        repoId = s;
        break;
      }
    }

    return GithubAccelLink._(
      kind: GithubLinkKind.signedAsset,
      originalInput: cleaned,
      mirror: mirror,
      repositoryId: repoId,
      fileName: _fileNameFromQuery(uri),
      expired: _isExpired(uri),
    );
  }

  static GithubAccelLink _parseGithubCom(
    String cleaned,
    List<String> segs,
    String mirror,
  ) {
    final owner = segs.isNotEmpty ? segs[0] : '';
    final repo = segs.length > 1 ? segs[1] : '';

    // /owner/repo/releases/latest/download/<file>
    // /owner/repo/releases/download/<tag>/<file>
    final relIdx = segs.indexOf('releases');
    if (relIdx == 2 && segs.length > relIdx + 1) {
      final rest = segs.sublist(relIdx + 1);
      if (rest.first == 'latest' && rest.length >= 3 && rest[1] == 'download') {
        return GithubAccelLink._(
          kind: GithubLinkKind.releaseDownload,
          originalInput: cleaned,
          mirror: mirror,
          owner: owner,
          repo: repo,
          tag: 'latest',
          fileName: rest.last,
          stableUrl: cleaned,
        );
      }
      if (rest.first == 'download' && rest.length >= 3) {
        return GithubAccelLink._(
          kind: GithubLinkKind.releaseDownload,
          originalInput: cleaned,
          mirror: mirror,
          owner: owner,
          repo: repo,
          tag: rest[1],
          fileName: rest.last,
          stableUrl: cleaned,
        );
      }
    }

    // /owner/repo/raw/<ref>/<path>
    // /owner/repo/archive/....zip
    if (segs.length > 2 && (segs[2] == 'raw' || segs[2] == 'archive')) {
      return GithubAccelLink._(
        kind: segs[2] == 'raw'
            ? GithubLinkKind.rawFile
            : GithubLinkKind.archive,
        originalInput: cleaned,
        mirror: mirror,
        owner: owner,
        repo: repo,
        fileName: segs.last,
        stableUrl: cleaned,
      );
    }

    // 其余 github.com 页面（仓库首页、issues 等）不是可下载文件。
    return GithubAccelLink._(
      kind: GithubLinkKind.unsupported,
      originalInput: cleaned,
      mirror: mirror,
      owner: owner,
      repo: repo,
    );
  }

  /// 拿查到的 `owner/repo` 重建稳定链接。
  ///
  /// 用 `releases/latest/download/<file>` 而不是带 tag 的形态：签名链里没有 tag
  /// 信息，而 latest 对「下最新版」这个诉求也更实用。
  GithubAccelLink rebuildWithRepo(String fullName) {
    final parts = fullName.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != 2 || fileName.isEmpty) {
      return this;
    }
    // 防注入：owner/repo 只允许 GitHub 合法字符。
    final ok = RegExp(r'^[A-Za-z0-9._-]+$');
    if (!ok.hasMatch(parts[0]) || !ok.hasMatch(parts[1])) return this;

    final stable =
        'https://github.com/${parts[0]}/${parts[1]}/releases/latest/download/'
        '${Uri.encodeComponent(fileName)}';

    return GithubAccelLink._(
      kind: GithubLinkKind.releaseDownload,
      originalInput: originalInput,
      mirror: mirror,
      owner: parts[0],
      repo: parts[1],
      repositoryId: repositoryId,
      fileName: fileName,
      tag: 'latest',
      expired: expired,
      stableUrl: stable,
    );
  }

  /// 换镜像重算，不重新解析。
  GithubAccelLink withMirror(String newMirror) {
    return GithubAccelLink._(
      kind: kind,
      originalInput: originalInput,
      mirror: newMirror,
      owner: owner,
      repo: repo,
      repositoryId: repositoryId,
      fileName: fileName,
      tag: tag,
      expired: expired,
      stableUrl: stableUrl,
    );
  }

  static String _clean(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    // 聊天软件常把链接包在尖括号里
    s = s.replaceAll(RegExp(r'^<+|>+$'), '').trim();
    if (s.isEmpty) return '';
    // 复制时常丢协议头
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      // 只对看起来像域名的输入补协议，避免把中文乱串也变成 URL
      if (!RegExp(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}/').hasMatch(s)) return s;
      s = 'https://$s';
    }
    return s;
  }

  static bool _detectMirror(String cleaned) {
    final uri = Uri.tryParse(cleaned);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (!_knownMirrorHosts.contains(host)) return false;
    // 镜像域名后面必须还套着一个 http 链接，才算「已加速」
    return cleaned.indexOf('http', 8) > 0;
  }

  /// 从 `rscd` 或 `response-content-disposition` 里抠出 filename。
  ///
  /// 两个参数名都要认：前者是 Azure Blob 的短名，后者是标准名，
  /// GitHub 的签名链两个都会带。值形如
  /// `attachment; filename=xxx.apk`（空格可能被编码成 `+` 或 `%20`）。
  static String _fileNameFromQuery(Uri uri) {
    for (final key in const [
      'rscd',
      'response-content-disposition',
      'filename',
    ]) {
      final raw = uri.queryParameters[key];
      if (raw == null || raw.isEmpty) continue;
      if (key == 'filename') return raw.trim();
      final m = RegExp(
        r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
        caseSensitive: false,
      ).firstMatch(raw);
      if (m != null) {
        var name = m.group(1)!.trim();
        // Uri.queryParameters 已解码一次，但 filename 里的 + 可能残留
        name = name.replaceAll('+', ' ').trim();
        try {
          name = Uri.decodeComponent(name);
        } catch (_) {
          // 已是明文，保持原样。
        }
        if (name.isNotEmpty) return name;
      }
    }
    return '';
  }

  /// 判断签名是否过期。`se` 是 Azure SAS 的到期时刻（ISO8601）。
  static bool _isExpired(Uri uri) {
    final se = uri.queryParameters['se'];
    if (se == null || se.isEmpty) return false;
    final t = DateTime.tryParse(se);
    if (t == null) return false;
    return t.isBefore(DateTime.now().toUtc());
  }
}
