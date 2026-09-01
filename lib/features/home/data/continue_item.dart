// lib/features/home/data/continue_item.dart
//
// 首页「继续使用」区块的统一条目模型。
//
// 影视和小说两侧的进度存储完全不同（Hive 的 play_history vs
// SharedPreferences 里按 bookId 分键的 reading_progress），这里把两者
// 归一成同一种卡片数据，让 UI 不必知道来源差异。
library;

/// 条目来源，决定点击时走哪条跳转路径。
enum ContinueKind { video, novel }

/// 首页「继续使用」的一张卡片。
class ContinueItem {
  const ContinueItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    this.coverUrl = '',
    this.progress,
  });

  final ContinueKind kind;

  /// 影视为 HistoryItem.storageKey，小说为 bookId。仅用于去重/定位，不展示。
  final String id;

  /// 主标题：剧名或书名。
  final String title;

  /// 副标题：影视为「源名 · 集名」，小说为章节名。
  final String subtitle;

  /// 最后一次使用时间（毫秒时间戳），用于跨来源统一排序。
  final int updatedAt;

  final String coverUrl;

  /// 播放/阅读进度 0.0–1.0。
  ///
  /// 小说侧拿不到可靠的整书百分比（`ReadingProgress` 只有 chapterIndex 和
  /// 章内偏移，不含总章数），所以允许为 null —— UI 此时不画进度条，
  /// 而不是画一根骗人的 0%。
  final double? progress;

  /// 进度是否值得展示。
  ///
  /// 刚打开就退出（不足 1%）时画一根几乎看不见的进度条只会显脏，
  /// 已看完（超过 99%）画满条也没有「继续」的意义。
  bool get hasMeaningfulProgress {
    final value = progress;
    if (value == null) return false;
    return value >= 0.01 && value <= 0.99;
  }

  /// 进度百分比文案，无有效进度时为 null。
  String? get progressLabel {
    if (!hasMeaningfulProgress) return null;
    return '${(progress! * 100).round()}%';
  }
}
