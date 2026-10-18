part of './comic_online_page.dart';

// ──────────────────────────────────────────────────────────────
// 阅读器界面簇：阅读页主体、上下控制栏、进度条、压暗层、翻页手势。
// 它在 mixin 链末尾，可以调用前面各簇的成员；反过来那三处
// （`_toast` / `_toggleChrome` / `_scheduleChromeHide`）由主文件的基类
// 先声明、这里实现。
// ──────────────────────────────────────────────────────────────

mixin _ComicReaderChromeMixin on _ComicBrowseMixin {
  Widget _readerBody() {
    if (_busy && _images.isEmpty) {
      return _busyView();
    }
    if (_images.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                _error ?? '这一话没取到图（站点可能改了取图方式）',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _back, child: const Text('返回')),
            ],
          ),
        ),
      );
    }
    if (_pageTurn) {
      // 左右翻页：一屏一张，左右滑（页漫用这个顺）
      return Stack(
        children: [
          // 画面区**黑底**：一页铺满宽度后，剩下的那点空白就成了一圈黑边
          //（阅读器的常规做法），不再是白花花一片"这里是不是缺了东西"
          //（2026-10-02 用户报「最上面空太多了…争取漫画铺满全屏」）。
          // 只铺在画面这一层：加载/报错那些字还是深色，得留在浅色底上。
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          // 页漫的单手操作：左右 1/3 各翻一张，**中间**才收/放控制栏
          //（滑动翻页照旧 —— 点按只是给够不到屏幕边缘的单手握持用）。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleReaderTap(d.localPosition, pageTurn: true),
            // **这里原来有一条"左半屏上下滑 = 调亮暗"的手势，2026-10-02 撤了。**
            // 用户的原话：「我还是喜欢上下滑动，现在上下滑动变成亮度调节了」——
            // 上下滑在他那儿是"读漫画"的动作，变成调亮度就是把这个动作抢走了；
            // 何况同一个动作在两种翻页模式下含义不同（页漫=亮度、条漫=滚动），
            // 这本身就是最容易踩的坑。**亮度只剩底栏那个滑块**（点一下就看得见、还有百分比），
            // 上下滑在任何模式下都不再改亮度。
            // 放大用**长按**，不用双击：双击识别器会把单击拖慢 ~300ms（实测），
            // 而页漫"点一下就翻"是手感的命门。长按只在按住 500ms 后才抢手势。
            onLongPress: () => _openZoom(_itemAt(_imageIndex)?.url ?? ''),
            child: PageView.builder(
              controller: _pageController,
              itemCount: _flatCount,
              onPageChanged: (i) {
                setState(() => _imageIndex = i);
                _saveProgress(i);
              },
              // 一页按**宽度铺满**、从**最上面**排下来。
              //
              // 老写法是 `Center` + `BoxFit.contain`：一页的宽高比与手机对不上时，
              // 上下各留一条等高的空白（实测约 15% 屏高，用户看到的就是「最上面空太多了」，
              // 2026-10-02 报障）。现在空白挤到下面去 —— 那儿本来就压着底部控制栏，不碍事；
              // 一页比一屏还高（长条页）时**页内可以上下滚**，不再缩成两边留白，也不裁掉下半张。
              itemBuilder: (context, i) {
                final it = _itemAt(i);
                if (it == null) return const SizedBox.shrink();
                // 页漫不插"第 X 话"分隔（一屏就是一页，插一条会挡掉第一张的顶部）；
                // 换话那一下用一句 toast 说清楚（见 `_turnPage`）。
                return SingleChildScrollView(
                  child: _CachedImage(
                    url: it.url,
                    cache: _cache,
                    fit: BoxFit.fitWidth,
                    decodeWidth: _readerDecodeWidth(),
                    onDark: true,
                    offline: _offline,
                    offlineBookUrl: _book?.bookUrl ?? '',
                    offlineChapterUrl: it.chapter.url,
                  ),
                );
              },
            ),
          ),
          // 后面的图还在取：顶部挂一条进度，别让人以为是卡住了。
          if (_busy)
            Positioned(
              top: _readerTopInset,
              left: 0,
              right: 0,
              child: _loadingBanner(),
            ),
          // 只提示一次：「喜欢上下滑动读？点这里换成竖向连续」。
          // 排在取图进度**下面**：两条都在顶上时不能互相盖住（提示条是要点的）。
          Positioned(
            left: 0,
            right: 0,
            top: _readerTopInset + (_busy ? 30 : 4),
            child: _pageTurnHintBar(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _readerProgressLine(),
          ),
          Positioned.fill(child: _dimOverlay()),
          Positioned.fill(child: _dimHudView()),
          Positioned(left: 0, right: 0, top: 0, child: _readerTopChrome()),
          Positioned(left: 0, right: 0, bottom: 0, child: _readerChrome()),
        ],
      );
    }
    // 一次算好整条列表（当前话 + 已接上的话）：itemBuilder 里再算就是每张都重算一遍。
    final items = _flatItems;
    final count = items.length;
    final decodeW = _readerDecodeWidth();
    return Stack(
      children: [
        // 同上：竖向连续也是黑底（图片是通栏的，空白只在最后一页下面）。
        const Positioned.fill(child: ColoredBox(color: Colors.black)),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleChrome,
          onLongPress: () => _openZoom(_itemAt(_imageIndex)?.url ?? ''),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (count == 0) return false;
              final max = n.metrics.maxScrollExtent;
              // 快到底了就把下一话接上来（自动加载下一话）：
              // 在**这里**触发是因为竖向连续没有"翻页"事件，滚动是唯一可靠的进度信号。
              if (max > 0 && n.metrics.pixels >= max - _kAutoNextTriggerPx) {
                unawaited(_appendNext());
              }
              // 折算出"滚到第几张"：顶部=第 1 张，底部=最后一张。
              // 老写法 `per = max / count` 在**底部**会算出 count（越界一位），
              // 页面就写成 "210 / 209 张" 这种；用 (count-1) 并夹住范围才两头都对
              // （2026-10-02 用户报"最下面页数显示不对"）。
              final idx = max <= 0
                  ? 0
                  : ((n.metrics.pixels / max) * (count - 1)).round().clamp(
                      0,
                      count - 1,
                    );
              if (idx != _imageIndex) {
                setState(() => _imageIndex = idx);
                _saveProgress(idx);
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              // 末尾多一项：那条"接着接下一话"的分隔（正在接 / 没取到 / 到底是最后一话）。
              itemCount: count + 1,
              itemBuilder: (context, i) {
                if (i >= count) return _appendFooter();
                final it = items[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 自动接话之后必须在两话之间插一条分隔：不插的话两话的图
                    // 首尾相接，看不出已经换了一话。
                    if (it.chapterStart && i > 0) _chapterDivider(it.chapter),
                    _PageImage(
                      url: it.url,
                      cache: _cache,
                      decodeWidth: decodeW,
                      offline: _offline,
                      offlineBookUrl: _book?.bookUrl ?? '',
                      offlineChapterUrl: it.chapter.url,
                      // 预取后面两张：翻页时基本就是本地读盘了。
                      prefetch: items
                          .skip(i + 1)
                          .take(2)
                          .map((e) => e.url)
                          .toList(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (_busy)
          Positioned(
            top: _readerTopInset,
            left: 0,
            right: 0,
            child: _loadingBanner(),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _readerProgressLine()),
        Positioned.fill(child: _dimOverlay()),
        Positioned.fill(child: _dimHudView()),
        Positioned(left: 0, right: 0, top: 0, child: _readerTopChrome()),
        Positioned(left: 0, right: 0, bottom: 0, child: _readerChrome()),
      ],
    );
  }

  /// 两话之间那条「第 X 话」分隔（自动接话用）。
  ///
  /// 为什么非要一条看得见的分隔：接成一整条之后，上一话最后一格和下一话第一格
  /// 是紧挨着的，没有分隔就分不清"这是新的一话"还是"同一话的下一格"。
  Widget _chapterDivider(ComicChapterRef chapter) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white24, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              chapter.title,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const Expanded(child: Divider(color: Colors.white24, height: 1)),
        ],
      ),
    );
  }

  /// 整条列表末尾那一格：正在接 / 没接上（可点重试）/ 到底了。
  ///
  /// 三种状态都要说清楚，因为"底下没动静"最容易被当成 App 卡住了：
  /// 正在接要写"在接哪一话"，失败了要写"哪一话、为什么、点哪儿重试"。
  Widget _appendFooter() {
    final next = _neighbor(1);
    final nextTitle = next?.title ?? '';
    final String text;
    VoidCallback? retry;
    if (_appending) {
      text = '正在接下一话…';
    } else if (_appendError.isNotEmpty) {
      text = '$_appendError（点这里重试）';
      retry = () => unawaited(_appendNext());
    } else if (next == null) {
      text = '已经是最后一话了';
    } else if (!canAutoAppendMore(_appendedImages)) {
      text =
          '这里已接上 $_appendedImages 张（${_appended.length} 话），'
          '再往下请看「下一话」';
      retry = () => unawaited(_openChapter(next));
    } else if (_autoNext) {
      text = '往下滑会自动接「$nextTitle」（点这里立即接）';
      retry = () => unawaited(_appendNext());
    } else {
      text = '自动加载下一话已关，下方「下一话」继续';
      retry = () => unawaited(_appendNext());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 40),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (retry != null && nextTitle.isNotEmpty)
            TextButton(onPressed: retry, child: Text('接下一话「$nextTitle」')),
        ],
      ),
    );
  }

  /// 还在取后面的图时挂的一条进度（写清楚"已取到几张"，不写成"请稍候"）。
  Widget _loadingBanner() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _busyLabel.isEmpty ? '正在取后面的图…' : _busyLabel,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 阅读器里直接挑话。
  ///
  /// 从第 3 话跳到第 50 话不该先退回详情页 —— 这是阅读器里最硬的一处缺口。
  /// 列表里标出"已下载 / 读到这一话"，点一下直接跳。
  Future<void> _pickChapter() async {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return;
    final currentUrl = _chapter?.url;

    // 已下载的话：读离线清单（失败/卡住就当没有，绝不挡住挑话）。
    //
    // 加超时是被测试逼出来的：清单读不动时（存储没就绪）整个目录就打不开了 ——
    // "读标记"是锦上添花，不该挡住"跳到第 50 话"这件正事。
    final downloaded = <String>{};
    try {
      final manifest = await _offline
          .loadBook(book.bookUrl)
          .timeout(const Duration(milliseconds: 600), onTimeout: () => null);
      for (final c in manifest?.chapters ?? const <ComicOfflineChapter>[]) {
        if (c.isDone) downloaded.add(c.url);
      }
    } catch (_) {
      // 清单读不出来不影响挑话。
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<ComicChapterRef>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          // 比原来高一点（0.6 → 0.72）：几百话的目录，一屏能多看几行就是省事。
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          child: ComicChapterList(
            chapters: book.chapters,
            currentUrl: currentUrl,
            downloaded: downloaded,
            prefs: _prefs,
            onPick: (c) => Navigator.of(sheetContext).pop(c),
          ),
        ),
      ),
    );

    if (picked != null && mounted) await _openChapter(picked);
  }

  /// 阅读器里的一次点击。
  ///
  /// 页漫（左右翻页）：左 1/3 上一张、右 1/3 下一张、中间收/放控制栏；
  /// 条漫（竖向连续）：只有"收/放控制栏"（竖直滚动没有"上一张"这回事）。
  void _handleReaderTap(Offset at, {required bool pageTurn}) {
    if (!pageTurn) {
      _toggleChrome();
      return;
    }
    final width = context.size?.width ?? MediaQuery.of(context).size.width;
    if (width <= 0) {
      _toggleChrome();
      return;
    }
    final third = width / 3;
    if (at.dx < third) {
      _turnPage(-1);
    } else if (at.dx > third * 2) {
      _turnPage(1);
    } else {
      _toggleChrome();
    }
  }

  /// 翻一张（页漫）。到头了给一句说明 —— 点了没动静最容易被当成坏了。
  void _turnPage(int delta) {
    final target = _imageIndex + delta;
    if (target < 0) {
      _toast('已经是第一张了');
      return;
    }
    if (target >= _flatCount) {
      // 页漫的「自动加载下一话」：最后一张再往后翻 **就是** 进下一话第一张。
      // 这里不拼接（一屏就是一页，拼接没意义），也不把 already-last 的提示
      // 摆在他面前让他再点一次 —— 他要的就是"不用手动点下一话"。
      final next = _neighbor(1);
      if (_autoNext && !_imagesStreaming && next != null) {
        unawaited(_openChapter(next));
        _toast('已进入「${next.title}」');
        return;
      }
      _toast(
        _imagesStreaming
            ? '这一话还在取后面的图，稍等一下'
            : (_neighbor(1) == null ? '已经是最后一张了' : '已经是最后一张了（可点「下一话」）'),
      );
      return;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// 长按放大：开一个**全屏查看器**（捏合缩放 + 拖动）。
  ///
  /// 为什么不就地套 `InteractiveViewer`：那会和 PageView / ListView 的手势打架
  /// ——捏合和拖动一会儿翻页、一会儿缩放，谁都做不顺。单独一页最干净，
  /// 关掉就回到原来那张（阅读位置不丢）。
  Future<void> _openZoom(String url) async {
    _chromeTimer?.cancel();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ComicZoomView(
          url: url,
          cache: _cache,
          offline: _offline,
          offlineBookUrl: _book?.bookUrl ?? '',
          offlineChapterUrl: _chapter?.url ?? '',
        ),
      ),
    );
  }

  /// 一句短提示（不挡画面、不打断阅读）。
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 点画面：收起 / 叫出底部控制栏。
  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleChromeHide();
  }

  /// 显示几秒后自己收起（不必让用户去点，也不会一直压着画面）。
  @override
  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  /// 页码文案。取完才给总数；还在取时只说"已取到几张"。
  ///
  /// 自动接过话之后要写成「第2话 · 3 / 20 张」：整条列表的长度已经不是"这一话有几张"了，
  /// 直接写 `位置 / 总数` 会变成"读到 210 / 209 张"这种越界页数（用户报过页数不对）。
  String _pageLabel() {
    final items = _flatItems;
    final n = items.length;
    if (n == 0) return '第 1 张';
    final at = (_imageIndex + 1).clamp(1, n);
    if (_imagesStreaming) return '第 $at 张 · 整话还在取（已取到 $n 张）';
    if (_appended.isNotEmpty) {
      final it = items[at - 1];
      return '${it.chapter.title} · ${it.indexInChapter + 1} / ${it.chapterImageCount} 张';
    }
    return '$at / $n 张';
  }

  /// 常驻的一条 2px 进度线：收起控制栏时也知道读到哪了（占位极小，不挡画面）。
  Widget _readerProgressLine() {
    final n = _flatCount;
    final v = n <= 1 ? 1.0 : ((_imageIndex + 1) / n).clamp(0.0, 1.0);
    return IgnorePointer(
      child: LinearProgressIndicator(
        value: v,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        color: Colors.white70,
      ),
    );
  }

  /// 底部控制栏：半透明 + 让开底部安全区，且能被收起来。
  /// 压暗层：压在画面上、**在控制栏下面**（控制栏不该跟着变暗，否则越调越看不见）。
  Widget _dimOverlay() {
    if (_dim <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: _dim),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// 只提示一次的「喜欢上下滑动读？」那条（点一下切成竖向连续）。
  ///
  /// 为什么要有它：翻页方式只是个带 tooltip 的图标按钮，手机上 tooltip 根本看不见。
  /// 用户的原话是「**我还是喜欢上下滑动**，现在上下滑动变成亮度调节了」—— 他要的
  /// 动作是"上下滑"，那就把"怎么得到上下滑"摆在他面前，而不是让他去猜图标。
  Widget _pageTurnHintBar() {
    if (!_showPageTurnHint) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => unawaited(_useVerticalScroll()),
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_vert, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    '喜欢上下滑动读？点这里换成竖向连续',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  IconButton(
                    tooltip: '知道了',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_markPageTurnHintSeen()),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 调暗的那一下提示。
  Widget _dimHudView() {
    if (_dimHud.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _dimHud,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }

  /// 阅读器顶部控制栏压掉的高度（图标按钮 48 + 上下留白 8 + 状态栏）。
  ///
  /// 顶上那两条提示（取图进度 / 换翻页方式）必须躲开它 —— 它们是 `Positioned(top: 0)`
  /// 画的，压在控制栏底下就**点不到**（用例当场逮到过：点提示点到了控制栏）。
  double get _readerTopInset => MediaQuery.of(context).padding.top + 56;

  /// 阅读器顶部那条（返回 + 标题 + 切源）——**压在画面上**，高度不占版面。
  ///
  /// 与底部控制栏同一条命（`_chromeVisible`）：读的时候它是隐的，画面就是整屏。
  Widget _readerTopChrome() {
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: _readerTopBar(),
      ),
    );
  }

  Widget _readerTopBar() {
    return Container(
      color: Colors.black54,
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        // 沉浸态下状态栏本来就没了；万一还看得见（切进切出那一瞬间），别压到它下面。
        top: 4 + MediaQuery.of(context).padding.top,
        bottom: 4,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
          Expanded(
            child: Text(
              // 自动接上下一话之后，标题要写**正在读的那一话**（`_activeChapter`），
              // 不能写"进来时那一话"—— 否则读到下一话，顶上还挂着上一话的名字。
              _activeChapter?.title ?? '阅读',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 读的时候也能换源（这一话取不到图时要能当场换一个），图标压成白的。
          IconTheme(
            data: const IconThemeData(color: Colors.white, size: 20),
            child: _sourceMenu(),
          ),
        ],
      ),
    );
  }

  Widget _readerChrome() {
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: _readerBar(),
      ),
    );
  }

  Widget _readerBar() {
    final prev = _neighbor(-1);
    final next = _neighbor(1);
    return Container(
      // 半透明（不是实心底）：底下还是画面；再让开底部安全区，别被手势条压住。
      color: Colors.black54,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 4,
        bottom: 4 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 竖向连续里给一条**能拖**的进度（页漫不用：一页一页本来就很清楚）。
          // 放在控制栏**里面**、不另占一条：不用去算控制栏多高，也不会互相压住。
          if (!_pageTurn && _flatCount > 1) _scrubRow(),
          Row(
            children: [
              // 左边 = 上一话，右边 = 下一话（跟翻页方向、常见阅读器一致）。
              IconButton(
                tooltip: '目录（直接挑话）',
                onPressed: _busy ? null : _pickChapter,
                icon: const Icon(
                  Icons.list_alt_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              TextButton(
                onPressed: prev == null || _busy
                    ? null
                    : () => _openChapter(prev),
                child: const Text('上一话', style: TextStyle(color: Colors.white)),
              ),
              IconButton(
                tooltip: _pageTurn ? '换成竖向连续（条漫）' : '换成左右翻页（页漫）',
                onPressed: _togglePageTurn,
                icon: Icon(
                  _pageTurn
                      ? Icons.view_day_outlined
                      : Icons.view_carousel_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: '画面亮度（压暗，夜里看不刺眼）',
                onPressed: _openDimSheet,
                icon: const Icon(
                  Icons.brightness_6_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              Expanded(
                child: Text(
                  _pageLabel(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: next == null || _busy
                    ? null
                    : () => _openChapter(next),
                child: const Text('下一话', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 竖向连续的拖动条：一话两百张时，想回到"刚才那一格"只能一直滑，拖一下就到位。
  ///
  /// 落点是**按比例折算**的近似值：一话两百张、高度各不相同，列表还是懒加载的
  /// （没构建过的项没有高度），拿不到精确偏移。近似落点已经够用 —— 到附近再滑
  /// 一两下就到，比"只能一直滑"强得多。
  Widget _scrubRow() {
    final n = _flatCount;
    final v = n <= 1 ? 1.0 : ((_imageIndex + 1) / n).clamp(0.0, 1.0);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(
            '第 ${_imageIndex + 1} 张',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            value: v,
            activeColor: Colors.white70,
            inactiveColor: Colors.white24,
            onChanged: (x) {
              if (n <= 1) return;
              _jumpToImage((x * (n - 1)).round().clamp(0, n - 1));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            '/ $n',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// 拖进度条 → 先把页码跟上去，再把列表滚到按比例折算的位置。
  void _jumpToImage(int index) {
    setState(() => _imageIndex = index);
    _saveProgress(index);
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final n = _flatCount;
    // 列表还没量出高度（或只有一张）时拖不动：页码照样更新，别当成坏了。
    if (n <= 1 || max <= 0) return;
    _scrollController.jumpTo(((index / (n - 1)) * max).clamp(0.0, max));
  }
}
