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

  double get progressPercentage =>
      duration > 0 ? (position / duration).clamp(0.0, 1.0).toDouble() : 0.0;

  Map<String, dynamic> toMap() => {
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
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String asString(dynamic value, [String fallback = '']) {
      if (value == null) return fallback;
      final text = value.toString().trim();
      return text.isEmpty ? fallback : text;
    }

    return HistoryItem(
      vodId: asString(map['vodId']),
      vodName: asString(map['vodName']),
      vodPic: asString(map['vodPic']),
      sourceId: asString(map['sourceId']),
      sourceName: asString(map['sourceName']),
      episodeName: asString(map['episodeName']),
      episodeUrl: asString(map['episodeUrl']),
      position: asInt(map['position']),
      duration: asInt(map['duration']),
      updateTime: asInt(map['updateTime']),
    );
  }
}