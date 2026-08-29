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
  GithubAccelService({GithubAccelFetch? fetch, this.mirror = GithubAccelLink.defaultMirror})
      : _fetch = fetch;

  final GithubAccelFetch? _fetch;
  final String mirror;

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

    final lookup = link.repoLookupUrl;
    final fetch = _fetch;
    if (lookup == null || fetch == null) {
      return GithubAccelResolution(
        link: link,
        ok: false,
        message: '这是带签名的临时地址，需要联网查询仓库信息才能转换。',
      );
    }

    try {
      final body = await fetch(lookup);
      final fullName = _fullNameFrom(body);
      if (fullName.isEmpty) {
        return GithubAccelResolution(
          link: link,
          ok: false,
          message: '查询仓库信息失败：返回内容里没有 full_name。',
        );
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
      debugPrint('[GithubAccel] 仓库查询失败: $e');
      return GithubAccelResolution(
        link: link,
        ok: false,
        message: '查询仓库信息失败：$e',
      );
    }
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
