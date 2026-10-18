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

import '../domain/comic_auto_append.dart';
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
import '../data/comic_sync_ops.dart';
import '../domain/comic_relay.dart';
import '../domain/comic_sync.dart';
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

part 'comic_online_page_reader.part.dart';
part 'comic_online_page_browse.part.dart';
part 'comic_online_page_reader_chrome.part.dart';
part 'comic_online_page_widgets.part.dart';

/// 书源菜单里「自检这份源」那一项的取值：菜单值的类型是 `Object`
/// （既能装一份源，也能装这一项），命中它就开自检页。
const Object _kSelfCheckItem = 'comicSourceSelfCheck';

/// 读到"还剩几张"就值得开始预取下一话：留 2 张的余量，够用户在翻页时把下一话开头
/// 那几张图下完。设成 0（读到最后一张才取）就来不及了 —— 那时候用户已经在点了。
const int _kPrefetchTriggerPages = 2;

/// 竖向连续里"快到底了"的距离：滚到离末尾这么近就把下一话接上来。
/// 取成 1500 是"一屏半"左右 —— 用户还在读最后几张时请求就已经回来了，
/// 接着往下滑是无缝的；再早去接会白花流量（他可能这次就读这一话）。
const double _kAutoNextTriggerPx = 1500;

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
    this.syncService,
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

  /// 跨设备同步（收藏 / 阅读进度）。用例注入假的；null = 按手机上存的令牌现建
  /// （没配令牌就是"这台设备不同步"，页面静默跳过 —— 不是错误）。
  final ComicSyncService? syncService;

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

/// 基类：字段 + 各簇共用的核心方法。
///
/// 拆成 part 之后，方法簇挂在 `mixin` 上（见各 `*.part.dart`）。
/// 为什么用 mixin 而不是 extension：`setState` 是 `State` 的 **protected**
/// 成员，只有「State 子类」与「on 类型是它的 mixin」才允许调用，
/// extension 挂在 State 子类上会触发 invalid_use_of_protected_member
/// （api_hub_page.dart 里记着同一条结论）。
abstract class _ComicOnlinePageStateBase extends State<ComicOnlinePage> {
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

  /// 跨设备同步：懒建（第一次真要用才去读设置/建客户端）。
  ComicSyncService? _sync;
  bool _syncResolved = false;
  bool _syncBusy = false;
  Timer? _syncTimer;

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

  /// 自动接上来的**下一话**（竖向连续里滚到本话末尾就接，见 [_appendNext]）。
  ///
  /// 为什么不直接拼进 `_images`：`_images` 是"当前这一话"，取图、逐批显示、预取
  /// 三种逻辑都围着它转；拼进去会把这三种逻辑一起带歪（预取的"下一话"会变成自己、
  /// 逐批显示会把上一话的张数当成本话的）。所以显示层另用一个"整条列表"视图
  /// （[_flatItems]）把"当前话 + 已接上的几话"看成一串，取图逻辑一行都不用改。
  List<_AppendedChapter> _appended = const [];

  /// 正在接下一话：滚动会反复触发，得挡住重复请求。
  bool _appending = false;

  /// 接下一话失败的原因（写在列表末尾那条分隔上 —— 不弹窗、不打断正在读的这一话）。
  String _appendError = '';

  /// 自动加载下一话（默认开，可在亮度面板里关）。关掉 = 回到手动点「下一话」。
  bool _autoNext = true;

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

  String _describe(Object e) {
    if (e is ComicProbeException || e is ComicImageException) return '$e';
    return describeComicProbeError(e);
  }

  /// 读翻页偏好与调暗档位（读不出来就用默认：竖向连续 + 不压暗）。
  Future<void> _loadPrefs() async {
    bool v = false;
    double dim = 0;
    bool hintSeen = true;
    bool autoNext = true;
    try {
      v = await _prefs.pageTurn();
      dim = await _prefs.dimLevel();
      hintSeen = await _prefs.pageTurnHintSeen();
      autoNext = await _prefs.autoNextChapter();
    } catch (_) {
      v = false;
      dim = 0;
      hintSeen = true;
      autoNext = true;
    }
    if (!mounted) return;
    setState(() {
      _pageTurn = v;
      _dim = dim;
      _pageTurnHintSeen = hintSeen;
      _autoNext = autoNext;
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

  Timer? _dimHudTimer;

  /// 同步入口：合并"进页面""收藏变了""进度变了"这些触发点，避免每动一下就发一次请求。
  ///
  /// 为什么必须防抖：翻页每翻一次都会存进度，直连打的是 `/opsapi/sync`，
  /// 不合并的话一话能打上百次请求 —— 服务端有速率限制，用户也会白耗流量。
  Future<void> _syncSoon({bool immediate = false}) async {
    _syncTimer?.cancel();
    if (!immediate) {
      _syncTimer = Timer(const Duration(seconds: 5), () {
        unawaited(_syncNow());
      });
      return;
    }
    await _syncNow();
  }

  /// 真同步一次。**任何失败都吞掉**：同步不该在看书时弹错、更不该打断翻页。
  Future<void> _syncNow() async {
    if (_syncBusy) return;
    if (!_syncResolved) {
      _syncResolved = true;
      try {
        _sync =
            widget.syncService ??
            await createComicSyncService(
              libraryStore: _library,
              progressStore: _progress,
            );
      } catch (_) {
        _sync = null;
      }
    }
    final sync = _sync;
    if (sync == null) return;
    _syncBusy = true;
    try {
      final outcome = await sync.syncNow();
      if (!mounted || outcome.skipped) return;
      // 别处加了/删了收藏：书架状态要跟着刷新（按钮上写着"加入书架"就还是没加）。
      if (outcome.addedBooks > 0 || outcome.removedBooks > 0) {
        await _refreshShelfFlags();
      }
    } catch (_) {
      // 网络/令牌/服务端问题：下次自然还会再试一次。
    } finally {
      _syncBusy = false;
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

  // 下面几项由阅读器界面簇（mixin 链末尾）实现，先在这里声明，
  // 好让排在它前面的簇能调用 —— 与 api_hub_page 的拆分同一套办法。
  void _scheduleChromeHide();
}

class _ComicOnlinePageState extends _ComicOnlinePageStateBase
    with _ComicReaderMixin, _ComicBrowseMixin, _ComicReaderChromeMixin {
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
    // 进页面顺带同步一次：换台设备打开就能看到另一台的收藏与进度。
    // 不 await（同步是顺带做的事，绝不能挡住开页面），失败也只记在状态里。
    unawaited(_syncSoon(immediate: true));
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
    _syncTimer?.cancel();
    _pageController.dispose();
    _keyController.dispose();
    _scrollController.dispose();
    _service.close();
    super.dispose();
  }

  // ── 动作 ──────────────────────────────────────────────────────

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
        // 阅读态**不要 AppBar**（2026-10-02 用户报「最上面空太多了，争取漫画铺满全屏」）：
        // AppBar 是常驻的，一进阅读就先吃掉一整条屏高（状态栏 + 56），而标题/返回
        // 在读的时候并不需要。阅读态改用压在画面上的 `_readerTopBar()`，
        // 与底部控制栏同一条命：点一下出现、4 秒自己收。
        appBar: _mode == _Mode.reader
            ? null
            : AppBar(
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
}

/// 阅读列表里的一项：一张图 + 它属于哪一话。
///
/// 自动加载下一话之后，一屏列表会跨好几话 —— 页码、进度、离线取图都得按
/// **这一项所属的那一话**算，不能按"进来时那一话"算（那是 2026-10-02 加自动接话
/// 之前的老假设）。
class _ReaderItem {
  const _ReaderItem({
    required this.url,
    required this.chapter,
    required this.indexInChapter,
    required this.chapterImageCount,
    required this.chapterStart,
  });

  final String url;
  final ComicChapterRef chapter;
  final int indexInChapter;

  /// 这一话一共几张（页码文案要用"本话第几张 / 本话共几张"）。
  final int chapterImageCount;

  /// 是不是某一话的第一张（要在它前面插一条"第 X 话"的分隔）。
  final bool chapterStart;
}

/// 自动接上来的一话（整话的图）。
class _AppendedChapter {
  const _AppendedChapter({required this.chapter, required this.images});

  final ComicChapterRef chapter;
  final List<String> images;
}
