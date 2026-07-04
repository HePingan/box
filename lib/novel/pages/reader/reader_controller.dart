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

  String title = '';
  String content = '';

  bool showMenu = false;
  bool isScrollMode = false;
  bool loadingNextScroll = false;

  ReaderSettings settings = const ReaderSettings();
  ReadingProgress? progress;

  final List<ReaderScrollChapterItem> scrollItems = <ReaderScrollChapterItem>[];

  // 已读章节追踪
  final Set<int> _openedChapters = <int>{};

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

  /// 阅读进度 0.0–1.0
  double get chapterProgress {
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

  /// 当前书籍的书签列表
  List<ReaderBookmark> get bookmarks =>
      bookmarkService.loadForBook(detail.book.id);

  /// 当前章节是否已收藏
  bool get hasBookmarkForCurrent {
    return bookmarks.any((b) => b.chapterIndex == chapterIndex);
  }

  /// 添加书签
  Future<void> addBookmark({int? pageIndex}) async {
    final bookmark = ReaderBookmark(
      id: '${detail.book.id}_${chapterIndex}_${DateTime.now().millisecondsSinceEpoch}',
      bookId: detail.book.id,
      chapterIndex: chapterIndex,
      chapterTitle: currentChapterTitle,
      pageIndex: pageIndex,
      createdAt: DateTime.now(),
    );
    await bookmarkService.add(bookmark);
    notifyListeners();
  }

  /// 删除书签
  Future<void> removeBookmark(String bookmarkId) async {
    await bookmarkService.remove(detail.book.id, bookmarkId);
    notifyListeners();
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

  void updateProgress(ReadingProgress? next) {
    progress = next;
    notifyListeners();
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
    showMenu = false;
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
              .catchError((_) {}),
        );
      }

      // 如果该书标记了离线缓存，后台批量预取后续 30 章
      if (offlineCacheService != null) {
        unawaited(
          offlineCacheService!
              .prefetchNext(detail, chapterIndex + 1, count: 30)
              .catchError((_) {}),
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

  void setMenuVisible(bool value) {
    if (showMenu == value) return;
    showMenu = value;
    notifyListeners();
  }

  void toggleMenu() {
    setMenuVisible(!showMenu);
  }

  void setScrollMode(bool value) {
    if (isScrollMode == value) return;

    isScrollMode = value;
    showMenu = false;

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
    } catch (_) {
      // 预加载失败不影响当前阅读
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
