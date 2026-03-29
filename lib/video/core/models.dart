String _asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) {
    final v = value.trim();
    return v.isEmpty ? fallback : v;
  }
  if (value is num || value is bool) return value.toString();
  if (value is List && value.isNotEmpty) return _asString(value.first, fallback);
  final v = value.toString().trim();
  return v.isEmpty ? fallback : v;
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

double _asDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'query': query,
        'description': description,
      };

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    return VideoCategory(
      id: _asString(json['id']),
      title: _asString(json['title']),
      query: _asString(json['query']),
      description: _asString(json['description']),
    );
  }
}

class VideoItem {
  final String id;
  final String title;
  final String intro;
  final String coverUrl;
  final String detailUrl;
  final String category;
  final String yearText;
  final String sourceName;

  const VideoItem({
    required this.id,
    required this.title,
    required this.intro,
    required this.coverUrl,
    required this.detailUrl,
    this.category = '',
    this.yearText = '',
    this.sourceName = '',
  });

  VideoItem copyWith({
    String? id,
    String? title,
    String? intro,
    String? coverUrl,
    String? detailUrl,
    String? category,
    String? yearText,
    String? sourceName,
  }) {
    return VideoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      intro: intro ?? this.intro,
      coverUrl: coverUrl ?? this.coverUrl,
      detailUrl: detailUrl ?? this.detailUrl,
      category: category ?? this.category,
      yearText: yearText ?? this.yearText,
      sourceName: sourceName ?? this.sourceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'intro': intro,
        'coverUrl': coverUrl,
        'detailUrl': detailUrl,
        'category': category,
        'yearText': yearText,
        'sourceName': sourceName,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: _asString(json['id']),
      title: _asString(json['title']),
      intro: _asString(json['intro']),
      coverUrl: _asString(json['coverUrl']),
      detailUrl: _asString(json['detailUrl']),
      category: _asString(json['category']),
      yearText: _asString(json['yearText']),
      sourceName: _asString(json['sourceName']),
    );
  }
}

class VideoEpisode {
  final String title;
  final String url;
  final int index;
  final String durationText;

  const VideoEpisode({
    required this.title,
    required this.url,
    required this.index,
    this.durationText = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'index': index,
        'durationText': durationText,
      };

  factory VideoEpisode.fromJson(Map<String, dynamic> json) {
    return VideoEpisode(
      title: _asString(json['title']),
      url: _asString(json['url']),
      index: _asInt(json['index']),
      durationText: _asString(json['durationText']),
    );
  }
}

class VideoDetail {
  final VideoItem item;
  final String creator;
  final String description;
  final List<String> tags;
  final List<VideoEpisode> episodes;
  final String sourceUrl;

  const VideoDetail({
    required this.item,
    required this.creator,
    required this.description,
    required this.tags,
    required this.episodes,
    this.sourceUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'creator': creator,
        'description': description,
        'tags': tags,
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'sourceUrl': sourceUrl,
      };

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final itemRaw = json['item'];
    final itemMap = itemRaw is Map ? Map<String, dynamic>.from(itemRaw) : <String, dynamic>{};

    final tagsRaw = json['tags'];
    final tags = tagsRaw is List ? tagsRaw.map((e) => _asString(e)).where((e) => e.isNotEmpty).toList() : <String>[];

    final episodesRaw = json['episodes'];
    final episodes = episodesRaw is List
        ? episodesRaw
            .whereType<Map>()
            .map((e) => VideoEpisode.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <VideoEpisode>[];

    return VideoDetail(
      item: VideoItem.fromJson(itemMap),
      creator: _asString(json['creator']),
      description: _asString(json['description']),
      tags: tags,
      episodes: episodes,
      sourceUrl: _asString(json['sourceUrl']),
    );
  }
}

class VideoPlaybackProgress {
  final String videoId;
  final int episodeIndex;
  final double positionSeconds;
  final double durationSeconds;
  final int updatedAt;

  const VideoPlaybackProgress({
    required this.videoId,
    required this.episodeIndex,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });

  VideoPlaybackProgress copyWith({
    String? videoId,
    int? episodeIndex,
    double? positionSeconds,
    double? durationSeconds,
    int? updatedAt,
  }) {
    return VideoPlaybackProgress(
      videoId: videoId ?? this.videoId,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'episodeIndex': episodeIndex,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAt': updatedAt,
      };

  factory VideoPlaybackProgress.fromJson(Map<String, dynamic> json) {
    return VideoPlaybackProgress(
      videoId: _asString(json['videoId']),
      episodeIndex: _asInt(json['episodeIndex']),
      positionSeconds: _asDouble(json['positionSeconds']),
      durationSeconds: _asDouble(json['durationSeconds']),
      updatedAt: _asInt(json['updatedAt']),
    );
  }
}