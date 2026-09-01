// lib/features/home/data/continue_repository.dart
//
// 把影视播放历史与小说阅读进度合并成首页「继续使用」的卡片列表。
//
// 两侧存储互不相干：
//   - 影视：Hive box `play_history`，HistoryController 已按 updateTime 倒序
//   - 小说：书架在 SharedPreferences（给书名/封面），进度按 bookId 分键存
//     （给章节名/时间），必须逐本查
//
// 依赖以函数形式注入，测试不必起 Hive / SharedPreferences。
library;

import 'dart:async';

import 'package:box/features/home/data/continue_item.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/video/models/history_item.dart';

typedef VideoHistoryLoader = Future<List<HistoryItem>> Function();
typedef BookshelfLoader = Future<List<NovelBook>> Function();
typedef NovelProgressLoader = Future<ReadingProgress?> Function(String bookId);

class ContinueRepository {
  ContinueRepository({
    required VideoHistoryLoader loadVideoHistory,
    required BookshelfLoader loadBookshelf,
    required NovelProgressLoader loadNovelProgress,
  }) : _loadVideoHistory = loadVideoHistory,
       _loadBookshelf = loadBookshelf,
       _loadNovelProgress = loadNovelProgress;

  final VideoHistoryLoader _loadVideoHistory;
  final BookshelfLoader _loadBookshelf;
  final NovelProgressLoader _loadNovelProgress;

  /// 首页横向轨最多展示的条目数。
  ///
  /// 首页是入口不是历史页，超出部分走「查看全部」。
  static const int maxItems = 8;

  /// 逐本查进度的并发上限。
  ///
  /// 书架可能有上百本，全部并发会瞬间打满 SharedPreferences 的读队列，
  /// 拖慢首屏。按书架顺序（最近收藏在前）只查前若干本 —— 更早收藏的书
  /// 即使有进度也早被 maxItems 挤掉了。
  static const int novelProbeLimit = 24;

  Future<List<ContinueItem>> load() async {
    // 两侧各自独立降级：一边的存储坏了不该让另一边也空掉。
    final results = await Future.wait([
      _videoItems().catchError((_) => const <ContinueItem>[]),
      _novelItems().catchError((_) => const <ContinueItem>[]),
    ]);

    final merged = <ContinueItem>[...results[0], ...results[1]]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return merged.take(maxItems).toList(growable: false);
  }

  Future<List<ContinueItem>> _videoItems() async {
    final history = await _loadVideoHistory();

    // 同一部剧看过多集时只留最近那条，否则一部剧就能占满整条轨。
    // HistoryController 已按 updateTime 倒序，但这里不依赖它 ——
    // 显式取更大的 updateTime，换用其它数据源时行为不变。
    final latestPerVod = <String, HistoryItem>{};
    for (final item in history) {
      final key = _vodKey(item);
      final existing = latestPerVod[key];
      if (existing == null || item.updateTime > existing.updateTime) {
        latestPerVod[key] = item;
      }
    }

    return latestPerVod.values.map((item) {
      final percentage = item.progressPercentage;
      return ContinueItem(
        kind: ContinueKind.video,
        id: item.storageKey,
        title: item.vodName,
        subtitle: _videoSubtitle(item),
        updatedAt: item.updateTime,
        coverUrl: item.vodPic,
        // duration<=0 时 progressPercentage 返回 0，那是「不知道」而非「0%」，
        // 不能当真实进度用。
        progress: item.duration > 0 ? percentage : null,
      );
    }).toList(growable: false);
  }

  static String _vodKey(HistoryItem item) {
    final sid = item.sourceId.trim();
    final vid = item.vodId.trim();
    return sid.isEmpty ? vid : '$sid|$vid';
  }

  static String _videoSubtitle(HistoryItem item) {
    final source = item.sourceName.trim();
    final episode = item.episodeName.trim();
    if (source.isEmpty) return episode;
    if (episode.isEmpty) return source;
    return '$source · $episode';
  }

  Future<List<ContinueItem>> _novelItems() async {
    final books = await _loadBookshelf();
    if (books.isEmpty) return const <ContinueItem>[];

    final candidates = books.take(novelProbeLimit).toList(growable: false);

    final progresses = await Future.wait(
      candidates.map((book) async {
        final bookId = _bookId(book);
        if (bookId.isEmpty) return null;
        try {
          return await _loadNovelProgress(bookId);
        } catch (_) {
          // 单本进度读失败不该让整个小说侧空掉。
          return null;
        }
      }),
    );

    final items = <ContinueItem>[];
    for (var i = 0; i < candidates.length; i++) {
      final progress = progresses[i];
      // 只收藏未读的书没有进度记录，不属于「继续」。
      if (progress == null) continue;

      final book = candidates[i];
      items.add(
        ContinueItem(
          kind: ContinueKind.novel,
          id: _bookId(book),
          title: book.title,
          subtitle: progress.chapterTitle.trim().isEmpty
              ? '第${progress.chapterIndex + 1}章'
              : progress.chapterTitle.trim(),
          updatedAt: progress.updatedAt,
          coverUrl: book.coverUrl,
          // ReadingProgress 只有 chapterIndex + 章内偏移，不含总章数，
          // 算不出可信的整书百分比。宁可不画进度条，也不画一个编的。
          progress: null,
        ),
      );
    }
    return items;
  }

  static String _bookId(NovelBook book) =>
      book.id.isNotEmpty ? book.id : book.detailUrl;
}
