import 'dart:math';

/// 视频条目
class VodItem {
  /// 视频 ID：使用 int，和页面里的 VideoDetailPage 入参保持一致
  final int vodId;

  final String vodName;
  final String? typeId;
  final String? typeName;
  final String? vodEn;

  /// 封面图
  final String? vodPic;

  /// 备注/更新状态
  final String? vodRemarks;

  /// 更新时间
  final String? vodTime;

  /// 主演
  final String? vodActor;

  /// 导演
  final String? vodDirector;

  /// 地区
  final String? vodArea;

  /// 语言
  final String? vodLang;

  /// 年份
  final String? vodYear;

  /// 播放线路，通常格式：
  /// wjm3u8$$$xgmi$$$...
  final String? vodPlayFrom;

  /// 播放地址，通常格式：
  /// 第1集$url1#第2集$url2$$$第1集$url3#第2集$url4
  final String? vodPlayUrl;

  /// 详情简介
  final String? vodContent;

  const VodItem({
    required this.vodId,
    required this.vodName,
    this.typeId,
    this.typeName,
    this.vodEn,
    this.vodPic,
    this.vodRemarks,
    this.vodTime,
    this.vodActor,
    this.vodDirector,
    this.vodArea,
    this.vodLang,
    this.vodYear,
    this.vodPlayFrom,
    this.vodPlayUrl,
    this.vodContent,
  });

  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      vodId: _parseInt(
        _pickString(json, const [
          'vod_id',
          'vodId',
          'id',
        ]),
      ),
      vodName: _pickString(json, const [
            'vod_name',
            'vodName',
            'name',
            'title',
          ]) ??
          '',
      typeId: _pickString(json, const [
        'type_id',
        'typeId',
      ]),
      typeName: _pickString(json, const [
        'type_name',
        'typeName',
      ]),
      vodEn: _pickString(json, const [
        'vod_en',
        'vodEn',
      ]),
      vodPic: _normalizeCoverUrl(
        _pickString(json, const [
          'vod_pic',
          'vodPic',
          'pic',
          'cover',
          'image',
          'img',
          'thumb',
          'poster',
          'vod_img',
        ]),
      ),
      vodRemarks: _pickString(json, const [
        'vod_remarks',
        'vodRemarks',
        'remarks',
        'remark',
      ]),
      vodTime: _pickString(json, const [
        'vod_time',
        'vodTime',
        'time',
      ]),
      vodActor: _pickString(json, const [
        'vod_actor',
        'vodActor',
        'actor',
      ]),
      vodDirector: _pickString(json, const [
        'vod_director',
        'vodDirector',
        'director',
      ]),
      vodArea: _pickString(json, const [
        'vod_area',
        'vodArea',
        'area',
      ]),
      vodLang: _pickString(json, const [
        'vod_lang',
        'vodLang',
        'lang',
      ]),
      vodYear: _pickString(json, const [
        'vod_year',
        'vodYear',
        'year',
      ]),
      vodPlayFrom: _pickString(json, const [
        'vod_play_from',
        'vodPlayFrom',
        'playFrom',
      ]),
      vodPlayUrl: _pickString(json, const [
        'vod_play_url',
        'vodPlayUrl',
        'playUrl',
      ]),
      vodContent: _pickString(json, const [
        'vod_content',
        'vodContent',
        'content',
        'desc',
        'description',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vod_id': vodId,
      'vod_name': vodName,
      'type_id': typeId,
      'type_name': typeName,
      'vod_en': vodEn,
      'vod_pic': vodPic,
      'vod_remarks': vodRemarks,
      'vod_time': vodTime,
      'vod_actor': vodActor,
      'vod_director': vodDirector,
      'vod_area': vodArea,
      'vod_lang': vodLang,
      'vod_year': vodYear,
      'vod_play_from': vodPlayFrom,
      'vod_play_url': vodPlayUrl,
      'vod_content': vodContent,
    };
  }

  /// 详情页会直接用到这个 getter
  ///
  /// 返回格式：
  /// [
  ///   PlaySourceGroup(name: 'wjm3u8', episodes: [...]),
  ///   PlaySourceGroup(name: 'xgmi', episodes: [...]),
  /// ]
  List<PlaySourceGroup> get parsePlayUrls {
    final rawPlayUrl = (vodPlayUrl ?? '').trim();
    if (rawPlayUrl.isEmpty) {
      return const [];
    }

    final rawPlayFrom = (vodPlayFrom ?? '').trim();

    final fromList = rawPlayFrom.isEmpty
        ? <String>[]
        : rawPlayFrom
            .split(RegExp(r'\s*\$\$\$\s*'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final urlGroups = rawPlayUrl
        .split(RegExp(r'\s*\$\$\$\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final groupCount = max(fromList.length, urlGroups.length);

    final result = <PlaySourceGroup>[];

    for (var i = 0; i < groupCount; i++) {
      final groupName = i < fromList.length && fromList[i].isNotEmpty
          ? fromList[i]
          : '线路${i + 1}';

      final groupRaw = i < urlGroups.length ? urlGroups[i] : '';
      final episodes = _parseEpisodes(groupRaw);

      if (episodes.isNotEmpty) {
        result.add(
          PlaySourceGroup(
            name: groupName,
            episodes: episodes,
          ),
        );
      }
    }

    return result;
  }

  /// 兼容旧命名
  List<PlaySourceGroup> get playUrls => parsePlayUrls;

  bool get hasCover => (vodPic ?? '').trim().isNotEmpty;

  static String? _pickString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  static int _parseInt(String? value) {
    if (value == null) return 0;
    return int.tryParse(value.trim()) ?? 0;
  }

  static String? _normalizeCoverUrl(String? raw) {
    if (raw == null) return null;

    var url = raw.trim();
    if (url.isEmpty) return null;

    // 协议相对地址：//img.xxx.com/a.jpg
    if (url.startsWith('//')) {
      return 'https:$url';
    }

    // 已经是绝对地址
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // 去掉反斜杠转义
    url = url.replaceAll('\\', '');

    // 相对路径先原样返回，页面里可再做 baseUrl 补全
    return url;
  }

  static List<PlayEpisode> _parseEpisodes(String groupRaw) {
    if (groupRaw.trim().isEmpty) return const [];

    final parts = groupRaw
        .split(RegExp(r'\s*#\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final result = <PlayEpisode>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];

      // 常见格式：第1集$url
      final dollarIndex = part.indexOf(r'$');

      String title;
      String url;

      if (dollarIndex >= 0) {
        title = part.substring(0, dollarIndex).trim();
        url = part.substring(dollarIndex + 1).trim();
      } else {
        title = '第${i + 1}集';
        url = part.trim();
      }

      if (title.isEmpty) {
        title = '第${i + 1}集';
      }

      if (url.isEmpty) continue;

      result.add(
        PlayEpisode(
          title: title,
          url: url,
        ),
      );
    }

    return result;
  }
}

/// 播放线路组
class PlaySourceGroup {
  final String name;
  final List<PlayEpisode> episodes;

  const PlaySourceGroup({
    required this.name,
    required this.episodes,
  });

  /// 兼容各种旧代码写法
  String get title => name;
  String get sourceName => name;
  String get lineName => name;

  List<PlayEpisode> get items => episodes;
  List<PlayEpisode> get playItems => episodes;
  List<PlayEpisode> get playUrls => episodes;

  /// 关键：让旧代码可以继续这样写：
  /// parsePlayUrls.first['url']
  /// parsePlayUrls.first['name']
  dynamic operator [](String key) {
    switch (key) {
      case 'name':
      case 'title':
      case 'sourceName':
      case 'lineName':
        return name;

      case 'url':
      case 'playUrl':
      case 'firstUrl':
        return episodes.isNotEmpty ? episodes.first.url : '';

      case 'episode':
      case 'item':
      case 'firstEpisode':
        return episodes.isNotEmpty ? episodes.first : null;

      case 'episodes':
      case 'items':
      case 'playItems':
      case 'playUrls':
        return episodes;

      default:
        return null;
    }
  }

  @override
  String toString() => 'PlaySourceGroup(name: $name, episodes: ${episodes.length})';
}

/// 单个播放条目
class PlayEpisode {
  final String title;
  final String url;

  const PlayEpisode({
    required this.title,
    required this.url,
  });

  /// 兼容不同命名
  String get name => title;
  String get episodeName => title;
  String get playUrl => url;
  String get link => url;
  String get href => url;

  /// 关键：支持旧代码中类似 item['url'] / item['name']
  dynamic operator [](String key) {
    switch (key) {
      case 'name':
      case 'title':
      case 'episodeName':
        return title;

      case 'url':
      case 'playUrl':
      case 'link':
      case 'href':
        return url;

      default:
        return null;
    }
  }

  @override
  String toString() => 'PlayEpisode(title: $title, url: $url)';
}