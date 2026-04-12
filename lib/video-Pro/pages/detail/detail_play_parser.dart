import '../../models/video_source.dart';
import '../../models/vod_item.dart';
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

        final episodeName =
            _text(ep.name) ?? _text(ep.title) ?? '第${j + 1}集';
        final resolvedUrl = resolvePlayUrl(ep.url, source: source);

        if (resolvedUrl.trim().isEmpty) continue;

        episodes.add(
          DetailPlayEpisode(
            name: episodeName,
            url: resolvedUrl,
          ),
        );
      }

      if (episodes.isNotEmpty) {
        result.add(
          DetailPlayLine(
            name: groupName,
            episodes: episodes,
          ),
        );
      }
    }

    return result;
  }

  static DetailPlaybackSelection pickDefaultSelection(
    List<DetailPlayLine> lines, {
    String? initialEpisodeUrl,
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

    final lineIndex = lines.indexWhere((line) => line.episodes.isNotEmpty);
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

  static String resolvePlayUrl(
    String rawUrl, {
    required VideoSource source,
  }) {
    var url = rawUrl.trim().replaceAll('\\', '');
    if (url.isEmpty) return url;

    if (url.startsWith('//')) {
      return 'https:$url';
    }

    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      return url;
    }

    for (final base in <String>[
      source.detailUrl,
      source.url,
    ]) {
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

    for (final base in <String>[
      source.detailUrl,
      source.url,
    ]) {
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

    if (leftUri != null &&
        rightUri != null &&
        leftUri.path == rightUri.path) {
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