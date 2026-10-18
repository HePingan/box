part of './comic_online_page.dart';

// ──────────────────────────────────────────────────────────────
// 浏览簇：搜索 / 分类 / 详情 / 书架 / 下载范围 / 列表与详情界面。
// on 类型是 `_ComicReaderMixin`（详情页能从「继续看」直接进阅读器）。
// ──────────────────────────────────────────────────────────────

mixin _ComicBrowseMixin on _ComicReaderMixin {
  /// 第一帧之后的开场：先把令牌拿到手（**有**令牌才走中转，没有就直连站点），
  /// 再取分类、再打开指定的书。
  Future<void> _boot() async {
    await _resolveRelayToken();
    if (!mounted) return;
    _swapService();
    await _loadCategories();
    final initial = widget.initialBookUrl;
    if (initial != null && initial.isNotEmpty) {
      // 从书架直接进来的：后面**没有**"搜索"这一层，所以不记进层级栈 ——
      // 否则按返回会退到一个空搜索页（看起来就是"返回跳到最上层"）。
      await _openBookUrl(initial, fromList: false);
    }
  }

  Future<void> _search() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = '先填个关键字（比如「海贼」）再搜');
      return;
    }
    await _run(() async {
      final hits = await _service.search(key);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _category = null; // 搜索与分类共用这份列表；搜了就退出分类态
        _nextUrl = null;
        _pathNote = _describePath();
        _setMode(_Mode.search);
        _levels.clear(); // 回到顶层：层级栈一起清掉（新的一轮从列表开始）
      });
    }, '正在搜索「$key」…（最多等 ${_service.openTimeout.inSeconds} 秒）');
  }

  /// 分类列表（书源 exploreUrl 的 JS）。失败只记一行说明，不影响搜索。
  Future<void> _loadCategories() async {
    try {
      final cats = await _service.categories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoryNote = null;
      });
    } on ComicProbeException catch (e) {
      if (!mounted) return;
      setState(() => _categoryNote = '分类浏览不可用：${e.message}');
    }
  }

  /// 切换书源：清掉上一次的结果、按新源重建服务（中转要重算）、再把上一次的关键字重搜一遍。
  Future<void> _selectSource(ComicSource s) async {
    if (s.name == _source.name) return;
    setState(() {
      _source = s;
      _hits = const [];
      _book = null;
      _chapter = null;
      _images = const [];
      _categories = const [];
      _category = null;
      _nextUrl = null;
      _pathNote = null;
      _categoryNote = null;
      _error = null;
      _setMode(_Mode.search);
      _levels.clear(); // 换源 = 从头开始
    });
    // 换到的源可能也走中转（比如从包子换回野蛮）——令牌按新源再确认一次。
    await _resolveRelayToken();
    if (!mounted) return;
    _swapService();
    await _loadCategories();
    final key = _keyController.text.trim();
    if (key.isNotEmpty) await _search();
  }

  /// 按分类取书（[more] = 往列表后面追加下一页，地址用接口给的 `next`）。
  Future<void> _openCategory(ComicCategory cat, {bool more = false}) async {
    final url = more ? _nextUrl : cat.url;
    if (url == null || url.isEmpty) return;
    await _run(() async {
      final page = await _service.explore(url);
      if (!mounted) return;
      setState(() {
        _category = cat;
        _nextUrl = page.nextUrl; // 到底了就是 null：不显示"加载更多"，也不假装还有
        _hits = more ? [..._hits, ...page.hits] : page.hits;
        _setMode(_Mode.search);
        if (!more) _levels.clear(); // 分类浏览也回到"列表"这一层
      });
    }, '正在取「${cat.title}」…（最多等 ${_service.openTimeout.inSeconds} 秒）');
  }

  Future<void> _openBook(ComicSearchHit hit) =>
      _openBookUrl(hit.bookUrl, name: hit.name);

  /// 记下"这本书的目录我看过了"（追更角标用；失败不算错，写不进去最多是角标多挂一会）。
  Future<void> _markCatalogSeen(ComicBookDetail book) async {
    if (book.chapters.isEmpty) return;
    try {
      await _updates.seen(
        bookUrl: book.bookUrl,
        titles: [for (final c in book.chapters) c.title],
        urls: [for (final c in book.chapters) c.url],
      );
    } catch (_) {
      // 记不住不影响看书。
    }
  }

  Future<void> _openBookUrl(
    String url, {
    String? name,
    bool fromList = true,
  }) async {
    await _run(() async {
      final book = await _service.bookInfo(url);
      if (!mounted) return;
      setState(() {
        _book = book;
        // 从列表点进来的记一层（返回能退回列表）；从书架直接进来的不记
        // （后面本来就没有上一层，记了会退到一个空搜索页）。
        if (fromList && _mode != _Mode.book) _levels.add(_mode);
        _setMode(_Mode.book);
        _pathNote = _describePath();
      });
      // 目录已经摆在用户面前了 → 追更的"有新话"角标据此清掉
      // （收藏里挂着红点、点进去却是自己早看过的话，就是骗人）。
      unawaited(_markCatalogSeen(book));
    }, '正在打开这本书…（最多等 ${_service.openTimeout.inSeconds} 秒）');
    // 站点打不开（断网 / 被掐断）**或目录是空的**：这本书下过的话，就从离线清单
    // 把书名/封面/目录摆出来。"下过了却连目录都进不去"是最不像话的一种失败。
    //
    // 两种形态都要接：打不通是抛错（_book 还是 null），而站点能连上但取不到目录
    // 时是**成功返回一本空目录的书**（以前这里只接抛错，于是断网时那种情况漏了）。
    if (_book == null || _book!.chapters.isEmpty) {
      await _showOfflineFallback(url);
    }
    // 书架/进度是**装饰**：放在取数之外读，读的时候也不让页面按钮变灰。
    await _refreshShelfFlags();

    // 「续读」：内容页的收藏卡片点进来时，直接接着上次读到的那一话
    // （不然还要"进详情 → 找到那一话 → 点"，收藏反而变成多两步的负担）。
    final resume = _resume;
    if (widget.autoResume && resume != null && mounted) {
      final chapters = _book?.chapters ?? const <ComicChapterRef>[];
      // 先按地址认；地址对不上（书源换了域名 / 相对地址解析变了）再按标题认
      // —— 存的是"上次读到哪一话"，别因为地址写法变了就丢掉这个信息。
      ComicChapterRef? target;
      for (final c in chapters) {
        if (c.url == resume.chapterUrl) {
          target = c;
          break;
        }
      }
      if (target == null && resume.chapterTitle.isNotEmpty) {
        for (final c in chapters) {
          if (c.title == resume.chapterTitle) {
            target = c;
            break;
          }
        }
      }
      final found = target;
      if (found != null) await _openChapter(found);
    }
  }

  /// 断网兜底：用离线清单把这本书摆出来，**只列已经下好的话**。
  Future<void> _showOfflineFallback(String url) async {
    // 没预热就别在这里等平台调用（那种环境里会一直挂着，页面就卡在报错态）。
    if (_offline.readyRoot == null) return;
    ComicOfflineBook? saved;
    try {
      saved = await _offline.loadBook(url);
    } catch (_) {
      saved = null;
    }
    final s0 = saved;
    if (s0 == null || s0.doneCount == 0) return;
    if (!mounted) return;
    setState(() {
      _book = ComicBookDetail(
        bookUrl: url,
        name: s0.title.isEmpty ? '（离线）已下载的漫画' : s0.title,
        cover: s0.cover,
        chapters: [
          for (final c in s0.chapters.where((c) => c.isDone))
            ComicChapterRef(title: c.title, url: c.url),
        ],
      );
      _setMode(_Mode.book);
      _error = null;
      _pathNote = '离线';
      _offlineNote = '离线模式：站点没连上，这里列的是已下载的 ${s0.doneCount} 话';
    });
  }

  /// 加入书架（同一本书重复加会覆盖，不会出现两条）。
  Future<void> _addToShelf() async {
    final book = _book;
    if (book == null) return;
    try {
      await _library.add(
        ComicBook(
          id: book.bookUrl,
          title: book.name,
          coverPath: book.cover,
          sourceType: ComicSourceType.online,
          onlineUrl: book.bookUrl,
          author: book.author,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _refreshShelfFlags();
      unawaited(_syncSoon());
      if (!mounted) return;
      // 给一句回执并说清去哪里找：用户点完会去「内容 → 漫画收藏」翻，
      // 只有按钮变三个字的话，他不知道收藏落到了哪儿（2026-10-02 的报障语境）。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已加入书架 · 在「内容 → 漫画收藏」里'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 失败要说人话：静默失败会让人以为"点了收藏"，其实没存进去。
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入书架失败：${_describe(e)}')));
    }
  }

  /// 「下载」：选下载范围。
  ///
  /// 为什么要有"未读之后 N 话"：追更的人真正想要的是"把我还没看的先下下来"，
  /// 而不是整本 —— 一本 200 话的漫画在 5G 上不是小数目（几个 GB）。
  Future<void> _pickDownloadScope(ComicBookDetail book) async {
    final chapters = book.chapters;
    if (chapters.isEmpty) return;

    // "未读之后" = 从上次读到的那一话往后；没读到过就从列表开头。
    final resumeUrl = _resume?.chapterUrl;
    var start = 0;
    if (resumeUrl != null) {
      final i = chapters.indexWhere((c) => c.url == resumeUrl);
      if (i >= 0) start = i;
    }
    final rest = chapters.skip(start).toList();
    final options = <String, List<ComicChapterRef>>{
      '未读之后 5 话': rest.take(5).toList(),
      '未读之后 10 话': rest.take(10).toList(),
      '余下全部（${rest.length} 话）': rest,
      '整本（${chapters.length} 话）': chapters,
    };
    final fromLabel = start > 0 ? '从「${chapters[start].title}」往后' : '从列表第一话开始';

    final picked = await showModalBottomSheet<List<ComicChapterRef>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('下载到本机（下过之后不联网也能读）'),
            ),
            for (final e in options.entries)
              if (e.value.isNotEmpty)
                ListTile(
                  dense: true,
                  title: Text(e.key),
                  subtitle: e.key.startsWith('未读') ? Text(fromLabel) : null,
                  onTap: () => Navigator.of(ctx).pop(e.value),
                ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open_outlined, size: 20),
              title: const Text('离线下载管理'),
              onTap: () => Navigator.of(ctx).pop(const <ComicChapterRef>[]),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;

    if (picked.isEmpty) {
      _openOfflineManager();
      return;
    }
    // **正在看的这一话插到最前面**：下载是串行的，用户更想马上能离线看手上这一话，
    // 而不是等前面几十话挨个下完（点「整本」时前面的等待是按小时计的）。
    final currentUrl = _chapter?.url;
    final ordered = <ComicChapterRef>[
      if (currentUrl != null)
        for (final c in picked)
          if (c.url == currentUrl) c,
      for (final c in picked)
        if (c.url != currentUrl) c,
    ];
    await _downloader.enqueue(
      bookUrl: book.bookUrl,
      chapters: [
        for (final c in ordered)
          ComicOfflineChapter(url: c.url, title: c.title),
      ],
      bookTitle: book.name,
      cover: book.cover ?? '',
    );
    if (!mounted) return;
    // 被"仅 Wi-Fi"拦下时，顺手给一个一次性的放行按钮 —— 否则用户只会看到"怎么不动"。
    final held = _downloader.waitingForWifi;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          held
              ? '已加入队列：${picked.length} 话 —— 按设置只在 Wi-Fi 下下载'
              : '已加入下载队列：${picked.length} 话（可在「离线下载管理」里看进度）',
        ),
        action: held
            ? SnackBarAction(
                label: '这次也用流量',
                onPressed: () => _downloader.allowNetworkOnce(),
              )
            : null,
      ),
    );
  }

  void _openOfflineManager() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ComicOfflinePage(store: _offline, downloader: _downloader),
      ),
    );
  }

  /// 书源切换：内置的源都列出来（各自的备注写在名字下面，只作展示）。
  ///
  /// 菜单里还挂一条「自检这份源」：源出问题时最有用的一步就是跑一次自检，
  /// 入口不该只藏在漫画库那一页（用户只有手机，出问题时想在原地拿到结论）。
  Widget _sourceMenu() => PopupMenuButton<Object>(
    tooltip: '切换书源',
    icon: const Icon(Icons.source_outlined),
    onSelected: (value) {
      if (value is ComicSource) {
        _selectSource(value);
      } else {
        _openSourceSelfCheck();
      }
    },
    itemBuilder: (context) => <PopupMenuEntry<Object>>[
      for (final s in _sources)
        PopupMenuItem<Object>(
          value: s,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.name,
                style: s.name == _source.name
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
              ),
              if (_noteForComicSource(s) != null)
                Text(
                  _noteForComicSource(s)!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<Object>(
        value: _kSelfCheckItem,
        child: Row(
          children: [
            const Icon(Icons.health_and_safety_outlined, size: 18),
            const SizedBox(width: 8),
            Text('自检「${_source.name}」'),
          ],
        ),
      ),
    ],
  );

  Widget _errorBox() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _search, child: const Text('重试')),
          const SizedBox(height: 4),
          // 失败了别只让人反复重试：源坏没坏、坏在哪一步，跑一次自检就有结论，
          // 而且自检页能一键复制结论（用户只有手机，这是他唯一拿得到证据的途径）。
          TextButton(
            onPressed: _openSourceSelfCheck,
            child: const Text('自检这个源'),
          ),
        ],
      ),
    ),
  );

  /// 打开「漫画源自检」，并预选当前这份源。
  void _openSourceSelfCheck() {
    final name = _source.name;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.selfCheckPageBuilder?.call(name) ??
            ComicSourceCheckPage(initialSourceName: name),
      ),
    );
  }

  // ── 搜索 ──────────────────────────────────────────────────────

  Widget _searchBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '搜漫画名，例如：海贼',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _search,
                child: Text(_busy ? '搜索中…' : '搜索'),
              ),
            ],
          ),
        ),
        if (_categoryNote != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _categoryNote!,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (_categories.isNotEmpty) _categoryBar(),
        if ((_pathNote ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _pathNote!,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _inlineError(_error!),
          ),
        if (_busy && _hits.isEmpty) Expanded(child: _busyView()),
        if (!_busy && _hits.isEmpty && _error == null)
          Expanded(
            child: Center(
              child: Text(
                _categories.isEmpty ? '输入关键字，点「搜索」' : '输入关键字搜，或点上面的分类翻榜单',
              ),
            ),
          ),
        if (_hits.isNotEmpty)
          Expanded(
            child: ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final hit = _hits[i];
                return ListTile(
                  leading: _Cover(url: hit.cover, cache: _cache, size: 44),
                  title: Text(
                    hit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    hit.author == null || hit.author!.isEmpty
                        ? '（未给出作者）'
                        : hit.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _openBook(hit),
                );
              },
            ),
          ),
        if (_nextUrl != null && !_busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton(
              onPressed: () => _openCategory(_category!, more: true),
              child: const Text('加载更多'),
            ),
          ),
      ],
    );
  }

  /// 分类条：横向滚动的分类按钮（书源给多少就显示多少）。
  Widget _categoryBar() => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final cat = _categories[i];
        final selected = _category?.title == cat.title;
        return Center(
          child: selected
              ? FilledButton(
                  onPressed: _busy ? null : () => _openCategory(cat),
                  child: Text(cat.title),
                )
              : OutlinedButton(
                  onPressed: _busy ? null : () => _openCategory(cat),
                  child: Text(cat.title),
                ),
        );
      },
    ),
  );

  /// 取数方式说明：快路就直说快路；退到老路时把原因带上（慢也要慢得明白）。
  String _describePath() {
    final path = _service.lastPath;
    final note = _service.lastPathNote;
    if (path.isEmpty) return '';
    if (path.contains('快路')) return '取数方式：取 HTML 文本解析（快路）';
    return note == null || note.isEmpty
        ? '取数方式：$path'
        : '取数方式：$path —— 快路没通：$note';
  }

  /// 转圈**必须**带上"在做什么、最多等多久"；再久一点就提示站点可能不可达。
  Widget _busyView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _busyLabel.isEmpty ? '正在处理…' : _busyLabel,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '等的时间偏长时，多半是站点这一侧不肯给（不是这台手机的问题）。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );

  Widget _inlineError(String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );

  // ── 详情 + 目录 ───────────────────────────────────────────────

  Widget _bookBody() {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(
                url: book.cover,
                cache: _cache,
                size: 96,
                offline: _offline,
                offlineBookUrl: book.bookUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author == null || book.author!.isEmpty
                          ? '（未给出作者）'
                          : book.author!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '共 ${book.chapters.length} 话',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (book.chapters.isNotEmpty)
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _openChapter(book.chapters.first),
                        child: const Text('从最新一话开始读'),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_resume != null)
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _openChapter(
                                    ComicChapterRef(
                                      title: _resume!.chapterTitle,
                                      url: _resume!.chapterUrl,
                                    ),
                                  ),
                            child: Text(
                              _resume!.chapterTitle.trim().isEmpty
                                  ? '继续看（第 ${_resume!.index + 1} 张）'
                                  : '继续看 ${_resume!.chapterTitle}',
                            ),
                          ),
                        OutlinedButton(
                          onPressed: _busy || _inShelf ? null : _addToShelf,
                          child: Text(_inShelf ? '已在书架' : '加入书架'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickDownloadScope(book),
                          icon: const Icon(
                            Icons.download_for_offline_outlined,
                            size: 18,
                          ),
                          label: const Text('下载'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_shelfNote != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _shelfNote!,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (_offlineNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _offlineNote!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (book.intro != null && book.intro!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              book.intro!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _inlineError(_error!),
          ),
        if (book.chapters.isEmpty)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这本书没取到章节目录（站点可能改版；也可能是目录还没渲染出来）',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else ...[
          const Divider(height: 1),
          Expanded(
            // 与阅读器里的「目录」同一份列表：快速滑动 + 正序/倒序 + 跳话。
            child: ComicChapterList(
              chapters: book.chapters,
              currentUrl: _chapter?.url,
              prefs: _prefs,
              trailing: (c) => ChapterOfflineAction(
                downloader: _downloader,
                store: _offline,
                bookUrl: book.bookUrl,
                bookTitle: book.name,
                cover: book.cover ?? '',
                chapter: c,
              ),
              onPick: _busy ? null : _openChapter,
            ),
          ),
        ],
      ],
    );
  }

  // ── 阅读 ──────────────────────────────────────────────────────
}
