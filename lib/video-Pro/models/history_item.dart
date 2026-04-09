class HistoryItem {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String sourceId;
  final String sourceName;
  final String episodeName;
  final String episodeUrl;
  final int position;
  final int duration;
  final int updateTime;

  HistoryItem({
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.sourceId,
    required this.sourceName,
    required this.episodeName,
    required this.episodeUrl,
    required this.position,
    required this.duration,
    required this.updateTime,
  });

  /// 统一存储 key，避免不同源同 vodId 覆盖
  String get storageKey {
    final sid = sourceId.trim();
    final vid = vodId.trim();
    if (sid.isEmpty) return vid;
    return '$sid|$vid';
  }

  double get progressPercentage {
    if (duration <= 0) return 0.0;
    final ratio = position / duration;
    if (ratio.isNaN || ratio.isInfinite) return 0.0;
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  Map<String, dynamic> toMap() => {
        'storageKey': storageKey,
        'vodId': vodId,
        'vodName': vodName,
        'vodPic': vodPic,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'episodeName': episodeName,
        'episodeUrl': episodeUrl,
        'position': position,
        'duration': duration,
        'updateTime': updateTime,
      };

  factory HistoryItem.fromMap(Map<dynamic, dynamic> map) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String asString(dynamic value, [String fallback = '']) {
      if (value == null) return fallback;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
      return text;
    }

    return HistoryItem(
      vodId: asString(map['vodId'] ?? map['vod_id']),
      vodName: asString(map['vodName'] ?? map['vod_name']),
      vodPic: asString(map['vodPic'] ?? map['vod_pic']),
      sourceId: asString(map['sourceId'] ?? map['source_id']),
      sourceName: asString(map['sourceName'] ?? map['source_name']),
      episodeName: asString(map['episodeName'] ?? map['episode_name']),
      episodeUrl: asString(map['episodeUrl'] ?? map['episode_url']),
      position: asInt(map['position']),
      duration: asInt(map['duration']),
      updateTime: asInt(map['updateTime']),
    );
  }
}