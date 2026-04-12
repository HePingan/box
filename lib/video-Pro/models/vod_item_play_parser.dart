import 'dart:math' as math;

/// 单个播放集数
///
/// 兼容你前面页面里用到的字段：
/// - name
/// - title
/// - url
class PlayEpisode {
  final String name;
  final String url;

  const PlayEpisode({
    required this.name,
    required this.url,
  });

  /// 兼容一些旧代码可能写 title
  String get title => name;
}

/// 单条播放线路
///
/// 兼容你前面页面里用到的字段：
/// - name
/// - episodes
class PlaySourceGroup {
  final String name;
  final List<PlayEpisode> episodes;

  const PlaySourceGroup({
    required this.name,
    required this.episodes,
  });

  bool get isEmpty => episodes.isEmpty;
  bool get isNotEmpty => episodes.isNotEmpty;
}

/// 播放字符串解析器
///
/// 兼容常见格式：
///
/// 1. 单线路：
///    `第1集$https://a.com/1.m3u8#第2集$https://a.com/2.m3u8`
///
/// 2. 多线路：
///    `线路1$$$线路2`
///    对应 `vod_play_url` 也用 `$$$` 分隔
///
/// 3. 如果没有 `vod_play_from`，也会自动兜底成 `线路1`
///
/// 4. 如果单集行里没有 `$`，会自动命名为 `第1集`
class VodItemPlayParser {
  static List<PlaySourceGroup> parse({
    String? vodPlayFrom,
    String? vodPlayUrl,
  }) {
    final fromGroups = _splitGroups(vodPlayFrom);
    final urlGroups = _splitGroups(vodPlayUrl);

    if (fromGroups.isEmpty && urlGroups.isEmpty) {
      return const <PlaySourceGroup>[];
    }

    final groupCount = math.max(fromGroups.length, urlGroups.length);
    final result = <PlaySourceGroup>[];

    for (var i = 0; i < groupCount; i++) {
      final groupName = _clean(_valueAt(fromGroups, i)) ?? '线路${i + 1}';
      final rawEpisodeLine = _valueAt(urlGroups, i);

      final episodes = _parseEpisodes(rawEpisodeLine);
      if (episodes.isEmpty) continue;

      result.add(
        PlaySourceGroup(
          name: groupName,
          episodes: episodes,
        ),
      );
    }

    return result;
  }

// 在 vod_item_play_parser.dart 中替换这两个方法：
  
  static List<String> _splitGroups(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.toLowerCase() == 'null') return const <String>[];
    // 🏆 优化：链式流处理，一步到位
    return raw.split(r'$$$')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static List<PlayEpisode> _parseEpisodes(String? rawLine) {
    if (rawLine == null || rawLine.trim().isEmpty) return const <PlayEpisode>[];

    // 🏆 优化：直接用单字符正则，性能比字符串数组切割更好
    final items = rawLine.split(RegExp(r'[#\r\n]'));
    final episodes = <PlayEpisode>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i].trim();
      if (item.isEmpty) continue;

      final dollarIndex = item.indexOf(r'$');
      String name, url;

      if (dollarIndex >= 0) {
        name = item.substring(0, dollarIndex).trim();
        url = item.substring(dollarIndex + 1).trim();
      } else {
        name = '第${i + 1}集';
        url = item;
      }

      if (url.isNotEmpty) episodes.add(PlayEpisode(name: name.isEmpty ? '第${i + 1}集' : name, url: url));
    }
    return episodes;
  }

  static String? _valueAt(List<String> list, int index) {
    if (index < 0 || index >= list.length) return null;
    return list[index];
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;
    return text;
  }
}