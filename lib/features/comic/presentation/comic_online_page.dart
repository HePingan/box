// 在线漫画：搜索 → 详情/目录 → 阅读。三件事在**同一个页面**里切换。
//
// 为什么不做成三个页面：整条链共用一个**离屏 WebView**（站点有 JS 挑战，取数必须在
// 页面里跑）。多个页面各建一个 WebView 会互相抢导航 —— 一个页面内切模式最稳。
//
// 界面上的三条底线（与自检一致的风格）：
//   * 失败**说人话**并带上原因（来自书源/站点的原文），不显示"加载失败"了事；
//   * 取不到就说取不到（0 张就是 0 张），不拿占位图假装成功；
//   * 翻页用本地缓存，缓存里没有才下载；某张没下来时给可点的"重试"。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/comic_book.dart';
import '../domain/comic_image_cache.dart';
import '../domain/comic_library_store.dart';
import '../domain/comic_online_progress.dart';
import '../domain/comic_reader_prefs.dart';
import '../domain/comic_online_service.dart';
import '../domain/comic_source.dart';
import '../domain/comic_source_diagnostics.dart'
    show ComicSourceTarget, describeComicProbeError;
import '../domain/comic_source_engine.dart' show ComicProbeException;
import '../domain/sources/seed_comic_source.dart';
import 'comic_source_webview_target.dart';

/// 在线漫画页面（搜索 / 详情 / 阅读三合一）。
class ComicOnlinePage extends StatefulWidget {
  const ComicOnlinePage({
    super.key,
    this.source,
    this.targetBuilder,
    this.imageCache,
    this.progressStore,
    this.libraryStore,
    this.readerPrefs,
    this.initialBookUrl,
    this.waitTimeout = const Duration(seconds: 15),
    this.listTimeout = const Duration(seconds: 12),
    this.openTimeout = const Duration(seconds: 20),
  });

  /// 可注入（测试用）；生产走内置书源。
  final ComicSource? source;

  /// 可注入取数实现（测试用）；生产里由页面自建离屏 WebView。
  final ComicSourceTarget Function()? targetBuilder;

  final ComicImageCache? imageCache;
  final ComicOnlineProgressStore? progressStore;

  /// 从书架点进来时直接打开这本书（省掉再搜一次）。
  final String? initialBookUrl;

  /// 书架的存储（「加入书架」用；测试里注入内存版）。
  final ComicLibraryStore? libraryStore;

  /// 阅读器偏好（翻页方式；测试里注入内存版）。
  final ComicReaderPrefs? readerPrefs;

  /// 等图地址 / 等列表 / 等页面打开 的时间上限（测试里调小，生产用默认）。
  final Duration waitTimeout;
  final Duration listTimeout;
  final Duration openTimeout;

  @override
  State<ComicOnlinePage> createState() => _ComicOnlinePageState();
}

enum _Mode { search, book, reader }

class _ComicOnlinePageState extends State<ComicOnlinePage> {
  late final ComicSource _source;
  late final ComicSourceTarget _target;
  late final ComicOnlineService _service;
  late final ComicImageCache _cache;
  late final ComicOnlineProgressStore _progress;
  late final ComicLibraryStore _library;
  late final ComicReaderPrefs _prefs;

  ComicSourceWebViewController? _webController;

  final _keyController = TextEditingController();
  _Mode _mode = _Mode.search;

  bool _busy = false;

  /// 正在做什么（转圈时必须写出来，否则用户只能看到"一直转圈"）。
  String _busyLabel = '';
  String? _error;

  List<ComicSearchHit> _hits = const [];

  /// 分类浏览：书源里的分类列表 + 当前分类 + 页码。
  List<ComicCategory> _categories = const [];
  ComicCategory? _category;

  /// 接口给的下一页地址（null = 到底了，界面就不显示「加载更多」）。
  String? _nextUrl;

  /// 分类列表没取到时的说明（不静默 —— 但也不挡住搜索）。
  String? _categoryNote;

  /// 这次取数走的是哪条路（快路省时间；退到老路时把原因写出来）。
  String? _pathNote;
  ComicBookDetail? _book;

  /// 这本书在不在书架里（界面按实际状态显示「已在书架」）。
  bool _inShelf = false;

  /// 左右翻页（true）/ 竖向连续长条（false）。竖向是默认，条漫更顺。
  bool _pageTurn = false;

  /// 左右翻页的分页控制器（只在 `_pageTurn` 时用）。
  final _pageController = PageController();

  /// 上次读到哪一话（有才显示「继续看」，没有就不显示）。
  ComicOnlineProgress? _resume;

  /// 书架状态读不出来时的说明（不挡住看书）。
  String? _shelfNote;
  ComicChapterRef? _chapter;
  List<String> _images = const [];
  int _imageIndex = 0;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? ComicSource.tryParse(kSeedComicSourceJson)!;
    if (widget.targetBuilder != null) {
      _target = widget.targetBuilder!();
    } else {
      _webController = ComicSourceWebViewController();
      _target = _webController!.target;
    }
    _service = ComicOnlineService(
      target: _target,
      source: _source,
      waitTimeout: widget.waitTimeout,
      listTimeout: widget.listTimeout,
      openTimeout: widget.openTimeout,
    );
    _cache = widget.imageCache ?? ComicImageCache();
    // 分类列表要等 WebView 就绪，放到第一帧之后（失败不挡搜索，只写在界面上一行）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
    // 从书架点进来的：直接打开这本书（省掉再搜一次）
    final initial = widget.initialBookUrl;
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openBookUrl(initial));
    }
    _library = widget.libraryStore ?? ComicLibraryStore();
    _prefs = widget.readerPrefs ?? ComicReaderPrefs();
    _progress = widget.progressStore ?? ComicOnlineProgressStore();
    _loadPrefs();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _keyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 动作 ──────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action, String label) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  static String _describe(Object e) {
    if (e is ComicProbeException || e is ComicImageException) return '$e';
    return describeComicProbeError(e);
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
        _mode = _Mode.search;
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
        _mode = _Mode.search;
      });
    }, '正在取「${cat.title}」…（最多等 ${_service.openTimeout.inSeconds} 秒）');
  }

  Future<void> _openBook(ComicSearchHit hit) =>
      _openBookUrl(hit.bookUrl, name: hit.name);

  Future<void> _openBookUrl(String url, {String? name}) async {
    await _run(() async {
      final book = await _service.bookInfo(url);
      if (!mounted) return;
      setState(() {
        _book = book;
        _mode = _Mode.book;
        _pathNote = _describePath();
      });
    }, '正在打开这本书…（最多等 ${_service.openTimeout.inSeconds} 秒）');
    // 书架/进度是**装饰**：放在取数之外读，读的时候也不让页面按钮变灰。
    await _refreshShelfFlags();
  }

  /// 读翻页偏好（读不出来就用默认的竖向连续）。
  Future<void> _loadPrefs() async {
    bool v = false;
    try {
      v = await _prefs.pageTurn();
    } catch (_) {
      v = false;
    }
    if (!mounted) return;
    setState(() => _pageTurn = v);
  }

  /// 切换翻页方式（记下来，下次进来还是这个）。
  Future<void> _togglePageTurn() async {
    final next = !_pageTurn;
    setState(() => _pageTurn = next);
    try {
      await _prefs.setPageTurn(next);
    } catch (_) {
      // 记不住不算错：这次先按用户点的显示，下次进来会回到默认。
    }
  }

  /// 这本书在不在书架里 + 上次读到哪一话（两个都读真的，不猜）。
  Future<void> _refreshShelfFlags() async {
    final book = _book;
    if (book == null) return;
    bool inShelf = false;
    ComicOnlineProgress? progress;
    String? note;
    try {
      inShelf = (await _library.fetch()).any((b) => b.onlineUrl == book.bookUrl);
      progress = await _progress.load(book.bookUrl);
    } catch (e) {
      // 书架/进度读不出来是**存储**的问题，不该挡住看书 —— 单独写一行说明。
      note = '书架状态读不出来：${_describe(e)}';
    }
    if (!mounted) return;
    setState(() {
      _inShelf = inShelf;
      _resume = progress;
      _shelfNote = note;
    });
  }

  /// 加入书架（同一本书重复加会覆盖，不会出现两条）。
  Future<void> _addToShelf() async {
    final book = _book;
    if (book == null) return;
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
  }

  Future<void> _openChapter(ComicChapterRef chapter, {int atIndex = 0}) async {
    await _run(() async {
      final images = await _service.chapterImages(chapter.url);
      if (!mounted) return;
      setState(() {
        _chapter = chapter;
        _images = images;
        _imageIndex = atIndex.clamp(0, images.isEmpty ? 0 : images.length - 1);
        _mode = _Mode.reader;
      });
      final book = _book;
      if (book != null) {
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
    }, '正在取「${chapter.title}」的图…（最多等 ${_service.waitTimeout.inSeconds} 秒）');
  }

  /// 进度随手记；失败不影响阅读（不弹错、不中断，下次再存）。
  void _saveProgress(int index) {
    final book = _book;
    final chapter = _chapter;
    if (book == null || chapter == null) return;
    _progress
        .save(
          ComicOnlineProgress(
            bookUrl: book.bookUrl,
            chapterUrl: chapter.url,
            chapterTitle: chapter.title,
            index: index,
          ),
        )
        .catchError((_) {});
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

  /// 上一话 / 下一话（目录是倒序的：index 大的更早）。
  ComicChapterRef? _neighbor(int delta) {
    final book = _book;
    final chapter = _chapter;
    if (book == null || chapter == null) return null;
    final i = book.chapters.indexWhere((c) => c.url == chapter.url);
    if (i < 0) return null;
    final j = i + delta;
    if (j < 0 || j >= book.chapters.length) return null;
    return book.chapters[j];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_mode) {
            _Mode.search => '在线漫画',
            _Mode.book => _book?.name ?? '详情',
            _Mode.reader => _chapter?.title ?? '阅读',
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_mode == _Mode.reader && _book != null) {
              setState(() => _mode = _Mode.book);
            } else if (_mode == _Mode.book) {
              setState(() => _mode = _Mode.search);
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          // 离屏 WebView：取数在它里面跑，用户看不见（1×1、不可点）。
          if (_webController != null) _webController!.buildOffscreen(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && !_busy && _hits.isEmpty && _book == null) {
      return _errorBox();
    }
    return switch (_mode) {
      _Mode.search => _searchBody(),
      _Mode.book => _bookBody(),
      _Mode.reader => _readerBody(),
    };
  }

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
        ],
      ),
    ),
  );

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
                _categories.isEmpty
                    ? '输入关键字，点「搜索」'
                    : '输入关键字搜，或点上面的分类翻榜单',
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
                  title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              _Cover(url: book.cover, cache: _cache, size: 96),
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
            child: ListView.builder(
              itemCount: book.chapters.length,
              itemBuilder: (context, i) {
                final c = book.chapters[i];
                return ListTile(
                  dense: true,
                  title: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: _busy ? null : () => _openChapter(c),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ── 阅读 ──────────────────────────────────────────────────────

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
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pageTurn) {
      // 左右翻页：一屏一张，左右滑（页漫用这个顺）
      return Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _images.length,
            onPageChanged: (i) {
              setState(() => _imageIndex = i);
              _saveProgress(i);
            },
            itemBuilder: (context, i) => Center(
              child: _CachedImage(
                url: _images[i],
                cache: _cache,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _readerBar()),
        ],
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final px = n.metrics.pixels;
            final per = n.metrics.maxScrollExtent /
                (_images.isNotEmpty ? _images.length : 1);
            final idx = per <= 0 ? 0 : (px / per).round();
            if (idx != _imageIndex) {
              setState(() => _imageIndex = idx);
              _saveProgress(idx);
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _images.length,
            itemBuilder: (context, i) => _PageImage(
              url: _images[i],
              cache: _cache,
              // 预取后面两张：翻页时基本就是本地读盘了。
              prefetch: _images.skip(i + 1).take(2).toList(),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _readerBar(),
        ),
      ],
    );
  }

  Widget _readerBar() {
    final prev = _neighbor(-1);
    final next = _neighbor(1);
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          TextButton(
            onPressed: prev == null || _busy ? null : () => _openChapter(prev),
            child: const Text('下一话', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            tooltip: _pageTurn ? '换成竖向连续（条漫）' : '换成左右翻页（页漫）',
            onPressed: _togglePageTurn,
            icon: Icon(
              _pageTurn ? Icons.view_day_outlined : Icons.view_carousel_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              '${_imageIndex + 1} / ${_images.length} 张',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: next == null || _busy ? null : () => _openChapter(next),
            child: const Text('上一话', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// 列表里的封面（带缓存与失败态）。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.cache, required this.size});

  final String? url;
  final ComicImageCache cache;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) {
      return SizedBox(
        width: size,
        height: size * 4 / 3,
        child: const ColoredBox(
          color: Color(0x11000000),
          child: Icon(Icons.image_not_supported_outlined, size: 18),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size * 4 / 3,
      child: _CachedImage(url: u, cache: cache, fit: BoxFit.cover),
    );
  }
}

/// 阅读页的一张图（本地缓存优先；失败可点重试）。
class _PageImage extends StatelessWidget {
  const _PageImage({
    required this.url,
    required this.cache,
    this.prefetch = const [],
  });

  final String url;
  final ComicImageCache cache;
  final List<String> prefetch;

  @override
  Widget build(BuildContext context) {
    for (final p in prefetch) {
      // 预取失败无所谓（真正翻到时会再试并显示原因）。
      cache.fetch(p).catchError((_) => File(''));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _CachedImage(url: url, cache: cache, fit: BoxFit.fitWidth),
    );
  }
}

/// 带缓存与重试的图片。
class _CachedImage extends StatefulWidget {
  const _CachedImage({
    required this.url,
    required this.cache,
    required this.fit,
  });

  final String url;
  final ComicImageCache cache;
  final BoxFit fit;

  @override
  State<_CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<_CachedImage> {
  late Future<File> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.cache.fetch(widget.url);
  }

  void _retry() {
    setState(() => _future = widget.cache.fetch(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return AspectRatio(
            aspectRatio: 3 / 4,
            child: ColoredBox(
              color: const Color(0x11000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    TextButton(onPressed: _retry, child: const Text('重试')),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const AspectRatio(
            aspectRatio: 3 / 4,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Image.file(snap.data!, fit: widget.fit);
      },
    );
  }
}
