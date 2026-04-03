import 'dart:convert';

class VideoCategory {
  final String id;
  final String title;
  final String query;
  final String description;

  const VideoCategory({
    required this.id,
    required this.title,
    required this.query,
    this.description = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'query': query,
      'description': description,
    };
  }

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    return VideoCategory(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      query: (json['query'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}

class VideoItem {
  final String id;
  final String title;
  final String detailUrl;

  /// 兼容你旧代码中的 coverUrl
  final String cover;

  /// 兼容你旧代码中的 intro
  final String intro;

  /// 兼容旧 UI 的副标题
  final String subtitle;

  final String category;
  final String yearText;
  final String sourceName;

  /// 聚合源内部站点唯一标识
  final String providerKey;

  final String area;
  final String remark;

  /// 多源聚合时，保存聚合进去的原始候选条目
  final List<VideoItem> mergedItems;

  const VideoItem({
    required this.id,
    required this.title,
    required this.detailUrl,
    this.cover = '',
    this.intro = '',
    this.subtitle = '',
    this.category = '',
    this.yearText = '',
    this.sourceName = '',
    this.providerKey = '',
    this.area = '',
    this.remark = '',
    this.mergedItems = const [],
  });

  /// 兼容旧代码
  String get coverUrl => cover;

  /// 是否是聚合条目
  bool get isAggregated => mergedItems.isNotEmpty;

  /// 聚合源数量
  int get mergedSourceCount => isAggregated ? mergedItems.length : 1;

  /// 获取详情时真正要尝试的候选项
  List<VideoItem> get detailCandidates => isAggregated ? mergedItems : [this];

  VideoItem copyWith({
    String? id,
    String? title,
    String? detailUrl,
    String? cover,
    String? intro,
    String? subtitle,
    String? category,
    String? yearText,
    String? sourceName,
    String? providerKey,
    String? area,
    String? remark,
    List<VideoItem>? mergedItems,
  }) {
    return VideoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      detailUrl: detailUrl ?? this.detailUrl,
      cover: cover ?? this.cover,
      intro: intro ?? this.intro,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      yearText: yearText ?? this.yearText,
      sourceName: sourceName ?? this.sourceName,
      providerKey: providerKey ?? this.providerKey,
      area: area ?? this.area,
      remark: remark ?? this.remark,
      mergedItems: mergedItems ?? this.mergedItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'detailUrl': detailUrl,
      'cover': cover,
      'intro': intro,
      'subtitle': subtitle,
      'category': category,
      'yearText': yearText,
      'sourceName': sourceName,
      'providerKey': providerKey,
      'area': area,
      'remark': remark,
      'mergedItems': mergedItems
          .map((e) => e.copyWith(mergedItems: const []).toJson())
          .toList(),
    };
  }

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    final rawMergedItems = json['mergedItems'];

    return VideoItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      detailUrl: (json['detailUrl'] ?? '').toString(),
      cover: (json['cover'] ?? json['coverUrl'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      yearText: (json['yearText'] ?? '').toString(),
      sourceName: (json['sourceName'] ?? '').toString(),
      providerKey: (json['providerKey'] ?? '').toString(),
      area: (json['area'] ?? '').toString(),
      remark: (json['remark'] ?? '').toString(),
      mergedItems: rawMergedItems is List
          ? rawMergedItems
              .whereType<Map>()
              .map((e) => VideoItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class VideoEpisode {
  final String title;
  final String url;
  final String durationText;

  /// 兼容旧代码
  final int index;

  const VideoEpisode({
    required this.title,
    required this.url,
    this.durationText = '',
    this.index = 0,
  });

  VideoEpisode copyWith({
    String? title,
    String? url,
    String? durationText,
    int? index,
  }) {
    return VideoEpisode(
      title: title ?? this.title,
      url: url ?? this.url,
      durationText: durationText ?? this.durationText,
      index: index ?? this.index,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'durationText': durationText,
      'index': index,
    };
  }

  factory VideoEpisode.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    return VideoEpisode(
      title: (json['title'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      durationText: (json['durationText'] ?? '').toString(),
      index: parseInt(json['index']),
    );
  }
}

class VideoPlaySource {
  final String name;
  final List<VideoEpisode> episodes;

  const VideoPlaySource({
    required this.name,
    required this.episodes,
  });

  int get episodeCount => episodes.length;

  VideoPlaySource copyWith({
    String? name,
    List<VideoEpisode>? episodes,
  }) {
    return VideoPlaySource(
      name: name ?? this.name,
      episodes: episodes ?? this.episodes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'episodes': episodes.map((e) => e.toJson()).toList(),
    };
  }

  factory VideoPlaySource.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'];
    return VideoPlaySource(
      name: (json['name'] ?? '').toString(),
      episodes: rawEpisodes is List
          ? rawEpisodes
              .map((e) => VideoEpisode.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class VideoDetail {
  final VideoItem item;
  final String cover;
  final String description;
  final String creator;
  final String sourceUrl;
  final List<String> tags;

  /// 多线路结构
  final List<VideoPlaySource> playSources;

  const VideoDetail({
    required this.item,
    this.cover = '',
    this.description = '',
    this.creator = '',
    this.sourceUrl = '',
    this.tags = const [],
    this.playSources = const [],
  });

  /// 兼容旧代码：默认返回第一条线路的剧集
  List<VideoEpisode> get episodes {
    if (playSources.isEmpty) return const [];
    return playSources.first.episodes;
  }

  int get sourceCount => playSources.length;

  VideoDetail copyWith({
    VideoItem? item,
    String? cover,
    String? description,
    String? creator,
    String? sourceUrl,
    List<String>? tags,
    List<VideoPlaySource>? playSources,
  }) {
    return VideoDetail(
      item: item ?? this.item,
      cover: cover ?? this.cover,
      description: description ?? this.description,
      creator: creator ?? this.creator,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      tags: tags ?? this.tags,
      playSources: playSources ?? this.playSources,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item': item.toJson(),
      'cover': cover,
      'description': description,
      'creator': creator,
      'sourceUrl': sourceUrl,
      'tags': tags,
      'playSources': playSources.map((e) => e.toJson()).toList(),
    };
  }

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final rawPlaySources = json['playSources'];
    final rawEpisodes = json['episodes'];
    final rawTags = json['tags'];

    List<VideoPlaySource> playSources;
    if (rawPlaySources is List && rawPlaySources.isNotEmpty) {
      playSources = rawPlaySources
          .map((e) => VideoPlaySource.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (rawEpisodes is List && rawEpisodes.isNotEmpty) {
      playSources = [
        VideoPlaySource(
          name: '默认线路',
          episodes: rawEpisodes
              .map((e) => VideoEpisode.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        ),
      ];
    } else {
      playSources = const [];
    }

    return VideoDetail(
      item: VideoItem.fromJson(Map<String, dynamic>.from(json['item'] ?? {})),
      cover: (json['cover'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      creator: (json['creator'] ?? '').toString(),
      sourceUrl: (json['sourceUrl'] ?? '').toString(),
      tags: rawTags is List
          ? rawTags
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
          : const [],
      playSources: playSources,
    );
  }
}

class VideoPlaybackProgress {
  final String videoId;
  final int sourceIndex;
  final int episodeIndex;
  final double positionSeconds;
  final double durationSeconds;
  final int updatedAt;

  const VideoPlaybackProgress({
    required this.videoId,
    required this.sourceIndex,
    required this.episodeIndex,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });

  VideoPlaybackProgress copyWith({
    String? videoId,
    int? sourceIndex,
    int? episodeIndex,
    double? positionSeconds,
    double? durationSeconds,
    int? updatedAt,
  }) {
    return VideoPlaybackProgress(
      videoId: videoId ?? this.videoId,
      sourceIndex: sourceIndex ?? this.sourceIndex,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'sourceIndex': sourceIndex,
      'episodeIndex': episodeIndex,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'updatedAt': updatedAt,
    };
  }

  factory VideoPlaybackProgress.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    return VideoPlaybackProgress(
      videoId: (json['videoId'] ?? '').toString(),
      sourceIndex: parseInt(json['sourceIndex']),
      episodeIndex: parseInt(json['episodeIndex']),
      positionSeconds: parseDouble(json['positionSeconds']),
      durationSeconds: parseDouble(json['durationSeconds']),
      updatedAt: parseInt(json['updatedAt']),
    );
  }

  String encode() => jsonEncode(toJson());

  static VideoPlaybackProgress? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return VideoPlaybackProgress.fromJson(decoded);
      }
      if (decoded is Map) {
        return VideoPlaybackProgress.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return null;
  }
}