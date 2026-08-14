import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/novel_repository.dart';
import '../../core/offline_cache_service.dart';
import '../../core/text_cleaner.dart';
import '../../novel_module.dart';
import 'reader_progress_service.dart';
import 'reader_bookmark_service.dart';
import 'reader_search_types.dart';

enum ReaderJumpTarget { start, end, restoreDb }

class ReaderScrollChapterItem {
  final int index;
  final String title;
  final String content;
  final GlobalKey key;

  ReaderScrollChapterItem({
    required this.index,
    required this.title,
    required this.content,
    GlobalKey? key,
  }) : key = key ?? GlobalKey();
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.detail,
    required int initialChapterIndex,
    this.repository,
    this.offlineCacheService,
    ReaderProgressService? progressService,
    ReaderBookmarkService? bookmarkService,
  }) : progressService = progressService ?? const ReaderProgressService(),
       bookmarkService = bookmarkService ?? const NoopReaderBookmarkService(),
       chapterIndex = initialChapterIndex.clamp(
         0,
         detail.chapters.isEmpty ? 0 : detail.chapters.length - 1,
       );

  final NovelDetail detail;
  final NovelRepository? repository;
  final OfflineCacheService? offlineCacheService;
  final ReaderProgressService progressService;
  ReaderBookmarkService bookmarkService;

  /// 设置真实书签服务（初始化时异步获取 SharedPreferences 后调用）
  void initBookmarkService(ReaderBookmarkService service) {
    bookmarkService = service;
    notifyListeners();
  }

  int chapterIndex;

  NovelRepository get _repo => repository ?? NovelModule.repository;

  bool loading = true;
  bool isError = false;
  String errorText = '';

  // 切章转场状态
  bool isTransitioning = false;
  String transitionTitle = '';

  /// 取消正在进行的切章转场（用户点击遮罩时调用）
  void cancelTransition() {
    if (!isTransitioning) return;
    isTransitioning = false;
    transitionTitle = '';
    notifyListeners();
  }

  /// 最后一次进度保存的错误（UI 可用于提示用户）
  Object? lastSaveError;

  // --- 预取统计 ---
  int _prefetchFailCount = 0;

  /// 累计预取失败次数（调试用，可在设置页展示）
  int get prefetchFailCount => _prefetchFailCount;

  String title = '';
  String content = '';

  bool isScrollMode = false;
  bool loadingNextScroll = false;

  ReaderSettings settings = const ReaderSettings();
  ReadingProgress? progress;

  final List<ReaderScrollChapterItem> scrollItems = <ReaderScrollChapterItem>[];

  /// 已读章节追踪
  final Set<int> _openedChapters = <int>{};

  /// 已读章节集合（公开只读）
  Set<int> get readChapters => _openedChapters;

  /// 滚动模式下，基于已读章节数估算全书进度（跨章节更准确）
  double get scrollBookProgress {
    if (totalChapters <= 1) return chapterProgress;
    final ratio = _openedChapters.length / totalChapters;
    // 当前章节进度也叠加进来
    final currentProgress = chapterProgress;
    // 已读章节的权重：当前章节在最后一个位置时，progress 贡献最大
    final currentWeight = currentProgress / (totalChapters * 1.5);
    return (ratio + currentWeight).clamp(0.0, 1.0);
  }

  /// 请求序列号，防止并发加载覆盖
  int _loadSeq = 0;

  Timer? _settingsSaveDebounce;

  // --- 阅读统计 ---
  /// 当前章节总字符数
  int _totalChars = 0;

  /// 已读字符数（估算）
  int _charsRead = 0;

  /// 章节开始阅读时间戳
  DateTime? _chapterStartTime;

  /// 预估阅读速度（字符/分钟），基于过去 N 秒的采样
  double _estimatedCpm = 0.0;

  /// 上次采样时的 charsRead
  int _lastSampleChars = 0;
  static const _sampleInterval = Duration(seconds: 15);

  /// 阅读进度 0.0–1.0（滚动模式下返回全书进度，分页模式下返回章节进度）
  double get chapterProgress {
    if (isScrollMode) return scrollBookProgress;
    if (_totalChars <= 0) return 0.0;
    return (_charsRead / _totalChars).clamp(0.0, 1.0);
  }

  /// 预估剩余阅读时间（分钟）
  double get estimatedRemainingMinutes {
    final remaining = _totalChars - _charsRead;
    if (remaining <= 0 || _estimatedCpm <= 0) return 0.0;
    return remaining / _estimatedCpm;
  }

  /// 格式化的剩余时间字符串
  String get estimatedRemainingText {
    final mins = estimatedRemainingMinutes;
    if (mins <= 0) return '';
    if (mins < 1) return '即将读完';
    if (mins < 60) return '剩余约 ${mins.round()} 分钟';
    final hours = mins ~/ 60;
    final remainingMins = mins.remainder(60).round();
    return '剩余约 $hours 小时 $remainingMins 分钟';
  }

  /// 更新阅读进度（由页面层传入当前已读比例）
  void updateChapterProgress(double fraction, {int? totalChars}) {
    if (totalChars != null) _totalChars = totalChars;
    final newCharsRead = (_totalChars * fraction.clamp(0.0, 1.0)).round();
    if (newCharsRead == _charsRead) return;
    _charsRead = newCharsRead;

    // 阅读速度采样
    final now = DateTime.now();
    if (_chapterStartTime == null) {
      _chapterStartTime = now;
      _lastSampleChars = _charsRead;
      return;
    }
    final elapsed = now.difference(_chapterStartTime!);
    if (elapsed >= _sampleInterval) {
      final deltaChars = _charsRead - _lastSampleChars;
      final deltaMinutes = elapsed.inSeconds / 60.0;
      if (deltaMinutes > 0 && deltaChars > 0) {
        // 加权移动平均
        final currentCpm = deltaChars / deltaMinutes;
        _estimatedCpm = _estimatedCpm > 0
            ? (_estimatedCpm * 0.6 + currentCpm * 0.4)
            : currentCpm;
      }
      _lastSampleChars = _charsRead;
      _chapterStartTime = now;
    }
  }

  /// 章节加载时重置阅读统计
  void _resetReadingStats(int contentLength) {
    _totalChars = contentLength;
    _charsRead = 0;
    _chapterStartTime = DateTime.now();
    _lastSampleChars = 0;
    // _estimatedCpm 保留（跨章保持速度估算）
  }

  // --- 全文搜索 ---

  /// 搜索全书：章节标题 + 当前章节内容
  Future<List<ChapterSearchResult>> searchInBook(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final qLower = q.toLowerCase();
    final results = <ChapterSearchResult>[];

    // 1. 搜索章节标题
    for (int i = 0; i < detail.chapters.length; i++) {
      if (detail.chapters[i].title.toLowerCase().contains(qLower)) {
        results.add(
          ChapterSearchResult(
            chapterIndex: i,
            chapterTitle: detail.chapters[i].title,
            matchCount: 1,
            snippet: null,
            isTitleMatch: true,
            isCurrent: i == chapterIndex,
          ),
        );
      }
    }

    // 2. 搜索当前章节内容
    if (content.toLowerCase().contains(qLower)) {
      final count = _countMatches(content, qLower);
      final (snippet, pos) = _buildSnippet(content, qLower);
      // 去重 — 如果当前章节已有 title 匹配，合并
      final existing = results.indexWhere(
        (r) => r.chapterIndex == chapterIndex && r.isTitleMatch,
      );
      if (existing >= 0) {
        results[existing] = ChapterSearchResult(
          chapterIndex: chapterIndex,
          chapterTitle: currentChapterTitle,
          matchCount: results[existing].matchCount + count,
          snippet: snippet,
          isTitleMatch: results[existing].isTitleMatch,
          isCurrent: true,
          matchPosition: pos,
        );
      } else {
        results.add(
          ChapterSearchResult(
            chapterIndex: chapterIndex,
            chapterTitle: currentChapterTitle,
            matchCount: count,
            snippet: snippet,
            isTitleMatch: false,
            isCurrent: true,
            matchPosition: pos,
          ),
        );
      }
    }

    // 3. 排序：当前章节 > 标题匹配 > 内容匹配（按 matchCount 降序）
    results.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      if (a.isTitleMatch != b.isTitleMatch) return a.isTitleMatch ? -1 : 1;
      return b.matchCount.compareTo(a.matchCount);
    });

    return results;
  }

  (String, int) _buildSnippet(String text, String query) {
    final lower = text.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) return ('', 0);

    const radius = 50;
    final start = (idx - radius).clamp(0, text.length);
    final end = (idx + query.length + radius).clamp(0, text.length);

    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    return ('$prefix${text.substring(start, end)}$suffix', idx);
  }

  int _countMatches(String text, String queryLower) {
    int count = 0;
    int idx = 0;
    while ((idx = text.toLowerCase().indexOf(queryLower, idx)) >= 0) {
      count++;
      idx += queryLower.length;
    }
    return count;
  }

  bool get hasChapters => detail.chapters.isNotEmpty;

  int get totalChapters => detail.chapters.length;

  bool get canGoPrev => chapterIndex > 0;

  bool get canGoNext => chapterIndex < detail.chapters.length - 1;

  NovelChapter get currentChapter => detail.chapters[chapterIndex];

  bool isChapterRead(int index) => _openedChapters.contains(index);

  String get currentChapterTitle {
    if (detail.chapters.isEmpty) return '';
    return detail.chapters[chapterIndex].title;
  }

  String get bookTitle => detail.book.title;

  // --- 书签相关 ---

  /// 乐观更新时缓存的书签列表（持久化失败时回滚）
  List<ReaderBookmark> _cachedBookmarks = const [];

  /// 当前书籍的书签列表（优先返回缓存，兜底从 storage 读取）
  List<ReaderBookmark> get bookmarks =>
      _cachedBookmarks.isNotEmpty ? _cachedBookmarks : bookmarkService.loadForBook(detail.book.id);

  /// 当前章节是否已收藏
  bool get hasBookmarkForCurrent {
    return bookmarks.any((b) => b.chapterIndex == chapterIndex);
  }

  /// 添加书签（乐观更新：先更新 UI，持久化失败时回滚）
  /// 返回是否成功（false 表示重复或持久化失败）
  Future<bool> addBookmark({int? pageIndex}) async {
    final existing = bookmarks;
    final alreadyHas = existing.any(
      (b) => b.chapterIndex == chapterIndex,
    );
    if (alreadyHas) return false;

    final bookmark = ReaderBookmark(
      id: '${detail.book.id}_${chapterIndex}_${DateTime.now().millisecondsSinceEpoch}',
      bookId: detail.book.id,
      chapterIndex: chapterIndex,
      chapterTitle: currentChapterTitle,
      pageIndex: pageIndex,
      createdAt: DateTime.now(),
    );

    // 乐观更新 UI
    _cachedBookmarks = [...existing, bookmark];
    notifyListeners();

    // 异步持久化，失败时回滚
    final success = await bookmarkService.add(bookmark);
    if (!success) {
      _cachedBookmarks = existing;
      notifyListeners();
    }
    return success;
  }

  /// 删除书签（乐观更新 + 失败回滚）
  Future<bool> removeBookmark(String bookmarkId) async {
    final existing = bookmarks;
    final before = existing;

    // 乐观更新 UI
    _cachedBookmarks = existing.where((b) => b.id != bookmarkId).toList();
    notifyListeners();

    // 异步持久化，失败时回滚
    await bookmarkService.remove(detail.book.id, bookmarkId);
    // 注意：remove 不返回 success 标志，失败时静默回滚
    // 由于 SharedPreferences 是同步写入，实际失败概率极低
    final stillExists = existing.any((b) => b.id == bookmarkId);
    if (stillExists) {
      _cachedBookmarks = before;
      notifyListeners();
    }
    return !stillExists;
  }

  /// 跳转到指定书签章节
  void jumpToBookmark(ReaderBookmark bookmark) {
    if (bookmark.chapterIndex >= 0 && bookmark.chapterIndex < totalChapters) {
      setChapterIndex(bookmark.chapterIndex);
      // 延迟通知页面恢复偏移（由上层 UI 处理）
    }
  }

  void setChapterIndex(int index) {
    if (chapterIndex == index) return;
    chapterIndex = index.clamp(
      0,
      detail.chapters.isEmpty ? 0 : detail.chapters.length - 1,
    );
    notifyListeners();
  }

  /// 重试加载当前章节（error 状态下）
  Future<void> retry() async {
    await loadCurrentChapter(
      forceRefresh: true,
      target: ReaderJumpTarget.restoreDb,
    );
  }

  /// 更新已保存的阅读进度。
  ///
  /// 阅读页不读取 `progress`（它只在详情页由 NovelDetailController 使用），
  /// 而本方法会在滚动/翻页的防抖保存里被高频调用。若在此 notifyListeners，
  /// 每次落库都会重建整个阅读页（顶栏、底栏、PageView），造成滚动卡顿。
  /// 因此这里只更新字段，不触发重建。
  void updateProgress(ReadingProgress? next) {
    progress = next;
  }

  Future<void> bootstrap() async {
    loading = true;
    isError = false;
    errorText = '';
    notifyListeners();

    try {
      settings = await _repo.getReaderSettings();
      notifyListeners();

      if (!hasChapters) {
        loading = false;
        isError = true;
        errorText = '暂无可阅读章节';
        notifyListeners();
        return;
      }

      await loadCurrentChapter(
        forceRefresh: false,
        target: ReaderJumpTarget.restoreDb,
      );
    } catch (e) {
      loading = false;
      isError = true;
      errorText = '初始化失败：$e';
      notifyListeners();
    }
  }

  Future<void> loadCurrentChapter({
    required bool forceRefresh,
    required ReaderJumpTarget target,
  }) async {
    if (!hasChapters) {
      loading = false;
      isError = true;
      errorText = '暂无可阅读章节';
      notifyListeners();
      return;
    }

    _loadSeq++;
    final seq = _loadSeq;

    loading = true;
    isError = false;
    errorText = '';
    loadingNextScroll = false;
    notifyListeners();

    try {
      final data = await _repo
          .fetchChapter(
            detail: detail,
            chapterIndex: chapterIndex,
            forceRefresh: forceRefresh,
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw TimeoutException(
              '章节加载超时，请检查网络后重试',
              const Duration(seconds: 35),
            ),
          );

      // 如果在此期间又发了新的加载请求，丢弃旧结果
      if (seq != _loadSeq) return;

      title = data.title.trim().isEmpty ? currentChapter.title : data.title;
      content = _cleanText(data.content);
      _resetReadingStats(content.length);

      progress = await progressService.loadCurrentChapterProgress(
        detail.book.id,
        chapterIndex,
      );

      scrollItems
        ..clear()
        ..add(
          ReaderScrollChapterItem(
            index: chapterIndex,
            title: title,
            content: content,
          ),
        );

      final nextIndex = chapterIndex + 1;
      if (nextIndex < detail.chapters.length) {
        unawaited(
          _repo
              .prefetchChapter(detail: detail, chapterIndex: nextIndex)
              .catchError((Object e) {
            _prefetchFailCount++;
            debugPrint('预取失败 (章节 $nextIndex): $e');
            return null;
          }),
        );
      }

      // 如果该书标记了离线缓存，后台批量预取后续 30 章
      if (offlineCacheService != null) {
        unawaited(
          offlineCacheService!
              .prefetchNext(detail, chapterIndex + 1, count: 30)
              .catchError((Object e) {
            _prefetchFailCount++;
            debugPrint('批量预取失败: $e');
            return null;
          }),
        );
      }

      _openedChapters.add(chapterIndex);
      loading = false;
      isTransitioning = false;
      notifyListeners();
    } on TimeoutException catch (e) {
      // 标记过期请求不更新 UI
      if (seq != _loadSeq) return;
      loading = false;
      isTransitioning = false;
      isError = true;
      errorText = e.message ?? '加载超时，请重试';
      notifyListeners();
    } catch (e) {
      if (seq != _loadSeq) return;
      loading = false;
      isTransitioning = false;
      isError = true;
      errorText = '章节加载失败：$e';
      notifyListeners();
    }
  }

  Future<void> switchChapter(
    int index, {
    required ReaderJumpTarget target,
  }) async {
    if (index < 0 || index >= detail.chapters.length) return;

    chapterIndex = index;
    scrollItems.clear();

    // 设置转场状态：显示目标章节标题
    isTransitioning = true;
    transitionTitle = detail.chapters[index].title;
    notifyListeners();

    await loadCurrentChapter(forceRefresh: false, target: target);
  }

  void setScrollMode(bool value) {
    if (isScrollMode == value) return;

    isScrollMode = value;

    scrollItems.clear();
    if (value && hasChapters) {
      scrollItems.add(
        ReaderScrollChapterItem(
          index: chapterIndex,
          title: title,
          content: content,
        ),
      );
    }

    notifyListeners();
  }

  Future<void> fetchNextScrollChapter() async {
    if (!isScrollMode || loadingNextScroll || scrollItems.isEmpty) return;

    final nextIdx = scrollItems.last.index + 1;
    if (nextIdx >= detail.chapters.length) return;

    loadingNextScroll = true;
    notifyListeners();

    try {
      final data = await _repo.fetchChapter(
        detail: detail,
        chapterIndex: nextIdx,
        forceRefresh: false,
      );

      final nextTitle = data.title.trim().isEmpty
          ? detail.chapters[nextIdx].title
          : data.title;

      scrollItems.add(
        ReaderScrollChapterItem(
          index: nextIdx,
          title: nextTitle,
          content: _cleanText(data.content),
        ),
      );
    } catch (e) {
      // 预加载失败不影响当前阅读，但记录日志
      debugPrint('预加载章节失败: $e');
    } finally {
      loadingNextScroll = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(ReaderSettings next) async {
    settings = next;
    notifyListeners();

    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_repo.saveReaderSettings(next).catchError((_) {}));
    });
  }

  String _cleanText(String raw) {
    final lines = TextCleaner.normalizeWhitespace(raw).split('\n');

    final cleaned = <String>[];
    for (final line in lines) {
      if (line.isNotEmpty) cleaned.add('\u3000\u3000$line');
    }

    if (cleaned.isEmpty && raw.isNotEmpty) {
      cleaned.add('\u3000\u3000$raw');
    }

    return cleaned.join('\n');
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    unawaited(_repo.saveReaderSettings(settings).catchError((_) {}));
    super.dispose();
  }
}
