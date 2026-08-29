import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'reader/reader_pagination_coordinator.dart';
import 'reader/reader_search_sheet.dart';
import 'reader/reader_settings_sheet.dart';
import 'reader/reader_status_views.dart';
import 'reader/reader_theme.dart';
import 'reader/reader_keyboard_intents.dart';
import 'reader/reader_progress_locator.dart';
import 'reader/reader_top_bar.dart';
import 'reader/reader_volume_key_controller.dart';
import 'reader/reader_wakelock_controller.dart';
import 'reader/reader_debug_log.dart';
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

  // 恢复前闸门：incremental 分页期间，进度恢复尚未完成，任何
  // _saveProgress() 调用都不能写盘，否则会覆盖掉正确的 db 进度。
  // 详见 _calculatePages / _restorePagePositionAfterPaginate。
  bool _pendingRestore = false;

  List<String> _textPages = <String>[];
  double _lastFitWidth = 0.0;
  double _lastNormalHeight = 0.0;

  // 菜单是否可见（用于通知 View 在菜单打开时不重算页高）
  bool _menuVisible = false;

  // 手势追踪：用于区分点击和滑动，避免滑动时误触菜单
  Offset? _pointerDownPos;
  bool _isSwiping = false;
  static const double _tapThreshold = 10.0; // 点击与滑动的位移阈值（像素）

  bool _pageCalcScheduled = false;
  bool _scrollJumpScheduled = false;
  bool _paginatingRemaining = false;

  /// 分页轮次仲裁 + 后台补页节奏。
  ///
  /// 代数计数器、取消标志、刷新节奏都在 [ReaderPaginationCoordinator] 里，
  /// 由 test/novel/reader/reader_pagination_coordinator_test.dart 锁死行为
  /// （含「首帧 + 稳定帧连开两轮导致恢复位置丢失」那个历史 bug 的回归）。
  final ReaderPaginationCoordinator _paginationCoordinator =
      ReaderPaginationCoordinator();

  /// 屏幕常亮策略：进入按持久化设置应用，离开无条件释放。
  final ReaderWakelockController _wakelock = ReaderWakelockController(
    toggle: (enabled) =>
        enabled ? WakelockPlus.enable() : WakelockPlus.disable(),
  );

  /// 音量键翻页：原生拦截标志位活在 Activity 上，离开阅读页必须释放。
  late final ReaderVolumeKeyController _volumeKeys;

  /// 物理键盘焦点。外接键盘 / 平板 / 桌面端翻页用。
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'reader-keyboard');

  /// 处理物理键盘事件。
  ///
  /// 按键映射抽到 [mapReaderKeyIntent]，这里只负责把意图接到已有的
  /// 导航方法上——和点击、音量键共用同一条翻页路径。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final intent = mapReaderKeyIntent(event);
    if (intent == null) return KeyEventResult.ignored;

    // 加载 / 错误态下只放行 dismiss，翻页无意义。
    if ((_controller.loading || _controller.isError) &&
        intent != ReaderKeyIntent.dismiss) {
      return KeyEventResult.ignored;
    }

    final size = MediaQuery.sizeOf(context);

    switch (intent) {
      case ReaderKeyIntent.previousPage:
        _navigationController.goPrevious(viewportHeight: size.height);
      case ReaderKeyIntent.nextPage:
        _navigationController.goNext(viewportHeight: size.height);
      case ReaderKeyIntent.previousChapter:
        if (!_controller.canGoPrev) return KeyEventResult.handled;
        unawaited(_navigationController.switchChapter(
          _controller.chapterIndex - 1,
          target: ReaderJumpTarget.start,
        ));
      case ReaderKeyIntent.nextChapter:
        if (!_controller.canGoNext) return KeyEventResult.handled;
        unawaited(_navigationController.switchChapter(
          _controller.chapterIndex + 1,
          target: ReaderJumpTarget.start,
        ));
      case ReaderKeyIntent.toggleMenu:
        _navigationController.toggleMenu();
      case ReaderKeyIntent.dismiss:
        // 菜单打开时先收菜单，再按才退出——避免一键连退两层。
        if (_navigationController.menuVisible) {
          _navigationController.dismissMenu();
        } else {
          unawaited(Navigator.of(context).maybePop());
        }
      case ReaderKeyIntent.increaseFontSize:
        _nudgeFontSize(1);
      case ReaderKeyIntent.decreaseFontSize:
        _nudgeFontSize(-1);
    }

    // 一律标记 handled：命中的按键不能再冒泡出去，
    // 否则空格 / 方向键会被外层 Scrollable 二次消费导致翻两页。
    return KeyEventResult.handled;
  }

  /// 字号步进，范围与设置面板滑条保持一致（14~30）。
  void _nudgeFontSize(int step) {
    final current = _controller.settings.fontSize;
    final next = (current + step).clamp(14.0, 30.0);
    if (next == current) return;
    unawaited(_controller.updateSettings(
      _controller.settings.copyWith(fontSize: next),
    ));
    // 字号变化必须清分页缓存，否则沿用旧页高会串行/截断。
    if (!_controller.isScrollMode) {
      setState(() => _textPages = <String>[]);
    }
  }

  // 当前分页视图索引
  int _currentViewPage = 0;

  // 分页模式滚动去抖
  Timer? _pagedScrollDebounce;

  // 搜索输入跨次保留（ReaderSearchSheet 每次 dismiss 后 State 销毁，
  // 所以把最后一次搜索词记在父 state 里，下次打开时回填）
  String? _lastSearchQuery;

  /// 内容 + 菜单两个 ChangeNotifier 的合并重建信号
  late final Listenable _rebuildSignal;

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

    // 菜单状态在 _navigationController 上，内容状态在 _controller 上。
    // 两者都要驱动重建，否则点击中央区域切换菜单不会有任何反应。
    // 合并对象只建一次，避免每帧 didUpdateWidget 反复挂/摘监听。
    _rebuildSignal = Listenable.merge([_controller, _navigationController]);

    _volumeKeys = ReaderVolumeKeyController(
      onNavigate: (direction) {
        if (!mounted) return;
        // 菜单打开时音量键先关菜单，避免"看不见内容却在翻页"。
        if (_navigationController.menuVisible) {
          _navigationController.dismissMenu();
          return;
        }
        final viewportHeight = MediaQuery.of(context).size.height;
        switch (direction) {
          case ReaderVolumeKeyDirection.previous:
            _navigationController.goPrevious(viewportHeight: viewportHeight);
            break;
          case ReaderVolumeKeyDirection.next:
            _navigationController.goNext(viewportHeight: viewportHeight);
            break;
        }
      },
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 初始化调试日志
    unawaited(ReaderDebugLog.init());

    unawaited(_controller.bootstrap().then((_) {
      // 常亮开关此前只在设置面板 onSettingsChanged 里生效，
      // 进入阅读页时不会按已持久化的设置应用，
      // 用户开了常亮、退出重进后屏幕照常息屏。
      if (!mounted) return;
      unawaited(_wakelock.apply(_controller.settings.keepScreenOn));
      unawaited(_volumeKeys.attach(
        enabled: _controller.settings.volumeKeyNav,
      ));
    }));
  }

  @override
  void dispose() {
    _paginationCoordinator.cancel();
    // 清理所有 Timer。_pagedScrollDebounce 以前漏了 cancel：它的回调虽有
    // mounted/hasClients 双守卫不会崩，但 Timer 会存活到 dispose 之后才空转一次，
    // 且持有 State 引用妨碍回收。注释说「所有」就得真的是所有。
    _saveDebounce?.cancel();
    _pagedScrollDebounce?.cancel();
    
    // 退出时立即保存进度。关键：使用 _currentViewPage（onPageChanged 已确认的页码），
    // 而不是 _pageController.page（可能还在动画中途、未 settle 到最终值）。
    if (!_controller.isScrollMode && _textPages.isNotEmpty && !_pendingRestore) {
      final pageIdx = _currentViewPage.clamp(0, _textPages.length - 1);
      final charOffset = charOffsetForPage(_textPages, _controller.content, pageIdx);
      final progress = ReadingProgress(
        bookId: widget.detail.book.id,
        chapterIndex: _controller.chapterIndex,
        chapterTitle: _controller.currentChapterTitle,
        scrollOffset: _encodeProgressOffset(pageIdx.toDouble()),
        charOffset: charOffset,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      ReaderDebugLog.log('dispose: SAVING currentViewPage=$_currentViewPage charOffset=$charOffset');
      unawaited(_persistProgress(progress));
    } else if (_controller.isScrollMode) {
      // 滚动模式仍走原逻辑
      unawaited(_saveProgress());
    }

    _scrollController
      ..removeListener(_onProgressChanged)
      ..dispose();
    _pageController.dispose();
    _controller.dispose();
    _navigationController.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 离开阅读页必须释放常亮，否则整个 App 后续页面都不息屏、持续耗电。
    unawaited(_wakelock.release());
    // 同理解除音量键拦截：标志位在 Activity 上，
    // 不释放的话离开阅读页后全 App 都调不了系统音量。
    unawaited(_volumeKeys.release());
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// 当前主题配色。色值本身在 [ReaderPalette]，这里只做取用。
  ReaderPalette get _palette =>
      ReaderPalette.of(_controller.settings.themeMode);

  Color get _bgColor => _palette.background;

  Color get _textColor => _palette.text;

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
    _paginationCoordinator.cancel();
    _pendingRestore = false;
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
    // 分页恢复尚未完成：DB 里的进度可能被增量分页的初始状态（第 1 页）
    // 覆盖，必须跳过。等待 _restorePagePositionAfterPaginate 完成后再写。
    if (_pendingRestore) {
      ReaderDebugLog.log('_saveProgress: SKIPPED (pendingRestore=true)');
      return;
    }
    ReaderDebugLog.log('_saveProgress: START pageController.hasClients=${_pageController.hasClients}, textPages=${_textPages.length}, chapter=${_controller.chapterIndex}');

    // PageView 已经 detach（页面正在销毁 / 还没 attach）时 page 读不到真值，
    // 此时 raw 会退化成 0，把 DB 里正确的进度覆盖成第 1 页。
    // 宁可不写，也不能写错——退出时的保存由 dispose() 用 _currentViewPage 完成。
    if (!_pageController.hasClients) {
      ReaderDebugLog.log('_saveProgress: SKIPPED (pageController has no clients)');
      return;
    }

    double raw = (_pageController.page ?? (_currentViewPage + 1).toDouble()) - 1.0;

    if (_textPages.isNotEmpty) {
      raw = raw.clamp(0.0, (_textPages.length - 1).toDouble());
    } else {
      raw = 0.0;
    }

    // 计算当前页的字符偏移
    final pageIdx = raw.toInt();
    final charOffset = charOffsetForPage(
      _textPages,
      _controller.content,
      pageIdx,
    );

    final nextProgress = ReadingProgress(
      bookId: widget.detail.book.id,
      chapterIndex: _controller.chapterIndex,
      chapterTitle: _controller.currentChapterTitle,
      scrollOffset: _encodeProgressOffset(raw),
      charOffset: charOffset,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    ReaderDebugLog.log('_saveProgress: SAVING page=${raw.toStringAsFixed(2)} charOffset=$charOffset progress=$nextProgress');
    await _persistProgress(nextProgress);
    ReaderDebugLog.log('_saveProgress: DONE');
  }

  void _updateScrollProgressAndDB() {
    if (!_controller.isScrollMode || _controller.scrollItems.isEmpty) return;
    if (!_scrollController.hasClients || !mounted) return;

    // 使用 pageStorageKey 或简单的 offset 计算，避免每帧遍历所有章节
    final currentOffset = _scrollController.offset;

    // 简化：只检查当前可见章节（通过 scrollController.position）
    // 避免遍历所有 scrollItems 做 hit-test
    if (_controller.chapterIndex < _controller.scrollItems.length) {
      // 使用一个简单的估算：根据当前滚动位置判断是否需要切换章节
      // 这里简化处理，避免复杂的 RenderObject 查询
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), () {
      final activeIdx = _controller.chapterIndex;
      if (activeIdx >= 0 && activeIdx < widget.detail.chapters.length) {
        final nextProgress = ReadingProgress(
          bookId: widget.detail.book.id,
          chapterIndex: activeIdx,
          chapterTitle: widget.detail.chapters[activeIdx].title,
          scrollOffset: currentOffset,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        // 添加超时保护，避免丢失进度
        // 失败/超时时暴露状态，允许 UI 提示用户（如 toast）
        unawaited(
          _persistProgress(nextProgress)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw TimeoutException(
                  '进度保存超时',
                  const Duration(seconds: 5),
                ),
              )
              .catchError((Object e, StackTrace st) {
                // 在 controller 上暴露最后一次保存错误，UI 可按需显示提示
                _controller.lastSaveError = e;
                debugPrint('进度保存失败: $e');
                return Future<void>.value();
              }),
        );
      }
    });
  }

  void _onProgressChanged() {
    // 菜单开关触发，更新菜单状态并重建（仅 topBar/bottomBar 可见性变化）
    final wasMenuVisible = _menuVisible;
    _menuVisible = _navigationController.menuVisible;
    if (wasMenuVisible != _menuVisible && mounted) {
      // 仅更新 topBar/bottomBar 可见性，PageView 保持原位，不重算页高
      setState(() {});
    }

    if (_controller.isScrollMode) {
      _updateScrollProgressAndDB();
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), _saveProgress);

    // 分页模式：页码真正变化才重建（注释原本这么说，代码却无条件 setState，
    // 于是滑动时每 100ms 重建一次整页）。翻页本身已由 _onPageChanged 处理，
    // 这里只需在页码漂移时补一次。
    _pagedScrollDebounce?.cancel();
    _pagedScrollDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_pageController.hasClients) return;
      final raw = _pageController.page;
      if (raw == null) return;
      final viewPage = raw.round() - 1;
      if (viewPage == _currentViewPage) return;
      setState(() => _currentViewPage = viewPage);
    });
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

  void _changeMode(bool isScroll) {
    if (_controller.isScrollMode == isScroll) return;

    _resetPagedState(ReaderJumpTarget.start);
    _controller.setScrollMode(isScroll);

    if (isScroll) {
      _scheduleScrollJump();
    }
  }

  Future<void> _openDirectory() async {
    _navigationController.dismissMenu();

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
    _navigationController.dismissMenu();

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
    _navigationController.dismissMenu();

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      builder: (context) {
        return ReaderSearchSheet(
          controller: _controller,
          bgColor: _bgColor,
          textColor: _textColor,
          initialQuery: _lastSearchQuery,
          onQueryUpdated: (q) => setState(() => _lastSearchQuery = q),
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
    _navigationController.dismissMenu();

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
            // 阅读时常亮控制
            unawaited(_wakelock.apply(next.keepScreenOn));
            // 音量键翻页开关
            unawaited(_volumeKeys.apply(next.volumeKeyNav));
            // 只清空分页缓存，不重建整个页面
            if (!_controller.isScrollMode) {
              setState(() => _textPages = <String>[]);
            }
          },
        );
      },
    );
  }

  void _openDictionary({String initialWord = ''}) {
    _navigationController.dismissMenu();

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

    _navigationController.dismissMenu();
    await _navigationController.switchChapter(nextIndex, target: target);
  }

  void _calculatePages(
    double fitWidth,
    double firstPageHeight,
    double normalPageHeight,
  ) {
    if (_controller.content.isEmpty || _controller.isScrollMode) return;

    // 取消之前的后台分页，并开启新一轮（代号自增让过期轮次自行退出）
    final generation = _paginationCoordinator.beginRound();

    final request = ReaderPaginationRequest(
      bookId: widget.detail.book.id,
      chapterIndex: _controller.chapterIndex,
      content: _controller.content,
      fitWidth: fitWidth,
      firstPageHeight: firstPageHeight,
      normalPageHeight: normalPageHeight,
      fontSize: _controller.settings.fontSize,
      lineHeight: _controller.settings.lineHeight,
      // 必须与 ReaderPagedView 渲染时的 TextStyle 完全一致，
      // 否则测量宽度与实际排版不符，页底文字会被裁掉。
      letterSpacing: _controller.settings.letterSpacing + 0.6,
      fontFamily: _controller.settings.fontFamily,
    );

    // 增量分页：先出 5 页，后台补全
    final result = ReaderPaginator.paginateIncremental(
      request,
      chunkSize: 5,
    );

    if (!mounted) return;

    ReaderDebugLog.log('_calculatePages: START content.length=${_controller.content.length} fitWidth=$fitWidth firstHeight=$firstPageHeight normalHeight=$normalPageHeight pagesCount=${result.firstChunk.length} isDone=${result.remaining.isDone}');
    setState(() {
      _textPages = result.firstChunk;
      _paginatingRemaining = !result.remaining.isDone;
      _pendingRestore = true;
    });

    if (result.remaining.isDone) {
      // 内容太短，一次性出完了。这条早返回路径也必须关掉闸门，
      // 否则 _pendingRestore 永远为 true，此后所有进度都存不下来。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_paginationCoordinator.isCurrent(generation)) return;
        await _restorePagePositionAfterPaginate();
        if (!mounted) return;
        setState(() => _pendingRestore = false);
      });
      return;
    }

    // 后台异步补齐剩余页码
    _paginationCoordinator.armBackgroundRound();
    unawaited(_paginateRemaining(result.remaining, generation));
  }

  /// 后台逐块补齐分页
  ///
  /// 每个微任务后 yield 给事件循环，确保不阻塞 UI。
  Future<void> _paginateRemaining(
    IncrementalPageIterator iterator,
    int generation,
  ) async {
    // 循环、代数仲裁、刷新节奏都在协调器里；这里只负责把结果落到
    // State 上，以及做 Flutter 特有的收尾（postFrameCallback + 恢复位置）。
    await _paginationCoordinator.drain(
      source: ReaderChunkSource.fromIterator(iterator),
      generation: generation,
      initialPages: _textPages,
      mounted: () => mounted,
      onFlush: (pages) {
        setState(() => _textPages = List<String>.from(pages));
      },
      onComplete: (pages) {
        setState(() {
          _textPages = List<String>.from(pages);
          _paginatingRemaining = false;
        });

        // 全部分页完成后再恢复阅读位置
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!_paginationCoordinator.isCurrent(generation)) return;
          await _restorePagePositionAfterPaginate();
          // 恢复完成，闸门关闭，后续 _saveProgress 可以正常写盘。
          // 必须 await 恢复再关闸门：jumpToPage 会同步触发 _onProgressChanged，
          // 若提前关闸，320ms debounce 后存下的仍是旧页码。
          if (!mounted) return;
          setState(() => _pendingRestore = false);
        });
      },
    );
  }

  Future<void> _restorePagePositionAfterPaginate() async {
    ReaderDebugLog.log('_restorePagePositionAfterPaginate: START isScrollMode=${_controller.isScrollMode} hasClients=${_pageController.hasClients} textPages=${_textPages.length} jumpTarget=${_navigationController.jumpTarget} pendingRestore=$_pendingRestore');
    if (_controller.isScrollMode ||
        !_pageController.hasClients ||
        _textPages.isEmpty) {
      ReaderDebugLog.log('_restorePagePositionAfterPaginate: EARLY RETURN (isScrollMode=${_controller.isScrollMode} hasClients=${_pageController.hasClients} textPagesEmpty=${_textPages.isEmpty})');
      return;
    }

    int targetPage = 0;

    if (_navigationController.jumpTarget == ReaderJumpTarget.end) {
      targetPage = _textPages.length - 1;
      ReaderDebugLog.log('_restorePagePositionAfterPaginate: using END target, targetPage=$targetPage');
    } else if (_navigationController.jumpTarget == ReaderJumpTarget.restoreDb) {
      // 优先用字符偏移定位（排版无关）
      ReaderDebugLog.log('_restorePagePositionAfterPaginate: restoring from DB for chapter=${_controller.chapterIndex}');
      final charOff = await _progressService.restoreCharOffsetForChapter(
        widget.detail.book.id,
        _controller.chapterIndex,
      );
      ReaderDebugLog.log('_restorePagePositionAfterPaginate: charOff=$charOff');

      if (charOff != null) {
        final offsets = computePageStartOffsets(_textPages, _controller.content);
        ReaderDebugLog.log('_restorePagePositionAfterPaginate: computePageStartOffsets returned ${offsets.length} offsets');
        targetPage = locatePageForCharOffset(offsets, charOff);
        ReaderDebugLog.log('_restorePagePositionAfterPaginate: located page=$targetPage for charOff=$charOff');
      } else {
        // 降级到旧逻辑：页索引
        ReaderDebugLog.log('_restorePagePositionAfterPaginate: charOff is null, falling back to scrollOffset');
        final saved = await _progressService.restoreOffsetForChapter(
          widget.detail.book.id,
          _controller.chapterIndex,
        );
        ReaderDebugLog.log('_restorePagePositionAfterPaginate: saved=$saved');

        if (saved != null) {
          final rawPage = _decodePageOffset(saved);
          targetPage = rawPage
              .clamp(0.0, (_textPages.length - 1).toDouble())
              .toInt();
          ReaderDebugLog.log('_restorePagePositionAfterPaginate: decoded page=$rawPage -> targetPage=$targetPage');
        }
      }
    }

    var targetView = targetPage + 1;
    if (targetView < 1) targetView = 1;
    if (targetView > _textPages.length) targetView = _textPages.length;

    ReaderDebugLog.log('_restorePagePositionAfterPaginate: jumping to view=$targetView (page=$targetPage)');
    _pageController.jumpToPage(targetView);
    await _saveProgress();
  }

  Widget _buildTopBar() {
    return ReaderTopBar(
      bookTitle: _controller.bookTitle,
      chapterTitle: _controller.currentChapterTitle,
      hasBookmark: _controller.hasBookmarkForCurrent,
      bgColor: _bgColor,
      textColor: _textColor,
      onBack: () => Navigator.pop(context),
      onBookmark: () {
        _navigationController.dismissMenu();
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
          menuVisible: _navigationController.menuVisible,
        ),
        if (_paginatingRemaining)
          Positioned(
            top: 8.0,
            right: 8.0,
            child: ReaderPaginatingBadge(
              bgColor: _bgColor,
              textColor: _textColor,
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
      menuVisible: _navigationController.menuVisible,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeAnimatedBuilder(
      animation: _rebuildSignal,
      builder: (context, _) {
        return Focus(
          focusNode: _keyboardFocus,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
          backgroundColor: _bgColor,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              children: [
                // 主内容区。
                //
                // 用 Listener 而非 GestureDetector：PageView 内部的滚动识别器会
                // 在手势竞技场中与 GestureDetector.onTapUp 竞争，导致点击时灵时不灵。
                // Listener（translucent 行为）无论内部 widget 是否消费手势都能收到
                // 指针事件，保证 menuVisible == false 时菜单切换始终可靠触发。
                Listener(
                  onPointerDown: (details) {
                    _pointerDownPos = details.localPosition;
                    _isSwiping = false;
                  },
                  onPointerMove: (details) {
                    // 检测是否发生位移，超过阈值认为是滑动
                    if (_pointerDownPos != null) {
                      final dx = (details.localPosition.dx - _pointerDownPos!.dx).abs();
                      final dy = (details.localPosition.dy - _pointerDownPos!.dy).abs();
                      if (dx > _tapThreshold || dy > _tapThreshold) {
                        _isSwiping = true;
                      }
                    }
                  },
                  onPointerUp: (details) {
                    if (_navigationController.menuVisible) return;
                    // 滑动时不触发菜单（上一页/下一页由 PageView 内部处理）
                    if (_isSwiping) return;
                    unawaited(_navigationController.handleScreenTap(
                      TapUpDetails(
                        localPosition: details.localPosition,
                        globalPosition: details.position,
                        kind: PointerDeviceKind.touch,
                      ),
                      context,
                    ));
                  },
                  child: IgnorePointer(
                    ignoring: _navigationController.menuVisible,
                    child: _buildContentArea(),
                  ),
                ),

                // 菜单遮罩层：菜单打开时铺满全屏，独占关闭手势。
                // 点击正文区域即关闭菜单（通过 _navigationController.handleScreenTap）。
                if (_navigationController.menuVisible &&
                    !_controller.loading &&
                    !_controller.isError)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _navigationController.dismissMenu,
                      child: const SizedBox.expand(),
                    ),
                  ),

                // 亮度遮罩叠加层（brightness 0.2~1.0，越低越暗）。
                // 必须排在顶部进度条之前：否则遮罩会把进度条一起压暗，
                // 亮度调到最低时进度条几乎看不见。
                if (!_controller.loading &&
                    !_controller.isError &&
                    _controller.settings.brightness < 1.0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(
                          alpha: 1.0 - _controller.settings.brightness,
                        ),
                      ),
                    ),
                  ),

                // 顶部阅读进度条（不受亮度遮罩影响）。
                //
                // 菜单展开时顶栏是不透明的整条，会把 top:0 的进度条完全盖住，
                // 所以这时把进度条下移到顶栏下沿；菜单收起时仍贴屏幕顶边。
                if (!_controller.loading && !_controller.isError)
                  Positioned(
                    top: _navigationController.menuVisible
                        ? MediaQuery.of(context).padding.top +
                              ReaderTopBar.contentHeight
                        : 0,
                    left: 0,
                    right: 0,
                    child: _buildTopProgressBar(),
                  ),

                // 切章转场遮罩
                if (_controller.isTransitioning)
                  Positioned.fill(
                    child: _buildChapterTransitionOverlay(),
                  ),

                // 菜单层
                if (_navigationController.menuVisible &&
                    !_controller.loading &&
                    !_controller.isError)
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                if (_navigationController.menuVisible &&
                    !_controller.loading &&
                    !_controller.isError)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomBar(),
                  ),
                
                // 调试日志按钮（橙色虫子图标）
                ReaderDebugLogButton(textColor: _textColor),
              ],
            ),
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
    return ReaderLoadingSkeleton(textColor: _textColor);
  }

  /// 错误状态（图标 + 文字 + 重试按钮）
  Widget _buildErrorState() {
    return ReaderErrorState(
      textColor: _textColor,
      message: _controller.errorText,
      onRetry: () => _controller.retry(),
    );
  }

  /// 顶部阅读进度条（薄线，显示章节在全书中的位置）
  Widget _buildTopProgressBar() {
    return ReaderTopProgressBar(
      textColor: _textColor,
      chapterIndex: _controller.chapterIndex,
      totalChapters: _controller.totalChapters,
    );
  }

  Widget _buildChapterTransitionOverlay() {
    return ReaderChapterTransitionOverlay(
      bgColor: _bgColor,
      textColor: _textColor,
      title: _controller.transitionTitle,
      onCancel: () {
        // 允许用户在切章加载期间点击遮罩取消（返回上一章）
        if (_controller.isTransitioning) {
          _controller.cancelTransition();
        }
      },
    );
  }
}

/// 词典输入底部面板