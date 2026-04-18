import 'package:flutter/foundation.dart';

import '../../models/video_source.dart';
import '../../models/vod_item.dart';
import 'package:box/utils/app_logger.dart';

const String kFallbackCatalogUrl =
    'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json';

const List<String> kHomeNsfwKeywords = [
  '伦理',
  '三级',
  '写真',
  '热舞',
  '福利',
  '激情',
  '成人',
  '两性',
  '情色',
  '午夜',
  '限制级',
  '禁片',
  'VIP',
  '擦边',
];

/// Web 上通常建议 true；如果你本地直连图片稳定，也可以改 false
const bool kEnableHomeMediaProxy = true;

/// 你的图片代理前缀
const String kHomeMediaProxyPrefix =
    'https://proxy.shuabu.eu.org/?url=';

final RegExp _nsfwRegex = RegExp(
  kHomeNsfwKeywords.map(RegExp.escape).join('|'),
  caseSensitive: false,
);

void _logCover(String message) {
  if (kDebugMode) {
    AppLogger.instance.log(message, tag: 'COVER');
  }
}

bool isSafeContent(String? text) {
  if (text == null) return true;

  final trimmed = text.trim();
  if (trimmed.isEmpty) return true;

  return !_nsfwRegex.hasMatch(trimmed);
}

bool _isProxyUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;

  if (trimmed.startsWith(kHomeMediaProxyPrefix)) return true;

  final uri = Uri.tryParse(trimmed);
  return uri != null && uri.host == 'proxy.shuabu.eu.org';
}

String _wrapWithProxy(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  if (_isProxyUrl(trimmed)) return trimmed;
  return '$kHomeMediaProxyPrefix${Uri.encodeComponent(trimmed)}';
}

/// 把 rawUrl 解析成可直接展示的图片地址
/// - 绝对地址：直接返回
/// - //xxx：补 https
/// - 相对地址：用 source.detailUrl / source.url 补全
/// - 需要时再包一层图片代理
String? resolveImageUrl(String? rawUrl, VideoSource? source) {
  final raw = rawUrl?.trim().replaceAll('\\', '');

  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') {
    _logCover(
      '[resolveImageUrl] rawUrl is empty, source=${source?.name ?? "null"}',
    );
    return null;
  }

  final sourceName = source?.name ?? 'null';
  String? absolute;
  String reason = 'unknown';

  // 协议相对地址
  if (raw.startsWith('//')) {
    absolute = 'https:$raw';
    reason = 'protocol-relative';
  } else {
    final parsed = Uri.tryParse(raw);

    // 绝对地址
    if (parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      absolute = raw;
      reason = 'absolute';
    } else {
      // 相对路径，尝试用 source 补全
      final baseUrls = <String>[
        source == null ? '' : source.detailUrl.trim(),
        source == null ? '' : source.url.trim(),
      ];

      for (final base in baseUrls) {
        if (base.isEmpty) continue;

        final baseUri = Uri.tryParse(base);
        if (baseUri == null || !baseUri.hasScheme) continue;

        try {
          final resolved = baseUri.resolve(raw).toString();
          final resolvedUri = Uri.tryParse(resolved);

          if (resolvedUri != null &&
              resolvedUri.hasScheme &&
              (resolvedUri.scheme == 'http' || resolvedUri.scheme == 'https')) {
            absolute = resolved;
            reason = 'resolved-by-base=$base';
            break;
          }
        } catch (e) {
          _logCover(
            '[resolveImageUrl] resolve error raw=$raw base=$base source=$sourceName err=$e',
          );
        }
      }
    }
  }

  if (absolute == null || absolute.isEmpty) {
    _logCover(
      '[resolveImageUrl] FAILED raw=$raw source=$sourceName '
      'base1=${source?.detailUrl ?? "null"} base2=${source?.url ?? "null"}',
    );
    return null;
  }

  final finalUrl = kEnableHomeMediaProxy ? _wrapWithProxy(absolute) : absolute;

  _logCover(
    '[resolveImageUrl] OK source=$sourceName raw=$raw reason=$reason '
    'absolute=$absolute final=$finalUrl proxy=$kEnableHomeMediaProxy',
  );

  return finalUrl;
}

/// 视频封面同步解析
String? resolveVideoCoverSync(VodItem video, VideoSource? source) {
  final direct = resolveImageUrl(video.vodPic, source);

  _logCover(
    '[resolveVideoCoverSync] vodId=${video.vodId} '
    'vodName=${video.vodName} '
    'vodPic=${video.vodPic ?? "null"} '
    'source=${source?.name ?? "null"} '
    'resolved=${direct ?? "null"}',
  );

  if (direct != null && direct.isNotEmpty) {
    return direct;
  }

  return null;
}