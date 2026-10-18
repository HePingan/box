part of './comic_online_page.dart';

// ──────────────────────────────────────────────────────────────
// 阅读器数据簇：开话 / 取图 / 进度 / 预取 / 接下一话 / 阅读列表 / 调暗与翻页偏好。
// on 类型是主文件里的 `_ComicOnlinePageStateBase`，所以私有字段
// （`_images` / `_chapter` …）与 `setState` 照旧可用，行为零变化。
// ──────────────────────────────────────────────────────────────

mixin _ComicReaderMixin on _ComicOnlinePageStateBase {
  /// 点提示：直接切成竖向连续（用户说的"我还是喜欢上下滑动"）。
  Future<void> _useVerticalScroll() async {
    setState(() {
      _pageTurn = false;
      _showPageTurnHint = false;
    });
    try {
      await _prefs.setPageTurn(false);
    } catch (_) {
      // 记不住不算错：这次先按用户点的显示。
    }
    await _markPageTurnHintSeen();
  }

  /// 关掉提示（包括"我自己切过了，别再提"）。
  Future<void> _markPageTurnHintSeen() async {
    _pageTurnHintSeen = true;
    if (_showPageTurnHint) setState(() => _showPageTurnHint = false);
    try {
      await _prefs.setPageTurnHintSeen();
    } catch (_) {
      // 记不住不算错：下次进来会再提一次。
    }
  }

  /// 改压暗档位。界面立刻变（这是手感），写盘在手松开之后（拖动里每帧写盘是白花钱）。
  void _setDim(double value, {bool notify = true}) {
    final next = value.clamp(0.0, ComicReaderPrefs.maxDim).toDouble();
    if (next == _dim) return;
    setState(() {
      _dim = next;
      if (notify) {
        _dimHud = '亮度 ${(next * 100 / ComicReaderPrefs.maxDim).round()}%';
      }
    });
    if (notify) _scheduleDimHudHide();
  }

  void _scheduleDimHudHide() {
    _dimHudTimer?.cancel();
    _dimHudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _dimHud = '');
    });
  }

  Future<void> _saveDim() async {
    try {
      await _prefs.setDimLevel(_dim);
    } catch (_) {
      // 记不住不算错：这次先按用户调的显示。
    }
  }

  /// 「亮度」面板：滑块从左到右 = 从原样到压到最暗。
  ///
  /// 为什么面板 + 手势两条路都要：页漫里"左半屏上下滑"很顺手，但条漫的上下滑是滚动、
  /// 抢不得，所以面板那条路必须留着（不然条漫就没法调了）。
  Future<void> _openDimSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.brightness_6_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '画面亮度（压暗一层，不动系统亮度）',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
                Slider(
                  value: _dim,
                  max: ComicReaderPrefs.maxDim,
                  divisions: 16,
                  label: '${(_dim * 100 / ComicReaderPrefs.maxDim).round()}%',
                  onChanged: (v) {
                    _setDim(v);
                    setSheetState(() {});
                  },
                  onChangeEnd: (_) => unawaited(_saveDim()),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        _setDim(0);
                        setSheetState(() {});
                        unawaited(_saveDim());
                      },
                      child: const Text('恢复最亮'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        unawaited(_saveDim());
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('好'),
                    ),
                  ],
                ),
                const Divider(height: 1),
                // 自动加载下一话：用户点名要的（2026-10-02「增加一个自动加载下一话」），
                // 默认开；做成开关是因为它要花流量、还会把"读到哪了"往前推。
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoNext,
                  title: const Text('自动加载下一话'),
                  subtitle: const Text('滚到本话最后一张，自动把下一话接上来（页漫：翻到最后再往后 = 进下一话）'),
                  onChanged: (v) {
                    setState(() => _autoNext = v);
                    setSheetState(() {});
                    unawaited(_prefs.setAutoNextChapter(v));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 切换翻页方式（记下来，下次进来还是这个）。
  Future<void> _togglePageTurn() async {
    final next = !_pageTurn;
    setState(() {
      _pageTurn = next;
      // 切到左右翻页时，正好把"想上下滑就点这里"摆出来（只在那次提示还没看过时）。
      _showPageTurnHint = next && !_pageTurnHintSeen;
    });
    try {
      await _prefs.setPageTurn(next);
    } catch (_) {
      // 记不住不算错：这次先按用户点的显示，下次进来会回到默认。
    }
  }

  Future<void> _openChapter(ComicChapterRef chapter, {int atIndex = 0}) async {
    // 离线库预热一次（把根目录解析出来）：之后每张图都能**同步**问"本机有没有"。
    // **不 await**：预热是加速用的，渲染与取图都不该等它（真读不到时走下面的兜底）。
    unawaited(_offline.warmUp());

    // 进阅读要记一层（返回能退回详情）。层级只看**进来时**那一态：逐批显示会先把
    // `_mode` 改成阅读，之后再判就会漏记 —— 那样在阅读里按返回会直接退出本页。
    final from = _mode;
    var levelAdded = false;

    void enterReader(List<String> images, {required bool partial}) {
      if (!mounted) return;
      setState(() {
        // 换话就把自动接上来的那几话丢掉：新的一话要接的是**它自己的**下一话，
        // 而且"哪些话已经接过了"也得跟着清空（否则接话去重会误判）。
        if (_chapter?.url != chapter.url) {
          _appended = const [];
          _appendError = '';
        }
        _chapter = chapter;
        _images = images;
        if (!levelAdded) {
          if (from != _Mode.reader) _levels.add(from);
          levelAdded = true;
        }
        _setMode(_Mode.reader);
        _imagesStreaming = partial;
        if (!partial) {
          _imageIndex = atIndex.clamp(
            0,
            images.isEmpty ? 0 : images.length - 1,
          );
        } else if (_imageIndex >= images.length) {
          // 逐批显示时，上一话留下的页码可能超出这一批的张数（PageView 页码越界会直接抛）。
          // 先收到这批的范围内；整话取完那一下再按 atIndex 定位。
          _imageIndex = images.isEmpty ? 0 : images.length - 1;
        }
      });
      // 整话取完（不是半截）时，给控制栏一个"几秒后自己收起"的计时。
      if (!partial) _scheduleChromeHide();
    }

    await _run(() async {
      final images = await _imagesFor(
        chapter,
        // 取到一批就先显示出来：一整话实测 209 张、要 21 次往返，等全取完再显示
        // 用户看到的就是"一直转圈"（2026-10-01 报的）。
        onPartial: (partial) {
          // 取图是异步的：用户可能已经退出这一页（onPartial 挂在 await 之后，
          // 仓库里那条 lint 就是钉这个的）。
          if (!mounted) return;
          if (partial.isEmpty) return;
          if (partial.length < _images.length) return; // 只有变多了才刷新
          enterReader(partial, partial: true);
          setState(
            () =>
                _busyLabel = '正在取「${chapter.title}」的图…已取到 ${partial.length} 张',
          );
        },
      );
      enterReader(images, partial: false);
      final book = _book;
      if (book != null) {
        // 一话很短（一两张图）时不会触发翻页回调 —— 进来就先判一次要不要预取下一话。
        _maybePrefetchNext(book, chapter, _imageIndex);
        // 进度存不上不该影响看书（不弹错、不中断）。
        try {
          await _progress.save(
            ComicOnlineProgress(
              bookUrl: book.bookUrl,
              chapterUrl: chapter.url,
              chapterTitle: chapter.title,
              index: _imageIndex,
            ),
          );
        } catch (_) {}
      }
      _jumpTo(_imageIndex);
    }, '正在取「${chapter.title}」的图…（整话要分批取，取到一批就先显示）');
  }

  /// 取一话的图片地址：**先要点站**；点不上就退回离线清单里那份（下过的话照样读）。
  Future<List<String>> _imagesFor(
    ComicChapterRef chapter, {
    void Function(List<String> partial)? onPartial,
  }) async {
    try {
      return await _service.chapterImages(chapter.url, onPartial: onPartial);
    } catch (e) {
      final offline = await _offlineImages(chapter);
      if (offline == null || offline.isEmpty) rethrow;
      if (mounted) {
        setState(() => _offlineNote = '离线模式：站点没连上，读的是本机下载的这一话');
      }
      return offline;
    }
  }

  /// 离线清单里这一话的图片地址（没下过就是 null）。
  Future<List<String>?> _offlineImages(ComicChapterRef chapter) async {
    final book = _book;
    if (book == null) return null;
    if (_offline.readyRoot == null) return null;
    try {
      final saved = await _offline.loadBook(book.bookUrl);
      for (final c in saved?.chapters ?? const <ComicOfflineChapter>[]) {
        if (c.url == chapter.url && c.images.isNotEmpty) return c.images;
      }
    } catch (_) {
      // 读离线清单失败就当没下过（不能因此把联网那条路也堵死）。
    }
    return null;
  }

  /// 进度随手记；失败不影响阅读（不弹错、不中断，下次再存）。
  void _saveProgress(int index) {
    final book = _book;
    // 进度要落在**这一张所属的那一话**上，而且是"本话第几张"：
    // 自动接话之后 index 是整条列表里的位置，直接存会把下一话的位置记成当前话的。
    final item = _itemAt(index);
    final chapter = item?.chapter ?? _chapter;
    final inChapter = item?.indexInChapter ?? index;
    if (book == null || chapter == null) return;
    _progress
        .save(
          ComicOnlineProgress(
            bookUrl: book.bookUrl,
            chapterUrl: chapter.url,
            chapterTitle: chapter.title,
            index: inChapter,
          ),
        )
        .catchError((_) {});
    unawaited(_syncSoon());
    _maybePrefetchNext(book, chapter, inChapter);
  }

  /// 快读到本话末尾时，顺手把**下一话**开头几张图取回来缓存。
  ///
  /// 触发点就挂在进度上报上（两种翻页模式都走这里），省得多处各挂一次。
  /// 只认"还剩 2 张以内"：早于这个点去取，很可能用户下一话根本不看，白费流量。
  void _maybePrefetchNext(
    ComicBookDetail book,
    ComicChapterRef chapter,
    int index,
  ) {
    if (_images.isEmpty) return;
    if (_images.length - index > _kPrefetchTriggerPages) return;
    final i = book.chapters.indexWhere((c) => c.url == chapter.url);
    if (i < 0) return;
    // 预取本身不 await：它抢的是"用户在读最后几页"这段时间，不能挡住翻页。
    unawaited(_prefetcher.prefetchNext(book.chapters, i));
  }

  void _jumpTo(int index) {
    if (_images.isEmpty) return;
    if (_pageTurn && _pageController.hasClients) {
      _pageController.jumpToPage(index);
      setState(() => _imageIndex = index);
      return;
    }
    if (!_scrollController.hasClients) return;
    // 每张都按"屏宽等比"显示，高度要靠布局算；这里用按张滚动的稳妥做法。
    _scrollController.jumpTo(0);
    setState(() => _imageIndex = index);
  }

  /// 阅读时按屏幕宽度解码（物理像素）。
  ///
  /// 放大查看（`_ComicZoomView`）**不要用**这个值 —— 那条路要原图清晰度。
  int _readerDecodeWidth() {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return 1080;
    final w = (mq.size.width * mq.devicePixelRatio).round();
    // 分屏/小窗时别解得太小（低于 720 宽会明显糊）。
    return w < 720 ? 720 : w;
  }

  /// 显示用的**整条列表**：当前话的图 + 自动接上来的那几话的图。
  ///
  /// 每一项都自带"我属于哪一话、是本话第几张"—— 页码、进度、离线取图、
  /// 章节分隔都靠它（自动接话之后，"第几张"必须按**本话**算，不能按整条算）。
  List<_ReaderItem> get _flatItems {
    final out = <_ReaderItem>[];
    final chapter = _chapter;
    if (chapter != null) {
      for (var i = 0; i < _images.length; i++) {
        out.add(
          _ReaderItem(
            url: _images[i],
            chapter: chapter,
            indexInChapter: i,
            chapterImageCount: _images.length,
            chapterStart: i == 0,
          ),
        );
      }
    }
    for (final a in _appended) {
      for (var i = 0; i < a.images.length; i++) {
        out.add(
          _ReaderItem(
            url: a.images[i],
            chapter: a.chapter,
            indexInChapter: i,
            chapterImageCount: a.images.length,
            chapterStart: i == 0,
          ),
        );
      }
    }
    return out;
  }

  int get _flatCount => _images.length + _appendedImages;

  /// 已经自动接上来多少张图（上限按张数算，见 `comic_auto_append.dart`）。
  int get _appendedImages =>
      _appended.fold<int>(0, (s, a) => s + a.images.length);

  /// 眼下这一张属于哪一话。
  ///
  /// 自动接过话之后 `_chapter`（"进来的那一话"）不再等于"正在读的那一话"：
  /// 页码文案、顶栏标题、上一话/下一话都得看这个，不能再看 `_chapter`。
  ComicChapterRef? get _activeChapter =>
      _itemAt(_imageIndex)?.chapter ?? _chapter;

  /// 快读到本话末尾时把下一话接上来（竖向连续）。
  ///
  /// 为什么要"接成一整条"而不是读完自动跳转：竖向连续里用户的手一直在往下滑，
  /// 到末尾突然整屏换一话，会以为滑错了；接在下面接着滑才顺（2026-10-02 用户
  /// 「增加一个自动加载下一话」）。
  Future<void> _appendNext() async {
    if (!_autoNext || _appending) return;
    // 上限按**张数**：短话能多接几话，长话不会一次接进来几百张（规则见 comic_auto_append.dart）。
    if (!canAutoAppendMore(_appendedImages)) return;
    final next = _neighborFrom(_activeChapter, 1);
    if (next == null) return; // 已经是最后一话
    if (_appended.any((a) => a.chapter.url == next.url)) return;
    setState(() {
      _appending = true;
      _appendError = '';
    });
    try {
      // 逐批接：一话实测 209 张、要 21 次往返。等整话取完再插进去，用户滑到底
      // 会先干等几秒（本话取图踩过同一个坑：整话取完再显示 = 一直转圈）。
      var got = 0;
      final images = await _imagesFor(
        next,
        onPartial: (partial) {
          if (!mounted || partial.isEmpty) return;
          if (partial.length <= got) return; // 只有变多了才刷新
          got = partial.length;
          setState(() {
            // 按话名去重后再拼：这样"换过话 / 被清空"也不会把旧的那份又加回来。
            _appended = [
              ..._appended.where((a) => a.chapter.url != next.url),
              _AppendedChapter(chapter: next, images: partial),
            ];
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _appended = [
          ..._appended.where((a) => a.chapter.url != next.url),
          _AppendedChapter(chapter: next, images: images),
        ];
      });
    } catch (e) {
      // 接不上不该打断正在读的这一话：把原因写进末尾那条分隔里。
      if (!mounted) return;
      setState(() => _appendError = '「${next.title}」没取到：$e');
    } finally {
      if (mounted) setState(() => _appending = false);
    }
  }

  _ReaderItem? _itemAt(int index) {
    final items = _flatItems;
    if (items.isEmpty) return null;
    return items[index.clamp(0, items.length - 1)];
  }

  /// 从**指定的一话**数相邻话（自动接话之后"当前话"是算出来的，不能再看字段）。
  ComicChapterRef? _neighborFrom(ComicChapterRef? chapter, int delta) {
    final book = _book;
    if (book == null || chapter == null) return null;
    final i = book.chapters.indexWhere((c) => c.url == chapter.url);
    if (i < 0) return null;
    final j = i + delta;
    if (j < 0 || j >= book.chapters.length) return null;
    return book.chapters[j];
  }

  /// 上一话 / 下一话。
  ///
  /// 目录是**正序**的（index 大的更晚）：实测 `https://yemancomic.com/book/7530/`
  /// 页面里第 1 条是「1卷」、最后一条是「第1193话」，规则引擎按文档顺序取，所以
  /// App 拿到的 `book.chapters` 也是第 1 话在前。
  ///
  /// 这里曾经按"倒序"写反过：左边那颗按钮标着「下一话」却打开上一话（2026-09-30 修）。
  ComicChapterRef? _neighbor(int delta) => _neighborFrom(_activeChapter, delta);
}
