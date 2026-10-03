import '../../models/video_source.dart';
import '../../models/vod_item.dart';
import '../../services/source_match.dart';
import '../../utils/play_url_policy.dart';
import 'detail_models.dart';

/// 详情页播放数据解析器
///
/// 作用：
/// 1. 直接复用 VodItem.parsePlayUrls
/// 2. 把原始播放地址按 VideoSource 的 baseUrl 做相对路径补全
/// 3. 统一默认选中线路 / 集数
class DetailPlayParser {
  static List<DetailPlayLine> buildPlayLines(
    VodItem detail,
    VideoSource source,
  ) {
    final rawGroups = detail.parsePlayUrls;

    if (rawGroups.isEmpty) {
      return const [];
    }

    final result = <DetailPlayLine>[];

    for (var i = 0; i < rawGroups.length; i++) {
      final group = rawGroups[i];
      final groupName = _text(group.name) ?? '线路${i + 1}';

      final episodes = <DetailPlayEpisode>[];

      for (var j = 0; j < group.episodes.length; j++) {
        final ep = group.episodes[j];

        final episodeName = _text(ep.name) ?? _text(ep.title) ?? '第${j + 1}集';
        final resolvedUrl = resolvePlayUrl(ep.url, source: source);

        if (resolvedUrl.trim().isEmpty) continue;

        episodes.add(DetailPlayEpisode(name: episodeName, url: resolvedUrl));
      }

      if (episodes.isNotEmpty) {
        result.add(DetailPlayLine(name: groupName, episodes: episodes));
      }
    }

    return result;
  }

  static DetailPlaybackSelection pickDefaultSelection(
    List<DetailPlayLine> lines, {
    String? initialEpisodeUrl,
    String? initialEpisodeName,
  }) {
    if (lines.isEmpty) {
      return const DetailPlaybackSelection.none();
    }

    final initial = initialEpisodeUrl?.trim();
    if (initial != null && initial.isNotEmpty) {
      for (var li = 0; li < lines.length; li++) {
        final line = lines[li];
        for (var ei = 0; ei < line.episodes.length; ei++) {
          final ep = line.episodes[ei];
          if (sameUrl(ep.url, initial)) {
            return DetailPlaybackSelection(
              lineIndex: li,
              episodeIndex: ei,
              url: ep.url,
              name: ep.name,
            );
          }
        }
      }
    }

    // 跨源续播：地址对不上（换了片源，地址必然不同）时按剧集名认同一集。
    final mediaLineFirst = lines.indexWhere(
      (line) =>
          line.episodes.isNotEmpty &&
          _looksLikeMediaUrl(line.episodes.first.url),
    );
    final nameMatch = matchEpisodeByName(
      lines,
      initialEpisodeName ?? '',
      preferLineIndex: mediaLineFirst >= 0 ? mediaLineFirst : null,
    );
    if (nameMatch != null) {
      final ep = lines[nameMatch.lineIndex].episodes[nameMatch.episodeIndex];
      return DetailPlaybackSelection(
        lineIndex: nameMatch.lineIndex,
        episodeIndex: nameMatch.episodeIndex,
        url: ep.url,
        name: ep.name,
      );
    }

    // 默认线路优先选「给的是真媒体地址」的那条：实测 21 部影片里 10 部的第一条
    // 线路是云播网页（`/play/<id>`、`/share/<id>`），默认选中它点开就是失败。
    final mediaLineIndex = lines.indexWhere(
      (line) =>
          line.episodes.isNotEmpty &&
          _looksLikeMediaUrl(line.episodes.first.url),
    );
    final lineIndex = mediaLineIndex >= 0
        ? mediaLineIndex
        : lines.indexWhere((line) => line.episodes.isNotEmpty);
    final safeLineIndex = lineIndex >= 0 ? lineIndex : 0;
    final line = lines[safeLineIndex];

    if (line.episodes.isEmpty) {
      return const DetailPlaybackSelection.none();
    }

    final firstEpisode = line.episodes.first;
    return DetailPlaybackSelection(
      lineIndex: safeLineIndex,
      episodeIndex: 0,
      url: firstEpisode.url,
      name: firstEpisode.name,
    );
  }

  /// 跨源续播用：按**剧集名**在剧集列表里认同一集。
  ///
  /// 换了片源后地址必然不同（`sameUrl` 不可能命中），只能靠名字。
  /// 归一化后精确相等才认（`第03集` == `第3集`）；`preferLineIndex`（一般是
  /// 真媒体线路）先看，避免认到云播网页那条线上。
  static ({int lineIndex, int episodeIndex})? matchEpisodeByName(
    List<DetailPlayLine> lines,
    String episodeName, {
    int? preferLineIndex,
  }) {
    final wanted = normalizeEpisodeName(episodeName);
    if (wanted.isEmpty) return null;

    final order = <int>[
      if (preferLineIndex != null &&
          preferLineIndex >= 0 &&
          preferLineIndex < lines.length)
        preferLineIndex,
      for (var i = 0; i < lines.length; i++)
        if (i != preferLineIndex) i,
    ];
    for (final li in order) {
      final line = lines[li];
      for (var ei = 0; ei < line.episodes.length; ei++) {
        if (normalizeEpisodeName(line.episodes[ei].name) == wanted) {
          return (lineIndex: li, episodeIndex: ei);
        }
      }
    }
    return null;
  }

  /// 这条线路给的是不是真媒体地址（.m3u8 / .mp4 / ...）。
  static bool _looksLikeMediaUrl(String? raw) {
    return PlayUrlPolicy.shapeOf(Uri.tryParse((raw ?? '').trim())) ==
        PlayUrlShape.media;
  }

  static String resolvePlayUrl(String rawUrl, {required VideoSource source}) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return url;

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      return url;
    }

    for (final base in <String>[source.detailUrl, source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // ignore
      }
    }

    return url;
  }

  static String? resolveImageUrl(
    String? rawUrl, {
    required VideoSource source,
  }) {
    if (rawUrl == null) return null;

    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return null;

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      return url;
    }

    for (final base in <String>[source.detailUrl, source.url]) {
      final baseUri = Uri.tryParse(base.trim());
      if (baseUri == null || !baseUri.hasScheme) continue;

      try {
        return baseUri.resolve(url).toString();
      } catch (_) {
        // ignore
      }
    }

    return url;
  }

  static bool sameUrl(String a, String b) {
    final left = _canonicalUrl(a);
    final right = _canonicalUrl(b);

    if (left == right) return true;

    final leftUri = Uri.tryParse(left);
    final rightUri = Uri.tryParse(right);

    if (leftUri != null && rightUri != null && leftUri.path == rightUri.path) {
      return true;
    }

    return false;
  }

  static String formatPosition(int millis) {
    final totalSeconds = (millis / 1000).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int n) => n.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  static String _canonicalUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    return uri.replace(fragment: '').toString();
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}
