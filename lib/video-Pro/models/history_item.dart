/// 文件功能：播放历史记录模型
/// 实现：保存视频 ID、源站 ID、集数名称及进度百分比
class HistoryItem {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String sourceId;      // 对应 VideoSource 的 ID
  final String sourceName;    // 对应 VideoSource 的名称
  final String episodeName;   // 当前播放的集数标题 (如：第05集)
  final String episodeUrl;    // 当前播放的集数 URL
  final int position;         // 当前播放进度 (毫秒)
  final int duration;         // 总时长 (毫秒)
  final int updateTime;       // 最后观看时间戳

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

  // 辅助计算：观看进度百分比
  double get progressPercentage => duration > 0 ? (position / duration) : 0.0;

  // 转为 Map 存储
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

  // 从 Map 恢复
  factory HistoryItem.fromMap(Map<dynamic, dynamic> map) {
    return HistoryItem(
      vodId: map['vodId'],
      vodName: map['vodName'],
      vodPic: map['vodPic'] ?? '',
      sourceId: map['sourceId'],
      sourceName: map['sourceName'],
      episodeName: map['episodeName'],
      episodeUrl: map['episodeUrl'],
      position: map['position'] ?? 0,
      duration: map['duration'] ?? 0,
      updateTime: map['updateTime'] ?? 0,
    );
  }
}