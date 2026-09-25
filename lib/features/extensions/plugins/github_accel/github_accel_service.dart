import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'github_accel_link.dart';

/// 抓取文本的最小抽象。注入以便单测不联网。
typedef GithubAccelFetch = Future<String> Function(String url);

/// 解析结果。
class GithubAccelResolution {
  const GithubAccelResolution({
    required this.link,
    required this.ok,
    this.message = '',
  });

  final GithubAccelLink link;
  final bool ok;
  final String message;

  String? get accelUrl => link.accelUrl;
  String? get stableUrl => link.stableUrl;
}

/// releases 列表里查到的信息：仓库名 + 该文件所属的 tag（没找到同名附件时为 null）。
class _ReleaseLookup {
  const _ReleaseLookup({required this.fullName, this.tag});

  final String fullName;
  final String? tag;
}

/// 把任意 GitHub 链接解析成可加速下载的地址。
///
/// 只有签名长链需要联网（查 `owner/repo`），其余形态纯本地转换。
class GithubAccelService {
  GithubAccelService({
    GithubAccelFetch? fetch,
    this.mirror = GithubAccelLink.defaultMirror,
    this.attemptsPerChannel = 3,
    this.retryDelay = const Duration(milliseconds: 400),
  }) : _fetch = fetch;

  final GithubAccelFetch? _fetch;
  final String mirror;

  /// 每个查询通道的尝试次数。镜像限流是间歇性的，重试才有意义。
  /// 调大 → 成功率高、失败时等更久；调小 → 反之。
  final int attemptsPerChannel;

  /// 两次尝试之间的间隔。测试里设 0 以免拖慢。
  final Duration retryDelay;

  Future<GithubAccelResolution> resolve(String input) async {
    final link = GithubAccelLink.parse(input, mirror: mirror);

    switch (link.kind) {
      case GithubLinkKind.unsupported:
        return GithubAccelResolution(
          link: link,
          ok: false,
          message: '无法识别为 GitHub 下载链接。支持 releases 附件、raw 文件、归档包。',
        );

      case GithubLinkKind.alreadyAccelerated:
        return GithubAccelResolution(
          link: link,
          ok: true,
          message: '这个链接已经是加速地址，直接用即可（重复套前缀会 404）。',
        );

      case GithubLinkKind.releaseDownload:
      case GithubLinkKind.rawFile:
      case GithubLinkKind.archive:
        return GithubAccelResolution(link: link, ok: true);

      case GithubLinkKind.signedAsset:
        return _resolveSigned(link);
    }
  }

  Future<GithubAccelResolution> _resolveSigned(GithubAccelLink link) async {
    // 先试"一次拿到 owner/repo + 文件所属 tag"的 releases 列表通道：同样一次请求，
    // 但结果比只查仓库名更有用（见 [_resolveViaReleases]）。查不到再退回老路。
    final byTag = await _resolveViaReleases(link);
    if (byTag != null) return byTag;
    return _resolveViaRepoLookup(link);
  }

  /// 按仓库 id 拉 releases 列表：一次请求同时得到 `owner/repo`（来自
  /// `repository_url`）与"这个文件名出现在哪个 tag 里"。
  ///
  /// 返回 null 表示"这条路走不通"（所有通道都失败 / 不是 JSON / 连仓库名都没拿到），
  /// 调用方会退回 [_resolveViaRepoLookup]——保留老路径，不让新增的这次请求变成
  /// 新的单点失败。
  Future<GithubAccelResolution?> _resolveViaReleases(GithubAccelLink link) async {
    final linkForLookup = link;
    final fetch = _fetch;
    if (linkForLookup.repositoryId.isEmpty || fetch == null) return null;

    // 只看最近 30 个版本：一次请求的返回体已经 ~150KB，翻到 100 个是给移动流量
    // 找麻烦；更老的附件查不到时会退回 latest 地址，并在文案里说清风险。
    final api = 'https://api.github.com/repositories/'
        '${linkForLookup.repositoryId}/releases?per_page=30';
    final channels = _lookupChannels(api, linkForLookup.mirror);

    Object? lastError;
    for (final url in channels) {
      for (var attempt = 0; attempt < attemptsPerChannel; attempt++) {
        try {
          final body = await fetch(url);
          final parsed = _parseReleases(body, linkForLookup.fileName);
          if (parsed == null) {
            lastError = '返回内容不是 releases 列表';
            continue;
          }
          final rebuilt =
              linkForLookup.rebuildWithRepo(parsed.fullName, tag: parsed.tag);
          if (!rebuilt.canBuildDirectly) {
            return GithubAccelResolution(
              link: linkForLookup,
              ok: false,
              message: '仓库信息「${parsed.fullName}」不合法，无法拼出下载地址。',
            );
          }
          final expiredNote =
              linkForLookup.expired ? '（原链接签名已过期）' : '';
          return GithubAccelResolution(
            link: rebuilt,
            ok: true,
            message: parsed.tag == null
                ? '已识别为 ${parsed.fullName}$expiredNote，转换为最新版稳定地址。\n'
                    '注：若该文件不属于最新版，这个地址会 404 —— 换 tag 固定地址更稳。'
                : '已识别为 ${parsed.fullName}$expiredNote，定位到该文件所在版本 '
                    '${parsed.tag}，已转换为 tag 固定地址。',
          );
        } catch (e) {
          lastError = e;
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay);
          }
        }
      }
    }
    debugPrint('[GithubAccel] releases 通道均失败，退回仓库名查询: $lastError');
    return null;
  }

  /// 老路径：只查 `owner/repo`，拼 latest 地址（releases 通道不可用时的兜底）。
  Future<GithubAccelResolution> _resolveViaRepoLookup(
    GithubAccelLink link,
  ) async {
    if (link.fileName.isEmpty) {
      return GithubAccelResolution(
        link: link,
        ok: false,
        message: '这是带签名的临时地址，且未能从中读出文件名，无法重建稳定链接。\n'
            '请到 Release 页面复制形如 /releases/latest/download/xxx 的地址。',
      );
    }

    final channels = link.repoLookupUrls;
    final fetch = _fetch;
    if (channels.isEmpty || fetch == null) {
      return GithubAccelResolution(
        link: link,
        ok: false,
        message: '这是带签名的临时地址，需要联网查询仓库信息才能转换。',
      );
    }

    // 逐通道 + 每通道重试。
    //
    // gh-proxy 用共享 GitHub 账号回源，限额打满时回 403，但是**间歇性**的
    // （实测同一地址连打 6 次：403,403,403,200,403,403），所以只试一次会
    // 无谓失败。attemptsPerChannel 调大能提高成功率，代价是失败时等更久。
    Object? lastError;
    for (final url in channels) {
      for (var attempt = 0; attempt < attemptsPerChannel; attempt++) {
        try {
          final body = await fetch(url);
          final fullName = _fullNameFrom(body);
          if (fullName.isEmpty) {
            // 限流响应也可能是 HTTP 200 + {"message":"API rate limit..."}，
            // 这种没有 full_name，按失败处理继续换通道。
            lastError = '返回内容里没有 full_name';
            continue;
          }

          final rebuilt = link.rebuildWithRepo(fullName);
          if (!rebuilt.canBuildDirectly) {
            return GithubAccelResolution(
              link: link,
              ok: false,
              message: '仓库信息「$fullName」不合法，无法拼出下载地址。',
            );
          }

          return GithubAccelResolution(
            link: rebuilt,
            ok: true,
            message: link.expired
                ? '原链接的签名已过期，已重建为 $fullName 的最新版稳定地址。'
                : '已识别为 $fullName，转换为最新版稳定地址。',
          );
        } catch (e) {
          lastError = e;
          if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
        }
      }
    }

    debugPrint('[GithubAccel] 所有查询通道均失败: $lastError');
    return GithubAccelResolution(
      link: link,
      ok: false,
      message: _lookupFailureMessage(link, channels.length),
    );
  }

  /// 查询全败时的人话提示。不把 Dio 的英文堆栈丢给用户。
  static String _lookupFailureMessage(GithubAccelLink link, int channelCount) {
    final buf = StringBuffer()
      ..writeln('查不到这个仓库的名字，$channelCount 个通道都失败了。')
      ..writeln()
      ..writeln('这条是浏览器里复制的**签名临时链接**，本身不含仓库名，')
      ..writeln('必须反查 GitHub API 才能还原。而加速镜像共用一个 GitHub')
      ..writeln('账号回源，该账号的 API 限额被打满时就会回 403 限流。')
      ..writeln()
      ..writeln('过一会儿再点一次转换通常就好。想立刻解决，改用稳定链接：');
    if (link.fileName.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('https://github.com/<作者>/<仓库>/releases/latest/download/'
            '${link.fileName}')
        ..writeln()
        ..writeln('把 <作者>/<仓库> 换成真实值即可（文件名已从原链接读出）。');
    } else {
      buf.writeln('到 Release 页面复制形如 /releases/latest/download/xxx 的地址。');
    }
    return buf.toString().trimRight();
  }

  /// 查询通道：直连优先，gh-proxy 次之，用户选的镜像兜底（与仓库名查询同策略）。
  static List<String> _lookupChannels(String api, String mirror) {
    final trimmed =
        mirror.endsWith('/') ? mirror.substring(0, mirror.length - 1) : mirror;
    final channels = <String>[api, 'https://gh-proxy.com/$api'];
    final custom = '$trimmed/$api';
    if (!channels.contains(custom) &&
        !GithubAccelLink.deadLookupHosts.any(custom.contains)) {
      channels.add(custom);
    }
    return channels;
  }

  /// 解析 releases 列表，挑出"含这个文件名"的那个版本。
  ///
  /// 拿不到 `owner/repo`（连 `repository_url` 都没有）时返回 null，让调用方兜底；
  /// 拿得到但没找到同名附件时返回 [tag] 为 null 的结果（地址退回 latest）。
  static _ReleaseLookup? _parseReleases(String body, String fileName) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // 镜像可能回 HTML 错误页 —— 与仓库名查询一样，按"这条路不通"处理。
      return null;
    }
    if (decoded is! List) return null;

    String fullName = '';
    for (final item in decoded) {
      if (item is! Map) continue;
      // releases 列表项里**没有** `repository_url` 字段（实测：它是 release 详情
      // 接口才有的）；能用来定位仓库的是 `url`（形如 /repos/o/r/releases/123）。
      // 两个都试：谁先出现用谁，避免换接口时静默退化成"只认 latest"。
      final fromUrl = _fullNameFromRepositoryUrl(
        '${item['repository_url'] ?? item['url']}',
      );
      if (fullName.isEmpty && fromUrl.isNotEmpty) fullName = fromUrl;

      if (fileName.isEmpty) continue;
      final tag = item['tag_name'];
      final assets = item['assets'];
      if (tag is! String || assets is! List) continue;
      for (final asset in assets) {
        if (asset is Map && asset['name'] == fileName) {
          final full = fullName.isNotEmpty ? fullName : fromUrl;
          if (full.isEmpty) return null;
          return _ReleaseLookup(fullName: full, tag: tag);
        }
      }
    }
    if (fullName.isEmpty) return null;
    return _ReleaseLookup(fullName: fullName);
  }

  /// `https://api.github.com/repos/owner/repo` → `owner/repo`。
  static String _fullNameFromRepositoryUrl(String url) {
    const marker = '/repos/';
    final idx = url.indexOf(marker);
    if (idx < 0) return '';
    final rest = url.substring(idx + marker.length);
    final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return '';
    return '${parts[0]}/${parts[1]}';
  }

  static String _fullNameFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['full_name'] is String) {
        return (decoded['full_name'] as String).trim();
      }
    } catch (_) {
      // 不是 JSON（镜像可能回了 HTML 错误页），退化到正则兜底。
    }
    final m = RegExp(r'"full_name"\s*:\s*"([^"]+)"').firstMatch(body);
    return m?.group(1)?.trim() ?? '';
  }
}
