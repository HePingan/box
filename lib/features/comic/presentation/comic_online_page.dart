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

import '../domain/comic_image_cache.dart';
import '../domain/comic_online_progress.dart';
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
    this.waitTimeout = const Duration(seconds: 25),
  });

  /// 可注入（测试用）；生产走内置书源。
  final ComicSource? source;

  /// 可注入取数实现（测试用）；生产里由页面自建离屏 WebView。
  final ComicSourceTarget Function()? targetBuilder;

  final ComicImageCache? imageCache;
  final ComicOnlineProgressStore? progressStore;

  /// 等页面就绪/等图地址的时间上限（测试里调小，生产用默认）。
  final Duration waitTimeout;

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

  ComicSourceWebViewController? _webController;

  final _keyController = TextEditingController();
  _Mode _mode = _Mode.search;

  bool _busy = false;
  String? _error;

  List<ComicSearchHit> _hits = const [];
  ComicBookDetail? _book;
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
    );
    _cache = widget.imageCache ?? ComicImageCache();
    _progress = widget.progressStore ?? ComicOnlineProgressStore();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 动作 ──────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
        _mode = _Mode.search;
      });
    });
  }

  Future<void> _openBook(ComicSearchHit hit) async {
    await _run(() async {
      final book = await _service.bookInfo(hit.bookUrl);
      if (!mounted) return;
      setState(() {
        _book = book;
        _mode = _Mode.book;
      });
    });
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
    });
  }

  void _jumpTo(int index) {
    if (!_scrollController.hasClients || _images.isEmpty) return;
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _inlineError(_error!),
          ),
        if (_busy && _hits.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator())),
        if (!_busy && _hits.isEmpty && _error == null)
          const Expanded(
            child: Center(child: Text('输入关键字，点「搜索」')),
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
      ],
    );
  }

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
                  ],
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
            child: Center(child: Text('这本书没取到章节目录（站点可能改版）')),
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
      return const Center(child: CircularProgressIndicator());
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
              final book = _book;
              final chapter = _chapter;
              if (book != null && chapter != null) {
                // 进度随手记；失败不影响阅读（不弹错，下次再存）。
                _progress
                    .save(
                      ComicOnlineProgress(
                        bookUrl: book.bookUrl,
                        chapterUrl: chapter.url,
                        chapterTitle: chapter.title,
                        index: idx,
                      ),
                    )
                    .catchError((_) {});
              }
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
