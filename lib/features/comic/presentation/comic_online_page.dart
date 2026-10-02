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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/comic_book.dart';
import '../domain/comic_image_cache.dart';
import '../domain/comic_offline_downloader.dart';
import '../domain/comic_offline_store.dart';
import '../domain/comic_library_store.dart';
import '../domain/comic_online_progress.dart';
import '../domain/comic_prefetch.dart';
import '../domain/comic_reader_prefs.dart';
import '../domain/comic_update_watch.dart';
import '../domain/comic_online_service.dart';
import '../domain/comic_relay.dart';
import '../domain/comic_source.dart';
import '../domain/comic_source_diagnostics.dart'
    show ComicSourceTarget, describeComicProbeError;
import '../domain/comic_source_engine.dart' show ComicProbeException;
import '../domain/sources/seed_comic_source.dart';
import 'comic_chapter_list.dart';
import 'comic_offline_page.dart';
import 'comic_offline_wiring.dart';
import 'comic_source_check_page.dart';
import 'comic_source_webview_target.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart'
    show ServerOpsSettings;

/// 书源菜单里「自检这份源」那一项的取值：菜单值的类型是 `Object`
/// （既能装一份源，也能装这一项），命中它就开自检页。
const Object _kSelfCheckItem = 'comicSourceSelfCheck';

/// 读到"还剩几张"就值得开始预取下一话：留 2 张的余量，够用户在翻页时把下一话开头
/// 那几张图下完。设成 0（读到最后一张才取）就来不及了 —— 那时候用户已经在点了。
const int _kPrefetchTriggerPages = 2;

/// 读中转要用的**设备令牌**（与只读运维 API 共用同一份）。
///
/// **取哪一台的令牌 = 中转服务真正跑在哪台**（175，`builtInTencent175Id`）。
/// 入口域名是 `box.hpa888.top`，但那只是边缘机的 nginx 反代
/// （`location ^~ /comicrelay/` → 隧道 8099 → 175:8098）；**中转进程在 175**，按
/// **175 的**令牌库校验（单元里没有 `BOX_OPS_TOKENS` 覆盖 → 读 175 的
/// `/root/.secrets/box-ops-api-tokens.json`，里面只有 `box-app-175`，没有 hpa888 那把）。
/// 按域名直觉取 hpa888 那把会**每次都 401**（实测：错令牌打公网入口拿到
/// `401 {"error":"令牌无效…"}`）。
///
/// 最小侵入：读不出来一律返回空串（**不抛**）。界面据此给「先去设置里填」的引导，
/// 而不是把整个页面变成错误页 —— 没填令牌只是"这个源现在读不了"，不是 App 坏了。
Future<String> loadComicRelayToken() async {
  try {
    final settings = await ServerOpsSettings.load();
    return settings.apiTokenFor(ServerOpsSettings.builtInTencent175Id).trim();
  } catch (_) {
    return '';
  }
}

/// 内置书源（第一份是默认）。解析不出来的**跳过**：坏一份源不该让页面打不开。
List<ComicSource> _builtinComicSources() {
  final out = <ComicSource>[];
  for (final json in kSeedComicSourcesJson) {
    final s = ComicSource.tryParse(json);
    if (s != null) out.add(s);
  }
  return out;
}

/// 内置源在界面上的备注（键 = 书源名；没有就是没有）。
String? _noteForComicSource(ComicSource s) => kSeedComicSourceNotes[s.name];

/// 在线漫画页面（搜索 / 详情 / 阅读三合一）。
class ComicOnlinePage extends StatefulWidget {
  const ComicOnlinePage({
    super.key,
    this.source,
    this.targetBuilder,
    this.imageCache,
    this.offlineStore,
    this.offlineDownloader,
    this.progressStore,
    this.libraryStore,
    this.readerPrefs,
    this.initialBookUrl,
    this.relayToken,
    this.autoResume = false,
    this.waitTimeout = const Duration(seconds: 15),
    this.listTimeout = const Duration(seconds: 12),
    this.openTimeout = const Duration(seconds: 20),
    this.selfCheckPageBuilder,
  });

  /// 可注入（测试用）；生产走内置书源。
  final ComicSource? source;

  /// 可注入取数实现（测试用）；生产里由页面自建离屏 WebView。
  final ComicSourceTarget Function()? targetBuilder;

  final ComicImageCache? imageCache;

  /// 离线库（**阅读页取图先问它**：命中就一个请求都不发，飞行模式也能读）。
  final ComicOfflineStore? offlineStore;

  /// 离线下载队列（测试注入用）；生产用全 App 共用那份（离开本页也要继续下）。
  final ComicOfflineDownloader? offlineDownloader;

  final ComicOnlineProgressStore? progressStore;

  /// 从书架点进来时直接打开这本书（省掉再搜一次）。
  final String? initialBookUrl;

  /// 进来就直接接着上次读到的那一话（内容页的收藏卡片用它做「续读」）。
  ///
  /// 默认 false：从书库搜索进来的路径要保持"先看详情"，别擅自把用户丢进阅读器。
  final bool autoResume;

  /// 中转要用的**设备令牌**（**可选**：没有它就直连站点，功能照样可用）。
  ///
  /// 生产里由书库页从设置里取好传进来（[loadComicRelayToken]）；
  /// **测试注入假值**；传 null = 页面自己去设置里读一次。
  /// 传空串 = "明确没有令牌"（测试用，避免真的去读设置；也就是走直连）。
  final String? relayToken;

  /// 书架的存储（「加入书架」用；测试里注入内存版）。
  final ComicLibraryStore? libraryStore;

  /// 阅读器偏好（翻页方式；测试里注入内存版）。
  final ComicReaderPrefs? readerPrefs;

  /// 等图地址 / 等列表 / 等页面打开 的时间上限（测试里调小，生产用默认）。
  final Duration waitTimeout;
  final Duration listTimeout;
  final Duration openTimeout;

  /// 可注入（测试用）：按源名造「漫画源自检」那一页。
  ///
  /// 为什么不直接 new 出真页面：真页面会建平台 WebView，纯 widget test 里碰不得
  /// （测试只要验证「带的是哪份源」）。
  final Widget Function(String sourceName)? selfCheckPageBuilder;

  @override
  State<ComicOnlinePage> createState() => _ComicOnlinePageState();
}

enum _Mode { search, book, reader }

class _ComicOnlinePageState extends State<ComicOnlinePage> {
  late final List<ComicSource> _sources;
  late ComicSource _source;
  late final ComicSourceTarget _target;
  late ComicOnlineService _service;
  late ComicImageCache _cache;
  late final ComicOnlineProgressStore _progress;
  late final ComicLibraryStore _library;
  late final ComicReaderPrefs _prefs;

  /// 当前生效的中转（源带 relay + 有令牌才有；否则 null = 老路）。
  ComicRelay? _relay;

  /// 中转令牌（注入的优先；没有就去设置里读一次）。
  String _relayToken = '';

  ComicSourceWebViewController? _webController;

  final _keyController = TextEditingController();
  _Mode _mode = _Mode.search;

  /// 真实走过的层级（返回时按它一层层退，不照写死的阶梯退）。
  ///
  /// 为什么需要：从书架点一本直接进「详情」时，后面**并没有**"搜索"这一层。照阶梯退
  /// 会退到一个空搜索页 —— 用户看到的就是"返回一跳跳到最上层，不是一层层退"（2026-09-29）。
  final List<_Mode> _levels = <_Mode>[];

  /// 一层层返回：退到了返回 true；没有上一层（该退出本页）返回 false。
  ///
  /// 左上角箭头与**系统返回**（手势 / 返回键）都走这里，两条路同一个口径。
  /// 切模式。阅读器的进入/退出有好几个入口（点目录、继续看、翻话、返回、系统返回），
  /// 沉浸态（隐藏状态栏 + 屏幕常亮）在这里**统一开关**，散着写迟早漏一处。
  void _setMode(_Mode mode) {
    _mode = mode;
    _syncReaderImmersive();
  }

  /// 屏幕常亮开关。平台通道缺失（测试环境、被裁剪的构建）不该影响看书：
  /// 失败就吞掉 —— 这只是"看得更舒服"，不是功能本身。
  void _setWakelock(bool on) {
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}),
    );
  }

  /// 进阅读器：隐藏状态栏/导航条 + 屏幕常亮；出来恢复。
  ///
  /// 常亮这条是刚需：长图一页要看很久，看到一半黑屏是纯损失
  /// （本地阅读器和小说阅读器早就在做了，在线漫画这边漏了）。
  void _syncReaderImmersive() {
    final reader = _mode == _Mode.reader;
    if (reader == _readerImmersive) return;
    _readerImmersive = reader;
    if (reader) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _setWakelock(true);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _setWakelock(false);
    }
  }

  void _back() {
    if (_levels.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    // 走 _setMode：从阅读器退出来时要把状态栏/常亮还回去
    // （测试先逮到的：只改 _mode 不动沉浸态，退回详情页后状态栏一直藏着）。
    setState(() => _setMode(_levels.removeLast()));
  }

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

  /// 离线库：阅读页与封面都先问它（命中 → 不发请求）。
  late final ComicOfflineStore _offline =
      widget.offlineStore ?? ComicOfflineStore();

  /// 离线下载队列（全 App 共用：离开本页之后还要接着下）。
  late final ComicOfflineDownloader _downloader =
      widget.offlineDownloader ?? ComicOfflineDownloader.shared();

  /// 这本书在不在书架里（界面按实际状态显示「已在书架」）。
  bool _inShelf = false;

  /// 左右翻页（true）/ 竖向连续长条（false）。竖向是默认，条漫更顺。
  bool _pageTurn = false;

  /// 追更记录本（只用来"记下我看到的目录"；查询在收藏那两页做）。
  late final ComicUpdateWatch _updates = ComicUpdateWatch();

  /// 阅读器的**压暗**档位（0~0.8）：夜里看漫画嫌亮，压一层黑就够了（见 ComicReaderPrefs.dimLevel）。
  double _dim = 0;

  /// 调暗时那一下的提示（比如"亮度 40%"），几秒后自己消失。
  String _dimHud = '';

  /// 左右翻页的分页控制器（只在 `_pageTurn` 时用）。
  final _pageController = PageController();

  /// 上次读到哪一话（有才显示「继续看」，没有就不显示）。
  ComicOnlineProgress? _resume;

  /// 书架状态读不出来时的说明（不挡住看书）。
  String? _shelfNote;

  /// "现在读的是离线内容"的说明。
  ///
  /// 为什么不复用 [_shelfNote]：那个字段会被 [_refreshShelfFlags] **整体重写**
  /// （读书架成功就设成 null），离线提示写进去会被当场抹掉 —— 界面看着就像没兜底。
  String? _offlineNote;
  ComicChapterRef? _chapter;
  List<String> _images = const [];
  int _imageIndex = 0;

  /// 底部控制栏是否显示。默认显示几秒后自己收起；点画面任意处可再叫出来 / 收起来。
  /// （2026-10-02 用户报"最下面这个影响观看，不能隐藏" —— 一直压着画面确实碍事。）
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  /// 阅读器里是否已经开了"屏幕常亮 + 沉浸全屏"（进出各做一次，别反复设）。
  bool _readerImmersive = false;

  /// 整话的图**还在取**：这时 `_images.length` 只是"已经取到几张"，
  /// 不能拿它当总数写出来（用户看到过"1 / 1 张"，其实整话 209 张 —— 就是"页数不对"）。
  bool _imagesStreaming = false;

  /// 下一话预取（只在本话快读完时才动手，见 `_maybePrefetchNext`）。
  late final ComicChapterPrefetcher _prefetcher;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sources = _builtinComicSources();
    _source =
        widget.source ??
        (_sources.isNotEmpty
            ? _sources.first
            : ComicSource.tryParse(kSeedComicSourceJson)!);
    _relayToken = widget.relayToken?.trim() ?? '';
    if (widget.targetBuilder != null) {
      _target = widget.targetBuilder!();
    } else {
      _webController = ComicSourceWebViewController();
      _target = _webController!.target;
    }
    _cache = widget.imageCache ?? ComicImageCache();
    // 服务按"当前源 + 当前令牌"组：令牌可能是异步读出来的（设置里），
    // 先按注入的值组一次，读到之后再重建 —— 界面不必为这一步卡住。
    _service = _makeService();
    _downloader.setLoadImages(
      (chapterUrl) => _service.chapterImages(chapterUrl),
    );
    // 「仅 Wi-Fi 下载」按设置生效（默认开；读不到网络类型就不拦，见那个文件里的立场）。
    wireComicOfflineNetworkGuard(_downloader);
    // 上次没下完的（被杀掉 / 被"仅 Wi-Fi"拦下）在这里自己接着下：用户多半就是
    // 在看漫画时点的下载，等他要逛到「离线下载」页才续，等于白等。策略不允许就
    // 保持暂停（那条取舍见 `autoResumeIfAllowed`）。
    unawaited(() async {
      try {
        await _downloader.loadInterrupted();
        await _downloader.autoResumeIfAllowed();
      } catch (_) {
        // 续下失败不影响看漫画：用户手动点「继续全部」也行。
      }
    }());
    _prefetcher = ComicChapterPrefetcher(
      loadImages: (chapterUrl) => _service.chapterImages(chapterUrl),
      cache: _cache,
    );
    _library = widget.libraryStore ?? ComicLibraryStore();
    _prefs = widget.readerPrefs ?? ComicReaderPrefs();
    // 预热离线库：一次平台通道往返，之后"本机有没有这一话"都是纯路径计算。
    unawaited(_offline.warmUp());
    _progress = widget.progressStore ?? ComicOnlineProgressStore();
    _loadPrefs();
    // 分类列表要等 WebView 就绪，放到第一帧之后（失败不挡搜索，只写在界面上一行）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

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

  /// 组一次服务：中转按**当前源 + 当前令牌**算（切源 / 拿到令牌后都要重来一次）。
  /// 图片缓存也要跟着换 —— 中转上的图没令牌就是一张都下不来（每张 401）。
  ComicOnlineService _makeService() {
    final spec = _source.relay;
    _relay = (spec != null && _relayToken.isNotEmpty)
        ? ComicRelay(endpoint: spec.endpoint, token: _relayToken)
        : null;
    final service = ComicOnlineService(
      target: _target,
      source: _source,
      relay: _relay,
      waitTimeout: widget.waitTimeout,
      listTimeout: widget.listTimeout,
      openTimeout: widget.openTimeout,
    );
    if (widget.imageCache == null) {
      _cache = ComicImageCache(headerFor: service.headersFor);
    }
    return service;
  }

  /// 令牌从哪来：注入的优先（生产由书库页取好）；否则去设置里读一次。
  /// 只在"这份源**配了中转**"时才去读 —— 没配 relay 的源用不上令牌，别白读一次。
  ///
  /// 令牌是**可选**的：有就经自己的服务器取（中转），**没有就直连站点**（默认那条）。
  /// 拿到令牌要连服务一起换 —— `_relay` 是在 `_makeService()` 里按令牌算出来的，
  /// 只改 `_relayToken` 不会换路（当初就漏了这一步）。
  Future<void> _resolveRelayToken() async {
    if (widget.relayToken != null) return;
    if (!_source.hasRelay) return;
    final token = await loadComicRelayToken();
    if (!mounted || token.isEmpty) return;
    _relayToken = token;
    _swapService();
  }

  /// 换一次服务：**先把旧的关掉**（它可能握着 http 连接池），再按当前源 / 令牌建新的。
  void _swapService() {
    final old = _service;
    setState(() {
      _service = _makeService();
      // 令牌异步读出来之后服务是新的：下载队列取图地址也要跟着换。
      _downloader.setLoadImages(
        (chapterUrl) => _service.chapterImages(chapterUrl),
      );
    });
    old.close();
  }

  @override
  void dispose() {
    // 退出页面时把状态栏和常亮还回去（在阅读器里被 pop 掉也要还）。
    if (_readerImmersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _setWakelock(false);
      _readerImmersive = false;
    }
    _chromeTimer?.cancel();
    _dimHudTimer?.cancel();
    _pageController.dispose();
    _keyController.dispose();
    _scrollController.dispose();
    _service.close();
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

  /// 读翻页偏好与调暗档位（读不出来就用默认：竖向连续 + 不压暗）。
  Future<void> _loadPrefs() async {
    bool v = false;
    double dim = 0;
    bool hintSeen = true;
    try {
      v = await _prefs.pageTurn();
      dim = await _prefs.dimLevel();
      hintSeen = await _prefs.pageTurnHintSeen();
    } catch (_) {
      v = false;
      dim = 0;
      hintSeen = true;
    }
    if (!mounted) return;
    setState(() {
      _pageTurn = v;
      _dim = dim;
      _pageTurnHintSeen = hintSeen;
      // 只在「左右翻页」时提示一次：竖向连续本来就是他要的，没什么可切的。
      _showPageTurnHint = v && !hintSeen;
    });
  }

  /// 只提示一次的那条要不要显示。
  bool _showPageTurnHint = false;

  /// 那条提示"已经看过了"没有（点提示本身、或点 ✕ 才算看过）。
  ///
  /// **手动切到左右翻页不算"看过"**：他可能只是点着玩，并不知道这个图标和上下滑有关系
  /// —— 而那正是他抱怨的场景（在页漫里上下滑，结果只是屏幕变暗）。
  bool _pageTurnHintSeen = true;

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

  Timer? _dimHudTimer;

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

  /// 这本书在不在书架里 + 上次读到哪一话（两个都读真的，不猜）。
  Future<void> _refreshShelfFlags() async {
    final book = _book;
    if (book == null) return;
    bool inShelf = false;
    ComicOnlineProgress? progress;
    String? note;
    try {
      inShelf = (await _library.fetch()).any(
        (b) => b.onlineUrl == book.bookUrl,
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加入书架失败：${_describe(e)}')),
      );
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
    _maybePrefetchNext(book, chapter, index);
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

  /// 上一话 / 下一话。
  ///
  /// 目录是**正序**的（index 大的更晚）：实测 `https://yemancomic.com/book/7530/`
  /// 页面里第 1 条是「1卷」、最后一条是「第1193话」，规则引擎按文档顺序取，所以
  /// App 拿到的 `book.chapters` 也是第 1 话在前。
  ///
  /// 这里曾经按"倒序"写反过：左边那颗按钮标着「下一话」却打开上一话（2026-09-30 修）。
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
    return PopScope(
      // 系统返回（手势 / 返回键）跟左上角箭头走同一条路：**先一层层退**，实在没有
      // 上一层了才退出本页。少了这一层，在阅读里按返回会直接回到书库 —— 看起来
      // 就是"没一层层退"（2026-09-29 用户报的）。
      canPop: _levels.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_mode) {
            _Mode.search => '在线漫画',
            _Mode.book => _book?.name ?? '详情',
            _Mode.reader => _chapter?.title ?? '阅读',
          }),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          actions: [_sourceMenu()],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _body()),
            // 离屏 WebView：取数在它里面跑，用户看不见（1×1、不可点）。
            if (_webController != null) _webController!.buildOffscreen(),
          ],
        ),
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
            onLongPress: () => _openZoom(_images[_imageIndex]),
            child: PageView.builder(
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
                  offline: _offline,
                  offlineBookUrl: _book?.bookUrl ?? '',
                  offlineChapterUrl: _chapter?.url ?? '',
                ),
              ),
            ),
          ),
          // 后面的图还在取：顶部挂一条进度，别让人以为是卡住了。
          if (_busy)
            Positioned(top: 0, left: 0, right: 0, child: _loadingBanner()),
          // 只提示一次：「喜欢上下滑动读？点这里换成竖向连续」。
          Positioned(
            left: 0,
            right: 0,
            top: _busy ? 44 : 8,
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
          Positioned(left: 0, right: 0, bottom: 0, child: _readerChrome()),
        ],
      );
    }
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleChrome,
          onLongPress: () => _openZoom(_images[_imageIndex]),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              final count = _images.length;
              if (count == 0) return false;
              final max = n.metrics.maxScrollExtent;
              // 折算出"滚到第几张"：顶部=第 1 张，底部=最后一张。
              // 老写法 `per = max / count` 在**底部**会算出 count（越界一位），
              // 页面就写成 "210 / 209 张" 这种；用 (count-1) 并夹住范围才两头都对
              // （2026-10-02 用户报"最下面页数显示不对"）。
              final idx = max <= 0
                  ? 0
                  : ((n.metrics.pixels / max) * (count - 1))
                        .round()
                        .clamp(0, count - 1);
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
                offline: _offline,
                offlineBookUrl: _book?.bookUrl ?? '',
                offlineChapterUrl: _chapter?.url ?? '',
                // 预取后面两张：翻页时基本就是本地读盘了。
                prefetch: _images.skip(i + 1).take(2).toList(),
              ),
            ),
          ),
        ),
        if (_busy)
          Positioned(top: 0, left: 0, right: 0, child: _loadingBanner()),
        Positioned(left: 0, right: 0, bottom: 0, child: _readerProgressLine()),
        Positioned.fill(child: _dimOverlay()),
        Positioned.fill(child: _dimHudView()),
        Positioned(left: 0, right: 0, bottom: 0, child: _readerChrome()),
      ],
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
    if (target >= _images.length) {
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
  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  /// 页码文案。取完才给总数；还在取时只说"已取到几张"。
  String _pageLabel() {
    final n = _images.length;
    if (n == 0) return '第 1 张';
    final at = (_imageIndex + 1).clamp(1, n);
    if (_imagesStreaming) return '第 $at 张 · 整话还在取（已取到 $n 张）';
    return '$at / $n 张';
  }

  /// 常驻的一条 2px 进度线：收起控制栏时也知道读到哪了（占位极小，不挡画面）。
  Widget _readerProgressLine() {
    final n = _images.length;
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
      child: Row(
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
            onPressed: prev == null || _busy ? null : () => _openChapter(prev),
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
            onPressed: next == null || _busy ? null : () => _openChapter(next),
            child: const Text('下一话', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

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
    this.prefetch = const [],
    this.offline,
    this.offlineBookUrl = '',
    this.offlineChapterUrl = '',
  });

  final String url;
  final ComicImageCache cache;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _CachedImage(
        url: url,
        cache: cache,
        fit: BoxFit.fitWidth,
        offline: offline,
        offlineBookUrl: offlineBookUrl,
        offlineChapterUrl: offlineChapterUrl,
      ),
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
    this.offline,
    this.offlineBookUrl = '',
    this.offlineChapterUrl = '',
    this.offlineCover = false,
  });

  final String url;
  final ComicImageCache cache;
  final BoxFit fit;

  /// 离线库：有就先在本机找（**命中不发请求** → 飞行模式也能读）。
  final ComicOfflineStore? offline;
  final String offlineBookUrl;
  final String offlineChapterUrl;

  /// 这是**封面**（按"这本书的封面"去找，而不是按某一话的图去找）。
  final bool offlineCover;

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
        await Future<void>.delayed(
          Duration(milliseconds: 1500 * _autoRetries),
        );
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
    return content;
  }
}
