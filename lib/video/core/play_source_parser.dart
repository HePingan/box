import 'models.dart';

String normalizePlaySourceName(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '默认线路';

  final key = text.toLowerCase();

  if (key.contains('liangzi') || key.contains('lzm3u8') || key == '量子') {
    return '量子';
  }
  if (key.contains('bfzym3u8') || key.contains('baofeng') || key.contains('暴风')) {
    return '暴风';
  }
  if (key.contains('ffm3u8') || key.contains('feifan') || key.contains('非凡')) {
    return '非凡';
  }
  if (key.contains('ikun')) {
    return 'iKun';
  }
  if (key.contains('wolong') || key.contains('卧龙')) {
    return '卧龙';
  }
  if (key.contains('jjm3u8') || key.contains('极速')) {
    return '极速';
  }
  if (key.contains('ukm3u8') || key.contains('u酷') || key.contains('uku')) {
    return 'U酷';
  }
  if (key.contains('snm3u8') || key.contains('闪电')) {
    return '闪电';
  }
  if (key.contains('dbm3u8') || key.contains('豆瓣')) {
    return '豆瓣';
  }

  return text;
}

List<String> _splitTriple(String raw) {
  if (raw.trim().isEmpty) return const [];
  return raw
      .split(r'$$$')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

String _normalizeText(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('\\/', '/')
      .replaceAll('\r', '')
      .replaceAll('\n', '')
      .trim();
}

List<VideoEpisode> _parseEpisodeGroup(String rawGroup) {
  final group = _normalizeText(rawGroup);
  if (group.isEmpty) return const [];

  final parts = group
      .split('#')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  final episodes = <VideoEpisode>[];
  final seen = <String>{};

  for (var i = 0; i < parts.length; i++) {
    final item = parts[i];
    final firstDollar = item.indexOf('\$');

    String title;
    String url;

    if (firstDollar > 0) {
      title = item.substring(0, firstDollar).trim();
      url = item.substring(firstDollar + 1).trim();
    } else {
      title = parts.length == 1 ? '正片' : '第${(i + 1).toString().padLeft(2, '0')}集';
      url = item.trim();
    }

    title = _normalizeText(title);
    url = _normalizeText(url);

    if (title.isEmpty) {
      title = parts.length == 1 ? '正片' : '第${(i + 1).toString().padLeft(2, '0')}集';
    }
    if (url.isEmpty) continue;

    final sign = '$title|$url';
    if (!seen.add(sign)) continue;

    episodes.add(
      VideoEpisode(
        title: title,
        url: url,
        index: episodes.length,
      ),
    );
  }

  return episodes;
}

List<VideoPlaySource> parseMacCmsPlaySources({
  required dynamic playFrom,
  required dynamic playUrl,
}) {
  final fromList = _splitTriple((playFrom ?? '').toString());
  final urlList = _splitTriple((playUrl ?? '').toString());

  final maxLength = fromList.length > urlList.length ? fromList.length : urlList.length;
  final result = <VideoPlaySource>[];

  for (var i = 0; i < maxLength; i++) {
    final rawSourceName = i < fromList.length ? fromList[i] : '线路${i + 1}';
    final rawGroup = i < urlList.length ? urlList[i] : '';

    final episodes = _parseEpisodeGroup(rawGroup);
    if (episodes.isEmpty) continue;

    result.add(
      VideoPlaySource(
        name: normalizePlaySourceName(rawSourceName),
        episodes: episodes,
      ),
    );
  }

  return result;
}

List<VideoPlaySource> parsePlaySourcesFromVodMap(Map<String, dynamic> vod) {
  return parseMacCmsPlaySources(
    playFrom: vod['vod_play_from'] ?? vod['playFrom'] ?? vod['play_from'],
    playUrl: vod['vod_play_url'] ?? vod['playUrl'] ?? vod['play_url'],
  );
}