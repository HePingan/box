import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/models.dart';
import '../core/offline_cache_service.dart';
import '../novel_module.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'reader/reader_bookmark_service.dart';
import 'reader/reader_bookmark_sheet.dart';
import 'reader/reader_bottom_bar.dart';
import 'reader/reader_controller.dart';
import 'reader/reader_continuous_view.dart';
import 'reader/reader_directory_sheet.dart';
import 'reader/reader_navigation_controller.dart';
import 'reader/reader_paginator.dart';
import 'reader/reader_paged_view.dart';
import 'reader/reader_progress_service.dart';
import 'reader/reader_search_sheet.dart';
import 'reader/reader_settings_sheet.dart';
import 'reader/reader_top_bar.dart';
import 'package:box/features/dictionary/dictionary_manager.dart';
import 'package:box/features/dictionary/presentation/dictionary_sheet.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.detail,
    required this.initialChapterIndex,
  });

  final NovelDetail detail;
  final int initialChapterIndex;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderController _controller;
  late final ReaderNavigationController _navigationController;
  late final PageController _pageController;
  late final ScrollController _scrollController;

  final ReaderProgressService _progressService = const ReaderProgressService();

  final DictionaryManager _dictionaryManager = DictionaryManager();

  Timer? _saveDebounce;

  List<String> _textPages = <String>[];
  double _lastFitWidth = 0.0;
  double _lastNormalHeight = 0.0;

  bool _pageCalcScheduled = false;
  bool _scrollJumpScheduled = false;
  bool _paginatingRemaining = false;

  // 背景增量分页取消标志
  bool _paginateCancelFlag = false;

  // 页码指示器状态
  int _currentViewPage = 0;
  bool _showPageIndicator = false;
  Timer? _pageIndicatorTimer;

  @override
  void initState() {
    super.initState();

    _controller = ReaderController(
      detail: widget.detail,
      initialChapterIndex: widget.initialChapterIndex,
      offlineCacheService: OfflineCacheService(
        cache: NovelModule.repository.cache,
        repository: NovelModule.repository,
      ),
    );

    // 异步初始化真实书签服务
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      _controller.initBookmarkService(
        SharedPreferencesReaderBookmarkService(prefs),
      );
    });

    _pageController = PageController();
    _scrollController = ScrollController()..addListener(_onProgressChanged);

    _navigationController = ReaderNavigationController(
      readerController: _controller,
      pageController: _pageController,
      scrollController: _scrollController,
      getTextPages: () => _textPages,
      onResetPagedState: _resetPagedState,
      scheduleScrollJump: _scheduleScrollJump,
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    unawaited(_controller.bootstrap());
  }

  @override
  void dispose() {
    _paginateCancelFlag = true;
    // 清理所有 Timer
    _saveDebounce?.cancel();
    _pageIndicatorTimer?.cancel();
    unawaited(_saveProgress());

    _scrollController
      ..removeListener(_onProgressChanged)
      ..dispose();
    _pageController.dispose();
    _controller.dispose();
    _navigationController.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Color get _bgColor {
    switch (_controller.settings.themeMode) {
      case ReaderThemeMode.warm:
        return const Color(0xFFDDEBD2);
      case ReaderThemeMode.paper:
        return const Color(0xFFF6EFD8);
      case ReaderThemeMode.dark:
        return const Color(0xFF1E2028);
    }
  }

  Color get _textColor {
    switch (_controller.settings.themeMode) {
      case ReaderThemeMode.dark:
        return const Color(0xFFD0C8B8);
      case ReaderThemeMode.warm:
        return const Color(0xFF161F1A);
      case ReaderThemeMode.paper:
        return const Color(0xFF2C2C2C);
    }
  }

  double _encodeProgressOffset(double raw) {
    return _controller.isScrollMode ? raw : -(raw + 1.0);
  }

  double _decodePageOffset(double saved) {
    if (saved < 0) return -saved - 1.0;
    if (saved <= 500) return saved;
    return 0.0;
  }

  double _decodeScrollOffset(double saved) {
    return saved < 0 ? 0.0 : saved;
  }

  void _resetPagedState(ReaderJumpTarget target) {
    _navigationController.setJumpTarget(target);
    _paginateCancelFlag = true;
    setState(() {
      _textPages = <String>[];
      _lastFitWidth = 0.0;
      _lastNormalHeight = 0.0;
      _paginatingRemaining = false;
    });
  }

  void _showBookmarkConfirm() {
    final already = _controller.hasBookmarkForCurrent;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          already ? '移除书签' : '添加书签',
          style: TextStyle(color: _textColor),
        ),
        content: Text(
          already
              ? '取消当前章节书签？'
              : '收藏「${_controller.currentChapterTitle}」？',
          style: TextStyle(color: _textColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: _textColor)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              if (already) {
                await _controller.removeBookmark(
                  _controller.bookmarks.first.id,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已移除书签'),
                    backgroundColor: _textColor.withValues(alpha: 0.85),
                  ),
                );
              } else {
                await _controller.addBookmark();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已添加书签'),
                    backgroundColor: _textColor.withValues(alpha: 0.85),
                  ),
                );
              }
            },
            child: Text(already ? '移除' : '添加'),
          ),
        ],
      ),
    );
  }

  void _schedulePageRecalc(
    double fitWidth,
    double firstPageHeight,
    double normalPageHeight,
  ) {
    if (_pageCalcScheduled) return;
    _pageCalcScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageCalcScheduled = false;
      if (!mounted) return;
      _calculatePages(fitWidth, firstPageHeight, normalPageHeight);
    });
  }

  void _scheduleScrollJump() {
    if (_scrollJumpScheduled) return;
    _scrollJumpScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollJumpScheduled = false;
      if (!mounted) return;
      await _handleScrollJump();
    });
  }

  Future<void> _persistProgress(ReadingProgress progress) async {
    await _progressService.saveProgress(progress);
    _controller.updateProgress(progress);
  }

  Future<void> _saveProgress() async {
    if (_controller.isScrollMode || !_controller.hasChapters) return;

    double raw = 0.0;
    if (_pageController.hasClients) {
      raw = (_pageController.page ?? 1.0) - 1.0;
    }

    if (_textPages.isNotEmpty) {
      raw = raw.clamp(0.0, (_textPages.length - 1).toDouble());
    } else {
      raw = 0.0;
    }

    final nextProgress = ReadingProgress(
      bookId: widget.detail.book.id,
      chapterIndex: _controller.chapterIndex,
      chapterTitle: _controller.currentChapterTitle,
      scrollOffset: _encodeProgressOffset(raw),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _persistProgress(nextProgress);
  }

  void _updateScrollProgressAndDB() {
    if (!_controller.isScrollMode || _controller.scrollItems.isEmpty) return;
    if (!_scrollController.hasClients || !mounted) return;

    final topInset = MediaQuery.of(context).padding.top;
    final targetY = topInset + 60.0;

    int activeIdx = _controller.scrollItems.first.index;
    double activeOffset = 0.0;

    for (int i = _controller.scrollItems.length - 1; i >= 0; i--) {
      final item = _controller.scrollItems[i];
      final ctx = item.key.currentContext;
      if (ctx == null) continue;

      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;

      final topY = box.localToGlobal(Offset.zero).dy;
      if (topY <= targetY) {
        activeIdx = item.index;
        activeOffset = (targetY - topY).clamp(0.0, double.infinity);
        break;
      }
    }

    if (_controller.chapterIndex != activeIdx) {
      _controller.setChapterIndex(activeIdx);
    }

    // 更新阅读统计（基于滚动位置）
    final max = _scrollController.position.maxScrollExtent;
    if (max > 0) {
      final progress = (_scrollController.position.pixels / max).clamp(0.0, 1.0);
      _controller.updateChapterProgress(
        progress,
        totalChars: _controller.content.length,
      );
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), () {
      final nextProgress = ReadingProgress(
        bookId: widget.detail.book.id,
        chapterIndex: activeIdx,
        chapterTitle: widget.detail.chapters[activeIdx].title,
        scrollOffset: activeOffset,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      unawaited(_persistProgress(nextProgress));
    });
  }

  void _onProgressChanged() {
    if (_controller.isScrollMode) {
      _updateScrollProgressAndDB();
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), _saveProgress);

    if (mounted) setState(() {});
  }

  Future<void> _handleScrollJump() async {
    if (!_scrollController.hasClients) return;

    if (_navigationController.jumpTarget == ReaderJumpTarget.start) {
      _scrollController.jumpTo(0.0);
      return;
    }

    if (_navigationController.jumpTarget == ReaderJumpTarget.end) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      return;
    }

    final saved = await _progressService.restoreOffsetForChapter(
      widget.detail.book.id,
      _controller.chapterIndex,
    );

    _scrollController.jumpTo(saved == null ? 0.0 : _decodeScrollOffset(saved));
  }

  void _onPageChanged(int viewIndex) {
    if (_controller.isScrollMode || _textPages.isEmpty) return;

    final tail = _textPages.length + 1;

    if (viewIndex == 0 || viewIndex == tail) {
      unawaited(_navigationController.handlePageChanged(viewIndex));
      return;
    }

    _currentViewPage = viewIndex - 1;

    // 更新阅读统计
    final totalPages = _textPages.length;
    if (totalPages > 0) {
      _controller.updateChapterProgress(
        (_currentViewPage + 1) / totalPages,
        totalChars: _controller.content.length,
      );
    }

    _onProgressChanged();
  }

  void _onScreenTap(TapUpDetails details) {
    unawaited(_navigationController.handleScreenTap(details, context));
  }

  void _changeMode(bool isScroll) {
    if (_controller.isScrollMode == isScroll) return;

    _resetPagedState(ReaderJumpTarget.start);
    _controller.setScrollMode(isScroll);

    if (isScroll) {
      _scheduleScrollJump();
    }
  }

  Future<void> _openDirectory() async {
    _controller.setMenuVisible(false);

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      builder: (context) {
        return ReaderDirectorySheet(
          controller: _controller,
          bgColor: _bgColor,
          textColor: _textColor,
        );
      },
    );

    if (selected != null) {
      await _navigationController.switchChapter(
        selected,
        target: ReaderJumpTarget.start,
      );
    }
  }

  Future<void> _openBookmarkList() async {
    _controller.setMenuVisible(false);

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      builder: (context) {
        return ReaderBookmarkSheet(
          controller: _controller,
          bgColor: _bgColor,
          textColor: _textColor,
        );
      },
    );

    if (selected != null) {
      await _navigationController.switchChapter(
        selected,
        target: ReaderJumpTarget.start,
      );
    }
  }

  Future<void> _openSearch() async {
    _controller.setMenuVisible(false);

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      builder: (context) {
        return ReaderSearchSheet(
          controller: _controller,
          bgColor: _bgColor,
          textColor: _textColor,
        );
      },
    );

    if (selected != null) {
      await _navigationController.switchChapter(
        selected,
        target: ReaderJumpTarget.start,
      );
    }
  }

  Future<void> _openSettings() async {
    _controller.setMenuVisible(false);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bgColor,
      isScrollControlled: true,
      builder: (context) {
        return ReaderSettingsSheet(
          controller: _controller,
          bgColor: _bgColor,
          textColor: _textColor,
          onModeChanged: _changeMode,
          onSettingsChanged: (next) {
            unawaited(_controller.updateSettings(next));
            // 阅读时长亮控制
            try {
              if (next.keepScreenOn) {
                WakelockPlus.enable();
              } else {
                WakelockPlus.disable();
              }
            } catch (_) {}
            setState(() => _textPages = <String>[]);
          },
        );
      },
    );
  }

  void _openDictionary({String initialWord = ''}) {
    _controller.setMenuVisible(false);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DictionarySheet(
          initialWord: initialWord,
          bgColor: _bgColor,
          textColor: _textColor,
          manager: _dictionaryManager,
        );
      },
    );
  }

  /// 从 contextMenuBuilder 回调查词
  void _lookupSelectedText(String word) {
    _openDictionary(initialWord: word);
  }

  Future<void> _switchAdjacentChapter(
    int offset,
    ReaderJumpTarget target,
  ) async {
    final nextIndex = _controller.chapterIndex + offset;
    if (nextIndex < 0 || nextIndex >= _controller.totalChapters) return;

    _controller.setMenuVisible(false);
    await _navigationController.switchChapter(nextIndex, target: target);
  }

  void _calculatePages(
    double fitWidth,
    double firstPageHeight,
    double normalPageHeight,
  ) {
    if (_controller.content.isEmpty || _controller.isScrollMode) return;

    // 取消之前的后台分页
    _paginateCancelFlag = true;

    final request = ReaderPaginationRequest(
      bookId: widget.detail.book.id,
      chapterIndex: _controller.chapterIndex,
      content: _controller.content,
      fitWidth: fitWidth,
      firstPageHeight: firstPageHeight,
      normalPageHeight: normalPageHeight,
      fontSize: _controller.settings.fontSize,
      lineHeight: _controller.settings.lineHeight,
      letterSpacing: 0.6,
    );

    // 增量分页：先出 5 页，后台补全
    final result = ReaderPaginator.paginateIncremental(
      request,
      chunkSize: 5,
    );

    if (!mounted) return;

    setState(() {
      _textPages = result.firstChunk;
      _paginatingRemaining = !result.remaining.isDone;
    });

    if (result.remaining.isDone) {
      // 内容太短，一次性出完了
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restorePagePositionAfterPaginate();
      });
      return;
    }

    // 后台异步补齐剩余页码
    _paginateCancelFlag = false;
    _paginateRemaining(result.remaining);
  }

  /// 后台逐块补齐分页
  ///
  /// 每个微任务后 yield 给事件循环，确保不阻塞 UI。
  Future<void> _paginateRemaining(
    IncrementalPageIterator iterator,
  ) async {
    final accumulatedPages = <String>[..._textPages];

    while (!iterator.isDone) {
      // 每次微任务只算一个 chunk
      await Future<void>.delayed(const Duration(milliseconds: 1));

      if (!mounted || _paginateCancelFlag) return;

      final chunk = iterator.nextChunk();
      if (chunk.isEmpty) break;

      accumulatedPages.addAll(chunk);

      if (!mounted || _paginateCancelFlag) return;

      setState(() {
        _textPages = List<String>.from(accumulatedPages);
      });
    }

    if (!mounted || _paginateCancelFlag) return;

    setState(() {
      _paginatingRemaining = false;
    });

    // 全部分页完成后再恢复阅读位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePagePositionAfterPaginate();
    });
  }

  Future<void> _restorePagePositionAfterPaginate() async {
    if (_controller.isScrollMode ||
        !_pageController.hasClients ||
        _textPages.isEmpty) {
      return;
    }

    int targetPage = 0;

    if (_navigationController.jumpTarget == ReaderJumpTarget.end) {
      targetPage = _textPages.length - 1;
    } else if (_navigationController.jumpTarget == ReaderJumpTarget.restoreDb) {
      final saved = await _progressService.restoreOffsetForChapter(
        widget.detail.book.id,
        _controller.chapterIndex,
      );

      if (saved != null) {
        final rawPage = _decodePageOffset(saved);
        targetPage = rawPage
            .clamp(0.0, (_textPages.length - 1).toDouble())
            .toInt();
      }
    }

    var targetView = targetPage + 1;
    if (targetView < 1) targetView = 1;
    if (targetView > _textPages.length) targetView = _textPages.length;

    _pageController.jumpToPage(targetView);
    await _saveProgress();
  }

  Widget _buildTopBar() {
    return ReaderTopBar(
      controller: _controller,
      bgColor: _bgColor,
      textColor: _textColor,
      onBack: () => Navigator.pop(context),
      onBookmark: () {
        _controller.setMenuVisible(false);
        _showBookmarkConfirm();
      },
      onDictionary: _openDictionary,
    );
  }

  Widget _buildBottomBar() {
    return ReaderBottomBar(
      controller: _controller,
      bgColor: _bgColor,
      textColor: _textColor,
      onDirectory: _openDirectory,
      onBookmarkList: _openBookmarkList,
      onSearch: _openSearch,
      onDictionary: _openDictionary,
      onPrev: _controller.canGoPrev
          ? () => _switchAdjacentChapter(-1, ReaderJumpTarget.start)
          : null,
      onNext: _controller.canGoNext
          ? () => _switchAdjacentChapter(1, ReaderJumpTarget.start)
          : null,
      onSettings: _openSettings,
    );
  }

  Widget _buildPagedReaderView(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final topPad = MediaQuery.of(context).padding.top;
    final fitWidth = (constraints.maxWidth - 40.0).clamp(200.0, 660.0);
    final paddingTotal = topPad + 8.0 + 8.0;

    final firstTextHeight =
        constraints.maxHeight - paddingTotal - 46.0 - 24.0 - 14.0;
    final normalTextHeight =
        constraints.maxHeight - paddingTotal - 24.0 - 24.0 - 14.0;

    if (fitWidth <= 0 || firstTextHeight <= 0 || normalTextHeight <= 0) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _textColor.withValues(alpha: 0.4),
        ),
      );
    }

    if (fitWidth != _lastFitWidth ||
        normalTextHeight != _lastNormalHeight ||
        _textPages.isEmpty) {
      _lastFitWidth = fitWidth;
      _lastNormalHeight = normalTextHeight;
      _schedulePageRecalc(fitWidth, firstTextHeight, normalTextHeight);
    }

    if (_textPages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _textColor.withValues(alpha: 0.4),
        ),
      );
    }

    return Stack(
      children: [
        ReaderPagedView(
          controller: _controller,
          pageController: _pageController,
          textPages: _textPages,
          settings: _controller.settings,
          textColor: _textColor,
          topPadding: topPad,
          onPageChanged: _onPageChanged,
          onLookupWord: _lookupSelectedText,
        ),
        if (_paginatingRemaining)
          Positioned(
            top: 8.0,
            right: 8.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _bgColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _textColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: _textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '排版中…',
                    style: TextStyle(
                      fontSize: 11,
                      color: _textColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContinuousReaderView(double topPad) {
    return ReaderContinuousView(
      controller: _controller,
      scrollController: _scrollController,
      topPadding: topPad,
      textColor: _textColor,
      onLoadNextChapter: () => _controller.fetchNextScrollChapter(),
      onLookupWord: _lookupSelectedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeAnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bgColor,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              children: [
                // 主内容区
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: _onScreenTap,
                  child: _buildContentArea(),
                ),

                // 顶部阅读进度条
                if (!_controller.loading && !_controller.isError)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopProgressBar(),
                  ),

                // 亮度遮罩叠加层（ brightness 0.2~1.0，越低越暗）
                if (!_controller.loading && !_controller.isError)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black
                            .withValues(alpha: 1.0 - _controller.settings.brightness),
                      ),
                    ),
                  ),

                // 底部页码指示器（翻页模式）
                if (!_controller.loading &&
                    !_controller.isError &&
                    !_controller.isScrollMode &&
                    _showPageIndicator &&
                    _textPages.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildPageIndicator(),
                  ),

                // 切章转场遮罩
                if (_controller.isTransitioning)
                  Positioned.fill(
                    child: _buildChapterTransitionOverlay(),
                  ),

                // 菜单层
                if (_controller.showMenu && !_controller.loading &&
                    !_controller.isError)
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                if (_controller.showMenu && !_controller.loading &&
                    !_controller.isError)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomBar(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 主内容区：loading / error / scroll / paged
  Widget _buildContentArea() {
    if (_controller.loading) return _buildLoadingSkeleton();
    if (_controller.isError) return _buildErrorState();
    if (_controller.isScrollMode) {
      return _buildContinuousReaderView(
        MediaQuery.of(context).padding.top,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildPagedReaderView(context, constraints);
      },
    );
  }

  /// 加载骨架屏（模拟文字占位 + spinner）
  Widget _buildLoadingSkeleton() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题占位
            Container(
              width: 180,
              height: 18,
              decoration: BoxDecoration(
                color: _textColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 28),
            // 文字行占位 ×5
            for (int i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  height: 14,
                  width: 120.0 + (i * 40) % 160,
                  decoration: BoxDecoration(
                    color: _textColor.withValues(
                      alpha: 0.08 + (i % 3) * 0.02,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _textColor.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 错误状态（图标 + 文字 + 重试按钮）
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: _textColor.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              _controller.errorText,
              style: TextStyle(
                color: _textColor.withValues(alpha: 0.65),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => _controller.retry(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部阅读进度条（薄线，显示章节在全书中的位置）
  Widget _buildTopProgressBar() {
    final total = _controller.totalChapters;
    if (total <= 1) return const SizedBox.shrink();

    final current = _controller.chapterIndex;
    final progress = (current + 1) / total;

    return FractionallySizedBox(
      widthFactor: progress.clamp(0.0, 1.0),
      child: Container(
        height: 2,
        color: _textColor.withValues(alpha: 0.30),
      ),
    );
  }

  /// 阅读统计格式化文本
  String _formatReadingStats() {
    final pct = (_controller.chapterProgress * 100).round();
    if (pct <= 0) return '';
    final remaining = _controller.estimatedRemainingText;
    if (remaining.isEmpty) return '已读 $pct%';
    return '已读 $pct% · $remaining';
  }

  /// 底部页码指示器（翻页模式）
  Widget _buildPageIndicator() {
    final totalPages = _textPages.length;
    final pageNo = (_currentViewPage + 1).clamp(1, totalPages);
    final chapterTitle = _controller.currentChapterTitle;
    final statsText = _formatReadingStats();

    return GestureDetector(
      onTap: () {
        _pageIndicatorTimer?.cancel();
        setState(() => _showPageIndicator = false);
      },
      // 水平滑动快速跳页
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        final delta = details.primaryVelocity! < 0 ? 1 : -1;
        final target = (_currentViewPage + delta).clamp(0, totalPages - 1);
        _pageController.jumpToPage(target + 1);
        _currentViewPage = target;
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: _showPageIndicator ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _bgColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _textColor.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：导航 + 页码 + 标题
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 10,
                      color: _textColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '第 $pageNo / $totalPages 页',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textColor.withValues(alpha: 0.85),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (totalPages > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        '· ${(pageNo / totalPages * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: _textColor.withValues(alpha: 0.50),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    Expanded(
                      child: Container(
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _textColor.withValues(alpha: 0.08),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (pageNo / totalPages).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: _textColor.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _textColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: _textColor.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                // 第二行：阅读统计
                if (statsText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      statsText,
                      style: TextStyle(
                        fontSize: 11,
                        color: _textColor.withValues(alpha: 0.45),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChapterTransitionOverlay() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 0.55),
          child: Container(
            color: _bgColor,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _controller.transitionTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textColor.withValues(alpha: 0.7 * value),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: _textColor.withValues(alpha: 0.35 * value),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 词典输入底部面板