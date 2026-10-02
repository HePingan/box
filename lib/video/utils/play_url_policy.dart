/// 播放地址形态判定 + 云播页归一化规则（纯函数，可单测，不碰网络）。
///
/// 为什么需要它（2026-10-02 走 App 同一条链路实测）：
/// 21 部影片 31 条线路里有 11 条播不了，其中 9 条不是网络问题，而是采集站
/// 给的地址根本不是媒体流，是云播 / 解析网页：
///   - `/play/<id>`  ：同一路径补 `/index.m3u8` 就能拿到真 HLS（实测 6/6）；
///   - `/share/<id>` ：补 `/index.m3u8` 是 404，得拉页面取 `var main`（实测 2/2）。
/// 以前这类地址一路放行到 ExoPlayer，用户看到的是「播放失败」；而「这是不是
/// 网页线路」在解析阶段就能确定，不必等播放器报错。
library;

/// 播放地址的形态。
enum PlayUrlShape {
  /// 直链媒体（.m3u8 / .mp4 / ...）。
  media,

  /// 云播页：`.../play/<id>`，补 `/index.m3u8` 通常就是真流。
  playPage,

  /// 分享解析页：`.../share/<id>`，真流在页面里的 `var main`。
  sharePage,

  /// 其它（相对地址、非 http(s)、测不出形态）。
  other,
}

/// 一次媒体探测的判定结果。
enum PlayProbeVerdict {
  /// 拿到了媒体（HLS 清单或二进制响应体）。
  playable,

  /// 服务器答了，但答的不是媒体（HTML 页、404 等）。
  answeredButNotMedia,

  /// 没拿到响应（超时 / 连接失败 / DNS）。
  unreachable,
}

const Set<String> _mediaExtensions = <String>{
  '.m3u8',
  '.mp4',
  '.flv',
  '.ts',
  '.mpd',
  '.mkv',
  '.avi',
  '.mov',
  '.webm',
  '.m4v',
};

class PlayUrlPolicy {
  const PlayUrlPolicy._();

  /// 判定地址形态。`/play/<id>/index.m3u8` 因为以 .m3u8 结尾算 [media]。
  static PlayUrlShape shapeOf(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return PlayUrlShape.other;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return PlayUrlShape.other;

    final path = uri.path.toLowerCase();
    if (path.isEmpty || path == '/') return PlayUrlShape.other;
    for (final extension in _mediaExtensions) {
      if (path.endsWith(extension)) return PlayUrlShape.media;
    }

    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    for (var i = 0; i < segments.length; i++) {
      // `<name>/<id>`：段后必须还有内容，否则 `/play/` 这种不算。
      if (i + 1 >= segments.length) continue;
      final segment = segments[i].toLowerCase();
      if (segment == 'play' || segment == 'playcontent') {
        return PlayUrlShape.playPage;
      }
      if (segment == 'share') return PlayUrlShape.sharePage;
    }
    return PlayUrlShape.other;
  }

  /// 是不是「网页线路」（需要二次解析的云播页）。
  static bool isCloudPage(Uri? uri) {
    final shape = shapeOf(uri);
    return shape == PlayUrlShape.playPage || shape == PlayUrlShape.sharePage;
  }

  /// 云播页 → 可直接交给播放器的候选地址（还需探测确认）。
  ///
  /// 只有 [PlayUrlShape.playPage] 能纯靠拼路径得到候选；[PlayUrlShape.sharePage]
  /// 必须先把页面拉回来（见 [extractShareMainUrl]）。
  static List<Uri> mediaCandidatesFor(Uri? pageUri) {
    if (pageUri == null || shapeOf(pageUri) != PlayUrlShape.playPage) {
      return const <Uri>[];
    }
    final path = pageUri.path.endsWith('/')
        ? '${pageUri.path}index.m3u8'
        : '${pageUri.path}/index.m3u8';
    return <Uri>[pageUri.replace(path: path)];
  }

  /// 从分享解析页里取 `var main = "..."` 的原值（可能是相对路径）。
  static String? extractShareMainPath(String? body) {
    final text = body ?? '';
    if (text.isEmpty) return null;
    final match = RegExp(
      '''var\\s+main\\s*=\\s*["']([^"']+)["']''',
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// 把分享页里的 `var main` 还原成绝对地址（页面常写成 `\/path\/index.m3u8?sign=…`）。
  static String? extractShareMainUrl(String? body, Uri pageUri) {
    final raw = extractShareMainPath(body);
    if (raw == null) return null;

    final cleaned = raw.replaceAll(r'\/', '/').trim();
    if (cleaned.isEmpty) return null;

    final resolved = pageUri.resolve(cleaned);
    if (!resolved.hasScheme || resolved.host.isEmpty) return null;
    final scheme = resolved.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return resolved.toString();
  }

  /// 响应体像不像 HTML 页面（云播页、站点首页、Cloudflare 拦截页都算）。
  static bool looksLikeHtml(String? body) {
    final text = (body ?? '').trimLeft().toLowerCase();
    if (text.isEmpty) return false;
    return text.startsWith('<');
  }

  /// 响应体像不像 HLS 清单。
  static bool looksLikePlaylist(String? body) {
    final text = body ?? '';
    return text.contains('#EXTM3U') || text.contains('#EXT-X');
  }

  /// 判定一次探测的结果。判定顺序：清单 > HTML > 状态码 > content-type。
  static PlayProbeVerdict classifyProbe({
    required int statusCode,
    String? contentType,
    String? body,
  }) {
    if (statusCode == 0) return PlayProbeVerdict.unreachable;
    if (looksLikePlaylist(body)) return PlayProbeVerdict.playable;
    if (looksLikeHtml(body)) return PlayProbeVerdict.answeredButNotMedia;
    if (statusCode >= 400) return PlayProbeVerdict.answeredButNotMedia;

    final type = (contentType ?? '').toLowerCase();
    if (type.isEmpty) {
      return statusCode < 400
          ? PlayProbeVerdict.playable
          : PlayProbeVerdict.answeredButNotMedia;
    }
    if (type.contains('html') || type.contains('xml')) {
      return PlayProbeVerdict.answeredButNotMedia;
    }
    if (type.contains('mpegurl') ||
        type.contains('video/') ||
        type.contains('audio/') ||
        type.contains('mp2t') ||
        type.contains('octet-stream')) {
      return PlayProbeVerdict.playable;
    }
    // text/plain 之类的裸文本 + 200：既不是清单也不是 HTML，交给播放器试。
    return statusCode < 400
        ? PlayProbeVerdict.playable
        : PlayProbeVerdict.answeredButNotMedia;
  }
}
