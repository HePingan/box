import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import 'reader/reader_bottom_bar.dart';
import 'reader/reader_controller.dart';
import 'reader/reader_continuous_view.dart';
import 'reader/reader_directory_sheet.dart';
import 'reader/reader_navigation_controller.dart';
import 'reader/reader_paginator.dart';
import 'reader/reader_paged_view.dart';
import 'reader/reader_progress_service.dart';
import 'reader/reader_settings_sheet.dart';
import 'reader/reader_top_bar.dart';

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

  Timer? _saveDebounce;

  List<String> _textPages = <String>[];
  double _lastFitWidth = 0.0;
  double _lastNormalHeight = 0.0;

  bool _pageCalcScheduled = false;
  bool _scrollJumpScheduled = false;

  @override
  void initState() {
    super.initState();

    _controller = ReaderController(
      detail: widget.detail,
      initialChapterIndex: widget.initialChapterIndex,
    );

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
    _saveDebounce?.cancel();
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
        return const Color(0xFFCBE5D2);
      case ReaderThemeMode.paper:
        return const Color(0xFFF1E9CE);
      case ReaderThemeMode.dark:
        return const Color(0xFF141414);
    }
  }

  Color get _textColor {
    switch (_controller.settings.themeMode) {
      case ReaderThemeMode.dark:
        return const Color(0xFF9A9A9A);
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
    setState(() {
      _textPages = <String>[];
      _lastFitWidth = 0.0;
      _lastNormalHeight = 0.0;
    });
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

    _scrollController.jumpTo(
      saved == null ? 0.0 : _decodeScrollOffset(saved),
    );
  }

  void _onPageChanged(int viewIndex) {
    if (_controller.isScrollMode || _textPages.isEmpty) return;

    final tail = _textPages.length + 1;

    if (viewIndex == 0 || viewIndex == tail) {
      unawaited(_navigationController.handlePageChanged(viewIndex));
      return;
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
            setState(() => _textPages = <String>[]);
          },
        );
      },
    );
  }

  Future<void> _switchAdjacentChapter(int offset, ReaderJumpTarget target) async {
    final nextIndex = _controller.chapterIndex + offset;
    if (nextIndex < 0 || nextIndex >= _controller.totalChapters) return;

    _controller.setMenuVisible(false);
    await _navigationController.switchChapter(
      nextIndex,
      target: target,
    );
  }

  void _calculatePages(
    double fitWidth,
    double firstPageHeight,
    double normalPageHeight,
  ) {
    if (_controller.content.isEmpty || _controller.isScrollMode) return;

    final pages = ReaderPaginator.paginate(
      ReaderPaginationRequest(
        bookId: widget.detail.book.id,
        chapterIndex: _controller.chapterIndex,
        content: _controller.content,
        fitWidth: fitWidth,
        firstPageHeight: firstPageHeight,
        normalPageHeight: normalPageHeight,
        fontSize: _controller.settings.fontSize,
        lineHeight: _controller.settings.lineHeight,
        letterSpacing: 0.6,
      ),
    );

    if (!mounted) return;

    setState(() => _textPages = pages);

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
    );
  }

  Widget _buildBottomBar() {
    return ReaderBottomBar(
      controller: _controller,
      bgColor: _bgColor,
      textColor: _textColor,
      onDirectory: _openDirectory,
      onPrev: _controller.canGoPrev
          ? () => _switchAdjacentChapter(-1, ReaderJumpTarget.start)
          : null,
      onNext: _controller.canGoNext
          ? () => _switchAdjacentChapter(1, ReaderJumpTarget.start)
          : null,
      onSettings: _openSettings,
    );
  }

  Widget _buildPagedReaderView(BuildContext context, BoxConstraints constraints) {
    final topPad = MediaQuery.of(context).padding.top;
    final fitWidth = constraints.maxWidth - 40.0;
    final paddingTotal = topPad + 8.0 + 8.0;

    final firstTextHeight =
        constraints.maxHeight - paddingTotal - 46.0 - 24.0 - 14.0;
    final normalTextHeight =
        constraints.maxHeight - paddingTotal - 24.0 - 24.0 - 14.0;

    if (fitWidth <= 0 || firstTextHeight <= 0 || normalTextHeight <= 0) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _textColor.withOpacity(0.4),
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
          color: _textColor.withOpacity(0.4),
        ),
      );
    }

    return ReaderPagedView(
      controller: _controller,
      pageController: _pageController,
      textPages: _textPages,
      settings: _controller.settings,
      textColor: _textColor,
      topPadding: topPad,
      onPageChanged: _onPageChanged,
    );
  }

  Widget _buildContinuousReaderView(double topPad) {
    return ReaderContinuousView(
      controller: _controller,
      scrollController: _scrollController,
      topPadding: topPad,
      textColor: _textColor,
      onLoadNextChapter: () => _controller.fetchNextScrollChapter(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bgColor,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onScreenTap,
                  child: _controller.loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: _textColor.withOpacity(0.5),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '正在铺排...',
                                style: TextStyle(
                                  color: _textColor.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _controller.isError
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _controller.errorText,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : _controller.isScrollMode
                              ? _buildContinuousReaderView(
                                  MediaQuery.of(context).padding.top,
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    return _buildPagedReaderView(
                                      context,
                                      constraints,
                                    );
                                  },
                                ),
                ),
                if (_controller.showMenu)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopBar(),
                  ),
                if (_controller.showMenu)
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
}