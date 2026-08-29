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
