part of './comic_online_page.dart';

// ──────────────────────────────────────────────────────────────
// 底部的私有控件：封面 / 目录里的离线控件 / 阅读页的图 / 放大查看 / 带缓存的图。
// 整类搬过来（不是 mixin）：类里引用的库级私有符号照旧可用。
// ──────────────────────────────────────────────────────────────

/// 列表里的封面（带缓存与失败态）。
class _Cover extends StatelessWidget {
  const _Cover({
    required this.url,
    required this.cache,
    required this.size,
    this.offline,
    this.offlineBookUrl = '',
  });

  /// 离线库 + 书地址：封面也走"先问本机"（断网时书架/详情页不至于只剩破图标）。
  final ComicOfflineStore? offline;
  final String offlineBookUrl;

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
      child: _CachedImage(
        url: u,
        cache: cache,
        fit: BoxFit.cover,
        offline: offline,
        offlineBookUrl: offlineBookUrl,
        // 封面归"这本书"而不是某一话（离线目录里单独一层）。
        offlineCover: true,
      ),
    );
  }
}

/// 目录里每一话右边的离线控件：下载这一话 / 看进度 / 暂停 / 继续 / 删掉。
///
/// 状态取两个来源：**队列里正在跑的那份**（活的）与**清单里记的那份**（持久）——
/// 队列里没有就看清单，于是重启 App 之后"已下载"照样显示（不然用户会以为白下了）。
class ChapterOfflineAction extends StatefulWidget {
  const ChapterOfflineAction({
    super.key,
    required this.downloader,
    required this.store,
    required this.bookUrl,
    required this.chapter,
    this.bookTitle = '',
    this.cover = '',
  });

  final ComicOfflineDownloader downloader;
  final ComicOfflineStore store;
  final String bookUrl;
  final ComicChapterRef chapter;
  final String bookTitle;
  final String cover;

  @override
  State<ChapterOfflineAction> createState() => _ChapterOfflineActionState();
}

class _ChapterOfflineActionState extends State<ChapterOfflineAction> {
  ComicOfflineChapter? _entry;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.downloader.addListener(_onChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    widget.downloader.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final book = await widget.store.loadBook(widget.bookUrl);
    ComicOfflineChapter? entry;
    for (final c in book?.chapters ?? const <ComicOfflineChapter>[]) {
      if (c.url == widget.chapter.url) entry = c;
    }
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loaded = true;
    });
  }

  bool get _downloaded => _entry?.isDone ?? false;

  Future<void> _tap() async {
    final job = widget.downloader.jobFor(widget.bookUrl, widget.chapter.url);
    if (job != null || _downloaded) {
      await _sheet();
      return;
    }
    await widget.downloader.enqueue(
      bookUrl: widget.bookUrl,
      chapters: [
        ComicOfflineChapter(
          url: widget.chapter.url,
          title: widget.chapter.title,
        ),
      ],
      bookTitle: widget.bookTitle,
      cover: widget.cover,
    );
    await _reload();
  }

  Future<void> _sheet() async {
    final job = widget.downloader.jobFor(widget.bookUrl, widget.chapter.url);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                widget.chapter.title.isEmpty ? '这一话' : widget.chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (job != null &&
                (job.state == ComicOfflineJobState.running ||
                    job.state == ComicOfflineJobState.queued))
              ListTile(
                dense: true,
                leading: const Icon(Icons.pause_rounded, size: 20),
                title: const Text('暂停'),
                onTap: () {
                  widget.downloader.pause(widget.bookUrl, widget.chapter.url);
                  Navigator.of(ctx).pop();
                },
              ),
            if (job != null &&
                (job.state == ComicOfflineJobState.paused ||
                    job.state == ComicOfflineJobState.failed))
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_arrow_rounded, size: 20),
                title: const Text('继续下载'),
                onTap: () {
                  widget.downloader.resume(widget.bookUrl, widget.chapter.url);
                  Navigator.of(ctx).pop();
                },
              ),
            if (_downloaded || job != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete_outline, size: 20),
                title: Text(_downloaded ? '删除这一话的离线内容' : '取消下载并删掉已下的'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await widget.downloader.cancel(
                    widget.bookUrl,
                    widget.chapter.url,
                  );
                  await _reload();
                },
              ),
          ],
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.downloader.jobFor(widget.bookUrl, widget.chapter.url);
    final theme = Theme.of(context);

    Widget icon;
    String tip;
    switch (job?.state) {
      case ComicOfflineJobState.running:
        final j = job;
        icon = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: (j != null && j.total > 0) ? j.progress : null,
            strokeWidth: 2,
          ),
        );
        tip = j == null ? '正在下载' : '正在下载 ${j.done}/${j.total} 张';
      case ComicOfflineJobState.queued:
        icon = const Icon(Icons.schedule_rounded, size: 20);
        tip = '排队中';
      case ComicOfflineJobState.paused:
        icon = const Icon(Icons.pause_circle_outline, size: 20);
        tip = '已暂停：${job?.error ?? ''}';
      case ComicOfflineJobState.failed:
        // 失败时给的是**重试**的样子（不再是"报错"的样子）：点一下就是重试，
        // 而"下不动了怎么办"正是用户在这一格上要找的（2026-10-02 报下载失败）。
        icon = Icon(
          Icons.refresh_rounded,
          size: 20,
          color: theme.colorScheme.error,
        );
        tip = '下载失败：${job?.error ?? ''}（点这里重试）';
      case ComicOfflineJobState.done:
        icon = Icon(
          Icons.check_circle,
          size: 20,
          color: theme.colorScheme.primary,
        );
        tip = '已下载到本机';
      case null:
        if (!_loaded) {
          icon = const Icon(Icons.download_for_offline_outlined, size: 20);
          tip = '下载这一话';
        } else if (_downloaded) {
          icon = Icon(
            Icons.check_circle,
            size: 20,
            color: theme.colorScheme.primary,
          );
          tip = '已下载到本机';
        } else {
          icon = const Icon(Icons.download_for_offline_outlined, size: 20);
          tip = '下载这一话';
        }
    }

    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: _tap,
        onLongPress: _sheet,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(8), child: icon),
      ),
    );
  }
}

/// 阅读页的一张图（本地缓存优先；失败可点重试）。
class _PageImage extends StatelessWidget {
  const _PageImage({
    required this.url,
    required this.cache,
    this.decodeWidth,
    this.prefetch = const [],
    this.offline,
    this.offlineBookUrl = '',
    this.offlineChapterUrl = '',
  });

  final String url;
  final ComicImageCache cache;
  final int? decodeWidth;
  final List<String> prefetch;
  final ComicOfflineStore? offline;
  final String offlineBookUrl;
  final String offlineChapterUrl;

  @override
  Widget build(BuildContext context) {
    for (final p in prefetch) {
      // 预取失败无所谓（真正翻到时会再试并显示原因）。
      cache.fetch(p).catchError((_) => File(''));
    }
    // 竖向连续里**不留页间距**：一页一页贴成一条长图才是条漫该有的样子
    //（2026-10-02 优化；自动接话时两话之间的那条「第X话」分隔仍然保留）。
    return _CachedImage(
      url: url,
      cache: cache,
      fit: BoxFit.fitWidth,
      decodeWidth: decodeWidth,
      onDark: true,
      offline: offline,
      offlineBookUrl: offlineBookUrl,
      offlineChapterUrl: offlineChapterUrl,
    );
  }
}

/// 双击出来的全屏查看器：捏合放大、拖动看细节、双击或右上角关掉。
class _ComicZoomView extends StatelessWidget {
  const _ComicZoomView({
    required this.url,
    required this.cache,
    this.offline,
    this.offlineBookUrl = '',
    this.offlineChapterUrl = '',
  });

  final String url;
  final ComicImageCache cache;
  final ComicOfflineStore? offline;
  final String offlineBookUrl;
  final String offlineChapterUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: _CachedImage(
                    url: url,
                    cache: cache,
                    fit: BoxFit.contain,
                    onDark: true,
                    offline: offline,
                    offlineBookUrl: offlineBookUrl,
                    offlineChapterUrl: offlineChapterUrl,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: '关闭（也可以双击图片）',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  '捏合放大 · 拖动看细节 · 双击关闭',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带缓存与重试的图片。
class _CachedImage extends StatefulWidget {
  const _CachedImage({
    required this.url,
    required this.cache,
    required this.fit,
    this.decodeWidth,
    this.offline,
    this.offlineBookUrl = '',
    this.offlineChapterUrl = '',
    this.offlineCover = false,
    this.onDark = false,
  });

  final String url;
  final ComicImageCache cache;
  final BoxFit fit;

  /// 解码宽度（物理像素）。阅读时按**屏幕宽度**解码，别按原图尺寸解。
  ///
  /// 为什么（2026-10-02 定的优化）：一页 1500×2000 的原图整解要十几 MB 内存，
  /// 竖向连续快速滑过去时会同时解好几张 —— 低内存机直接被系统杀掉。
  /// 按屏宽解，内存和出图时间都省一截。
  ///
  /// **放大查看（`_ComicZoomView`）不要传**：那条路要的就是原图清晰度
  /// （捏合放大到 2-3 倍时，按屏宽解出来的会糊）。
  final int? decodeWidth;

  /// 离线库：有就先在本机找（**命中不发请求** → 飞行模式也能读）。
  final ComicOfflineStore? offline;
  final String offlineBookUrl;
  final String offlineChapterUrl;

  /// 这是**封面**（按"这本书的封面"去找，而不是按某一话的图去找）。
  final bool offlineCover;

  /// 这张图落在**黑底**上（阅读器画面区）：报错文案要浅色，深色会看不见。
  final bool onDark;

  @override
  State<_CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<_CachedImage> {
  late Future<File> _future;

  /// 自动重试次数（**只在"被掐断"这类一闪而过的错上**用）。
  ///
  /// 2026-10-02 图床一直在交替掐端口：这类错等一两秒再试往往就通了。
  /// 没有它，用户看到的是破图 + 重试按钮 —— 明明等一下就能自己好。
  /// 上限 2 次（1.5s、4s），HTTP 码/0 字节这类"再试也没用"的错不重试。
  int _autoRetries = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    unawaited(_watchTransientFailure());
  }

  /// 盯着这次取图的结果：是"一闪而过"的网错就自己再试（最多两次）。
  Future<void> _watchTransientFailure() async {
    while (mounted && _autoRetries < 2) {
      try {
        await _future; // 取到了就没什么要做的
        return;
      } catch (e) {
        if (!mounted) return;
        // HTTP 码 / 0 字节 / 地址不合法：再试也是一样，别浪费用户流量。
        if (e is! ComicImageException || !e.transient) return;
        _autoRetries++;
        // 等差退避：1.5s、然后 3s —— 图床对短时并发敏感，立刻再撞上去没意义。
        await Future<void>.delayed(Duration(milliseconds: 1500 * _autoRetries));
        if (!mounted) return;
        // 注意用块体：箭头体返回的是"赋值表达式的值"（一个 Future），
        // setState 会当场断言失败（这条是被用例逮出来的）。
        setState(() {
          _future = _load();
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _autoRetries = 0;
      _future = _load();
    });
    unawaited(_watchTransientFailure());
  }

  /// 取图：**先问离线库**（下过的话本机就有，一个请求都不用发），没有再走缓存/网络。
  ///
  /// 同步版（`localFileIfReady`）：渲染路径上不做平台通道往返；离线库的预热在进页面/
  /// 打开章节时做（见 `ComicOfflineStore.warmUp`）。
  Future<File> _load() async {
    final offline = widget.offline;

    /// 同步问一次（预热过就是纯路径计算）。命中 → 一个请求都不发。
    File? local() => widget.offlineCover
        ? offline?.localCoverIfReady(widget.offlineBookUrl, widget.url)
        : offline?.localFileIfReady(
            widget.offlineBookUrl,
            widget.offlineChapterUrl,
            widget.url,
          );

    /// 认真问一次（可以等）。只在**联网那条路已经失败**时才走到这里。
    Future<File?> localAsync() async => widget.offlineCover
        ? await offline?.localCover(widget.offlineBookUrl, widget.url)
        : await offline?.localFile(
            widget.offlineBookUrl,
            widget.offlineChapterUrl,
            widget.url,
          );

    final fast = local();
    if (fast != null) return fast;

    /// 离线库**当前能不能答话**：预热过就能（纯路径计算），没预热就别在这里等 ——
    /// 平台通道往返在拿不到平台实现的环境里会一直挂着，界面上就只剩一个转圈。
    final usable = offline != null && offline.readyRoot != null;
    try {
      return await widget.cache.fetch(widget.url);
    } catch (e) {
      // 断网/图床被掐：这时才值得再问一次离线库（下过的话照样读得出来）。
      if (usable) {
        final fallback = await localAsync();
        if (fallback != null) return fallback;
      } else {
        // 没预热就顺手预热一下：用户点「重试」时就有离线那条快路了。
        unawaited(offline?.warmUp() ?? Future<void>.value());
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<File>(
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
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.onDark ? Colors.white70 : null,
                      ),
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
        return Image.file(
          snap.data!,
          fit: widget.fit,
          // 传了才按指定宽度解码；没传（放大查看/封面）就按原图，别擅自降清晰度。
          cacheWidth: widget.decodeWidth,
        );
      },
    );
    return content;
  }
}
