// 离线下载的队列（"下载到本机，断网也能读"那一半）。
//
// 形状与理由：
//   * **一话一个任务、任务之间串行**（一话下完再下一话）。漫画一话 20~200 张，
//     几话同时去挤图床正是 2026-10-01 那次"连接被掐断（errno 104）"的起因之一；
//     话内的并发交给 `ComicImageCache`，取值见 [defaultChapterParallel]（比阅读时的 4 更保守）。
//   * **续传认"文件在不在"，不认计数**（见 `ComicImageCache.fetch(dest:)`）：杀进程、
//     手机关机、用户点暂停之后，重新开始时缺哪张下哪张 —— 计数会飘，文件不会。
//   * 取图**不另写一套**：走 `ComicImageCache.fetch(dest:)`，于是图床那套"每次连接
//     截止时间 / :666 换 443 / 被掐断按同一地址重试 / 错误说人话"原样继承。
//   * 状态落进清单：`running` 表示"上次下到一半就没了" —— 启动时改成 `paused`，
//     等用户点继续（不偷偷在移动网络上跑）。
library;

import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'comic_image_cache.dart';
import 'comic_download_keepalive.dart';
import 'comic_offline_store.dart';

/// 一个下载任务的状态。
enum ComicOfflineJobState {
  queued,
  running,
  done,
  paused,
  failed,
}

/// 队列里的一个任务 = 一话。
class ComicOfflineJob {
  ComicOfflineJob({
    required this.bookUrl,
    required this.chapterUrl,
    required this.chapterTitle,
    this.bookTitle = '',
    this.cover = '',
    this.state = ComicOfflineJobState.queued,
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
    this.error = '',
  });

  final String bookUrl;
  final String chapterUrl;
  final String chapterTitle;
  final String bookTitle;
  final String cover;

  ComicOfflineJobState state;
  int done;
  int total;
  int bytes;
  String error;

  String get key => '$bookUrl|$chapterUrl';

  /// 0~1；还不知道总数时返回 0（界面显示"准备中"）。
  double get progress => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  bool get isDone => state == ComicOfflineJobState.done;

  /// 用户**自己按的**暂停（只存内存，不落盘）。
  ///
  /// 为什么要有这个标记：启动续下要挑"该接着下的"（上次被杀掉、或者被"仅 Wi-Fi"拦下），
  /// 但**不能把用户手动暂停的也拉起来** —— 那就成了"我停了它，它自己又跑"。
  /// 光看 `paused` 分不出这两种，所以暂停时打个标，用户点继续时清掉。
  bool userPaused = false;
}

/// 离线下载队列。
class ComicOfflineDownloader extends ChangeNotifier {
  ComicOfflineDownloader({
    ComicOfflineStore? store,
    ComicImageCache? cache,
    Future<List<String>> Function(String chapterUrl)? loadImages,
    Future<bool> Function()? networkAllowed,
    ComicDownloadKeepAlive? keepAlive,
    this.imageAttempts = defaultImageAttempts,
    this.retryDelay = const Duration(milliseconds: 1200),
  }) : store = store ?? ComicOfflineStore(),
       cache = cache ?? ComicImageCache(maxParallel: defaultChapterParallel),
       _keepAlive = keepAlive ?? ComicDownloadKeepAlive(),
       _loadImages = loadImages,
       _networkAllowed = networkAllowed ?? (() async => true);

  /// 一话之内同时下几张图。
  ///
  /// **取 3 是量出来的（2026-10-02，同一批 10 张图各跑两轮，失败都是 0）**：
  /// 并发 2 → 6.0s / 3 → 4.5s / 4 → 6.2s。3 比 2 快约四分之一，再往上反而变慢
  /// （对端开始推回来，连接建立成了瓶颈）。想重新量：
  /// `flutter test --tags live test/features/comic/comic_download_parallel_live_test.dart`
  /// （默认 footprint 很小 —— 一口气打几百个请求的话图床会回 400，量到的就不是并发的锅）。
  /// 话与话之间仍然串行：整本一起挤上去正是 2026-10-01 那次「连接被掐断」的起因。
  static const int defaultChapterParallel = 3;

  /// 单张图允许试几个地址（默认比前台读图多：下载是连发几百张，一次抖动
  /// 就废掉整话，代价完全不对等）。
  static const int defaultImageAttempts = 6;

  /// 一轮都不成时，等一会儿再整轮重来一次（图床那种"掐断"多是短时状态）。
  final Duration retryDelay;
  final int imageAttempts;

  /// 全 App 共用一份：**下载要在离开这个页面之后继续**，所以不能是页面级对象。
  static ComicOfflineDownloader? _shared;

  static ComicOfflineDownloader shared({
    Future<List<String>> Function(String chapterUrl)? loadImages,
  }) {
    final existing = _shared;
    if (existing != null) return existing;
    final made = ComicOfflineDownloader(loadImages: loadImages);
    _shared = made;
    return made;
  }

  @visibleForTesting
  static void resetShared() => _shared = null;

  final ComicOfflineStore store;
  final ComicImageCache cache;

  /// 取一话的图片地址（App 里接 ComicOnlineService.chapterImages）。
  Future<List<String>> Function(String chapterUrl)? _loadImages;

  /// 现在允不允许下载（仅 Wi-Fi 策略由界面/设置注入）。默认允许（测试与桌面）。
  Future<bool> Function() _networkAllowed;

  /// 「这次也用流量」的一次性放行（用完即失效）。
  ///
  /// 为什么是一次性的：做成常开等于把"仅 Wi-Fi"这个设置悄悄关掉 ——
  /// 用户那次点了"用流量"是因为他**知道**自己在 5G 上，下次未必。
  bool _allowOnce = false;

  /// 这一话是不是被"只在 Wi-Fi 下下载"拦下的。
  bool _wifiHeld(ComicOfflineJob job) =>
      job.state == ComicOfflineJobState.paused && job.error.contains('Wi-Fi');

  /// 还有任务在等 Wi-Fi（界面用它决定要不要显示"这次用流量"）。
  bool get waitingForWifi => _jobs.any(_wifiHeld);

  /// 「这次也用流量」：本轮放行一次。
  ///
  /// 除了开一次性放行，必须**把它们从 paused 重新排回队列** —— 被拦下的任务是 paused，
  /// 而 [_pump] 只挑 queued，于是用户点了按钮什么都不会发生（2026-10-01 用户报的
  /// 「点击这次用流量没反应」就是这个：按钮本身没坏，是没人把它们叫回来）。
  void allowNetworkOnce() {
    _allowOnce = true;
    for (final j in _jobs) {
      if (_wifiHeld(j)) {
        j.state = ComicOfflineJobState.queued;
        j.error = '';
      }
    }
    notifyListeners();
    unawaited(_pump());
  }

  final List<ComicOfflineJob> _jobs = <ComicOfflineJob>[];
  bool _pumping = false;
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  /// 队列快照（界面用）。
  List<ComicOfflineJob> get jobs => List<ComicOfflineJob>.unmodifiable(_jobs);

  bool get isBusy => _jobs.any((j) => j.state == ComicOfflineJobState.running);

  ComicOfflineJob? get runningJob {
    for (final j in _jobs) {
      if (j.state == ComicOfflineJobState.running) return j;
    }
    return null;
  }

  ComicOfflineJob? jobFor(String bookUrl, String chapterUrl) {
    for (final j in _jobs) {
      if (j.key == '$bookUrl|$chapterUrl') return j;
    }
    return null;
  }

  List<ComicOfflineJob> jobsOfBook(String bookUrl) =>
      _jobs.where((j) => j.bookUrl == bookUrl).toList();

  void setLoadImages(Future<List<String>> Function(String chapterUrl) fn) {
    _loadImages = fn;
  }

  /// 开始/继续一段下载：把前台保活挂上（幂等），并从头数这一轮的账。
  ///
  /// 为什么在"真的挑到任务"时才挂（而不是 enqueue 就挂）：入队之后可能立刻被
  /// "仅 Wi-Fi"拦下 —— 那种情况一个字节都不会下，挂个"正在下载"的通知就是骗人。
  void _startKeepAlive(String text) {
    if (!_keepAliveOn) {
      _keepAliveOn = true;
      _sessionDone = 0;
      _sessionFailed = 0;
    }
    _lastNoticeAt = DateTime.now();
    unawaited(_keepAlive.start(title: '漫画下载中', text: text));
  }

  /// 更新通知文案（有节流：默认 2 秒最多一次）。
  void _updateKeepAlive(String text, {bool force = false}) {
    if (!_keepAliveOn) return;
    final now = DateTime.now();
    final last = _lastNoticeAt;
    if (!force && last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastNoticeAt = now;
    unawaited(_keepAlive.update(text: text));
  }

  /// 队列空了：收工。
  ///
  /// [userStopped] = 用户自己暂停/取消（那就不用告诉他"下载完成"，直接把通知撤掉）。
  void _stopKeepAlive({required bool userStopped}) {
    if (!_keepAliveOn) return;
    _keepAliveOn = false;
    _lastNoticeAt = null;
    if (userStopped) {
      unawaited(_keepAlive.stop());
      return;
    }
    if (_sessionDone == 0 && _sessionFailed == 0) {
      // 一件都没做成（比如全被拦下/全失败在入队阶段）：不该留"下载完成"的通知。
      unawaited(_keepAlive.stop());
      return;
    }
    final text = _sessionFailed > 0
        ? '完成 $_sessionDone 话 · 失败 $_sessionFailed 话（可在「离线下载」里重试）'
        : '共 $_sessionDone 话，已存到本机';
    unawaited(
      _keepAlive.finish(
        title: _sessionFailed > 0 ? '漫画下载有失败' : '漫画下载完成',
        text: text,
      ),
    );
  }

  /// 队列里的状态文案：通知与界面用的是同一份事实。
  String _queueSummary() {
    final running = _jobs.where((j) => j.state == ComicOfflineJobState.running);
    final waiting = _jobs
        .where((j) => j.state == ComicOfflineJobState.queued)
        .length;
    final cur = running.isEmpty ? null : running.first;
    if (cur == null) return '还剩 $waiting 话';
    final title = cur.chapterTitle.trim().isEmpty ? '这一话' : cur.chapterTitle;
    final pages = cur.total > 0 ? '（${cur.done}/${cur.total} 张）' : '';
    return '$title$pages · 还剩 $waiting 话';
  }

  void setNetworkAllowed(Future<bool> Function() fn) {
    _networkAllowed = fn;
  }

  /// 入队：把这几话加进队列（已经在队列里/已经下完的跳过），并开始跑。
  Future<void> enqueue({
    required String bookUrl,
    required List<ComicOfflineChapter> chapters,
    String bookTitle = '',
    String cover = '',
  }) async {
    // 清单先建好：书名/封面/目录都要在里面，断网时才进得了详情页。
    final book = await store.loadBook(bookUrl) ??
        ComicOfflineBook(bookUrl: bookUrl, title: bookTitle, cover: cover);
    if (book.title.isEmpty) book.title = bookTitle;
    if (book.cover.isEmpty) book.cover = cover;
    for (final c in chapters) {
      final known = _findChapter(book, c.url);
      if (known == null) {
        book.chapters.add(
          ComicOfflineChapter(url: c.url, title: c.title, images: c.images),
        );
      } else if (c.images.isNotEmpty) {
        known.images
          ..clear()
          ..addAll(c.images);
      }
    }
    await store.saveBook(book);

    for (final c in chapters) {
      final entry = _findChapter(book, c.url)!;
      if (entry.isDone) continue; // 已经下完，不重复下
      if (jobFor(bookUrl, c.url) != null) continue; // 已在队列里
      _jobs.add(
        ComicOfflineJob(
          bookUrl: bookUrl,
          chapterUrl: c.url,
          chapterTitle: c.title,
          bookTitle: book.title,
          cover: book.cover,
          total: entry.total,
          done: entry.done,
        ),
      );
    }
    notifyListeners();
    unawaited(_fetchCover(bookUrl, book.cover));
    unawaited(_pump());
  }

  /// 取一张图（下载用）：先让缓存按候选地址自己试 [imageAttempts] 个地址，
  /// 整轮都不成就**等一会儿再整轮重来一次**。
  ///
  /// 为什么要多这一层（2026-10-02 用户截图）：下载是连发几百张，一张图被图床掐断
  /// 就让整话失败，用户看到的是「0/1 章 · 1 KB」这种最没用的结果 —— 而重试一次的
  /// 成功率远高于"再排一个地址"（掐断是短时状态，隔一秒就过去了）。
  Future<void> _fetchImage(String url, File dest) async {
    try {
      await cache.fetch(
        url,
        lowPriority: true,
        dest: dest,
        maxAttempts: imageAttempts,
      );
    } on ComicImageException catch (e) {
      // 只有"一闪而过"（被掐断 / 连接被提前关掉 / 5xx）才值得整轮重来：
      // HTTP 404、0 字节、地址不合法这种，等一会儿也一样，别拿用户的时间赌。
      if (!e.transient && !e.retryable) rethrow;
      if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      await cache.fetch(
        url,
        lowPriority: true,
        dest: dest,
        maxAttempts: imageAttempts,
      );
    }
  }

  /// 顺手把封面也下下来。
  ///
  /// 封面失败**不影响**下载结果：一本书读得了比封面重要得多，所以这里吞掉异常，
  /// 由封面自己的组件在下次联网时再试。
  Future<void> _fetchCover(String bookUrl, String cover) async {
    if (cover.isEmpty) return;
    try {
      final dest = await store.coverFile(bookUrl, cover);
      if (await dest.exists()) return;
      await _fetchImage(cover, dest);
    } on ComicImageException {
      // 封面是"顺带"，失败不打扰任何人。
    } on FormatException {
      // 同上（地址不合法之类）。
    }
  }

  /// 暂停（正在跑的那一话会在**下完当前这张**之后停下）。
  void pause(String bookUrl, String chapterUrl) {
    final job = jobFor(bookUrl, chapterUrl);
    if (job == null) return;
    job.userPaused = true;
    _userStoppedThisRound = true;
    if (job.state == ComicOfflineJobState.running) {
      _pauseRequested = true;
    } else {
      job.state = ComicOfflineJobState.paused;
      _persist(job);
      notifyListeners();
    }
  }

  /// 暂停全部。
  void pauseAll() {
    _userStoppedThisRound = true;
    for (final j in _jobs) {
      j.userPaused = true;
      if (j.state == ComicOfflineJobState.running) {
        _pauseRequested = true;
      } else if (j.state == ComicOfflineJobState.queued) {
        j.state = ComicOfflineJobState.paused;
      }
    }
    notifyListeners();
  }

  /// 继续（暂停/失败的任务重新排队）。
  ///
  /// 被"只在 Wi-Fi 下下载"拦下的那一话，点「继续」= 用户**现在就要它接着下**，
  /// 所以顺手开一次性放行：否则他会看到"点了没反应"（任务排回去又被同一条策略拦下，
  /// 界面只多了一行字）。2026-10-01 用户报的正是这类观感。
  void resume(String bookUrl, String chapterUrl) {
    final job = jobFor(bookUrl, chapterUrl);
    if (job == null) return;
    if (job.state == ComicOfflineJobState.done) return;
    job.userPaused = false;
    if (_wifiHeld(job)) _allowOnce = true;
    job.state = ComicOfflineJobState.queued;
    job.error = '';
    notifyListeners();
    unawaited(_pump());
  }

  /// 继续全部没下完的（同样：被 Wi-Fi 拦下的按"用户要求现在继续"处理）。
  void resumeAll() {
    for (final j in _jobs) {
      if (j.state == ComicOfflineJobState.paused ||
          j.state == ComicOfflineJobState.failed) {
        j.userPaused = false;
        if (_wifiHeld(j)) _allowOnce = true;
        j.state = ComicOfflineJobState.queued;
        j.error = '';
      }
    }
    notifyListeners();
    unawaited(_pump());
  }

  /// 启动时**在网络策略允许的前提下**自动续下"上次没下完的"。
  ///
  /// 三条取舍（都不是拍脑袋）：
  ///   * 不无条件自动续：那等于**可能在移动网络上自己开始下几百兆** —— 用户没点过头
  ///     （原来 `loadInterrupted` 只标 paused、等人点，就是这个理由）；
  ///   * 也不永不续：杀掉 App 再打开就全停在"已暂停"，点一话动一话，同样没道理；
  ///   * 所以看策略：现在是 Wi-Fi（或用户已关掉"仅 Wi-Fi"）就自己继续，否则保持暂停。
  ///
  /// 只挑 **paused**：`failed` 是"试过、失败了"，重开一次就再撞一遍是白费流量，
  /// 那种要用户点一下（界面上失败那一话给的就是重试图标）。
  Future<int> autoResumeIfAllowed() async {
    bool allowed;
    try {
      allowed = await _networkAllowed();
    } catch (_) {
      allowed = false; // 拿不准就不自动下（省流量那一档）
    }
    if (!allowed) return 0;
    var n = 0;
    for (final j in _jobs) {
      if (j.state != ComicOfflineJobState.paused) continue;
      // 用户自己按的暂停不碰：那就成了"我停了它，它自己又跑"。
      if (j.userPaused) continue;
      // 只有两类该自动接着下：上次被杀掉的、以及当时被"仅 Wi-Fi"拦下的
      // （用户此刻就在 Wi-Fi 上，拦的理由已经不成立了）。
      final wanted =
          _interrupted.contains(_key(j.bookUrl, j.chapterUrl)) || _wifiHeld(j);
      if (!wanted) continue;
      j.state = ComicOfflineJobState.queued;
      j.error = '';
      n++;
    }
    if (n > 0) {
      notifyListeners();
      unawaited(_pump());
    }
    return n;
  }

  ComicOfflineJob? get _nextQueued {
    for (final j in _jobs) {
      if (j.state == ComicOfflineJobState.queued) return j;
    }
    return null;
  }

  /// 清单里找这一话（没有就 null）。
  static ComicOfflineChapter? _findChapter(ComicOfflineBook book, String url) {
    for (final c in book.chapters) {
      if (c.url == url) return c;
    }
    return null;
  }

  /// 取消这一话：队列里去掉 + **把已经下来的文件删掉**（留着会变成看不见的占用）。
  Future<void> cancel(String bookUrl, String chapterUrl) async {
    _userStoppedThisRound = true; // 用户取消：收工不留"下载完成"的通知
    final job = jobFor(bookUrl, chapterUrl);
    if (job != null && job.state == ComicOfflineJobState.running) {
      _cancelRequested = true;
      // 等它自己退出来再删（正在写那一张文件，删了可能留半张）。
      while (jobFor(bookUrl, chapterUrl) != null &&
          jobFor(bookUrl, chapterUrl)!.state == ComicOfflineJobState.running) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    _jobs.removeWhere((j) => j.key == '$bookUrl|$chapterUrl');
    await store.deleteChapter(bookUrl, chapterUrl);
    notifyListeners();
  }

  /// 下载期间的前台保活（通知栏常驻）+ 下完那条通知。
  ///
  /// 为什么要它：Dart 的任务拦不住系统回收进程 —— app 退到后台、内存一紧就被回收，
  /// 队列直接断掉（用户回来只看到进度不动了）。仓库里视频下载 / 远端传输都是同一个模式：
  /// 各起一个前台服务、**通知 ID 分开**（1001 / 1002，这里是 1003），互不干扰。
  final ComicDownloadKeepAlive _keepAlive;

  /// 保活服务现在挂着没有（挂着才需要更新/收工，避免无谓的平台调用）。
  bool _keepAliveOn = false;

  /// 这轮（本次保活）下完了多少话、失败多少话 —— 收工那条通知要报数，不报数等于没说。
  int _sessionDone = 0;
  int _sessionFailed = 0;

  /// 上次更新通知的时间：进度通知不必每张图都刷（平台调用也是有代价的）。
  DateTime? _lastNoticeAt;

  /// 启动时把"上次下到一半就没了"的任务改成暂停。
  ///
  /// 不自动继续：自动继续意味着**可能在移动网络上**自己开始下几百兆 ——
  /// 用户点一下"继续"才是对的（而且他点的时候知道自己现在什么网）。

  /// 上次被杀掉、这次被叫回来的任务（`bookUrl|chapterUrl`）—— 启动续下只认这些。
  final Set<String> _interrupted = <String>{};

  static String _key(String bookUrl, String chapterUrl) => '$bookUrl|$chapterUrl';

  Future<int> loadInterrupted() async {
    var found = 0;
    for (final book in await store.books()) {
      for (final c in book.chapters) {
        final live = jobFor(book.bookUrl, c.url);
        final liveRunning = live != null &&
            (live.state == ComicOfflineJobState.running ||
                live.state == ComicOfflineJobState.queued);
        if (c.state == ComicOfflineState.running && !liveRunning) {
          // 清单说"下到一半"而队列里没有这个任务 = 上次被杀掉了 → 改成暂停等人点。
          c.state = ComicOfflineState.paused;
          await store.saveBook(book);
          _interrupted.add(_key(book.bookUrl, c.url));
          found++;
        }
        if (c.state == ComicOfflineState.done || c.isDone) continue;
        if (jobFor(book.bookUrl, c.url) != null) continue;
        _jobs.add(
          ComicOfflineJob(
            bookUrl: book.bookUrl,
            chapterUrl: c.url,
            chapterTitle: c.title,
            bookTitle: book.title,
            cover: book.cover,
            state: c.state == ComicOfflineState.paused
                ? ComicOfflineJobState.paused
                : ComicOfflineJobState.queued,
            done: c.done,
            total: c.total,
            bytes: c.bytes,
            error: c.error,
          ),
        );
      }
    }
    if (found > 0 || _jobs.isNotEmpty) notifyListeners();
    return found;
  }

  // ── 跑队列 ────────────────────────────────────────────────────

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      // 一次放行覆盖**本轮**排着的所有任务（用户点"这次也用流量"时看到的就是这些）。
      var allowedOnce = _allowOnce;
      _allowOnce = false;

      while (true) {
        final job = _nextQueued;
        if (job == null) break;

        if (!allowedOnce && !await _networkAllowed()) {
          job.state = ComicOfflineJobState.paused;
          job.error = '按设置：只在 Wi-Fi 下下载';
          _persist(job);
          notifyListeners();
          break;
        }

        _startKeepAlive(_queueSummary());
        final ok = await _runJob(job);
        if (ok) {
          _sessionDone++;
        } else {
          _sessionFailed++; // 失败或用户暂停，下面按队列状态区分怎么收工
        }
        if (!ok) break; // 失败/被暂停：停下，剩下的留在队列里等用户
      }
    } finally {
      _pumping = false;
      notifyListeners();
      // 队列空了才算收工；还有排队的（比如刚才被拦下）就继续挂着。
      if (_nextQueued == null && !_pumping) {
        final paused = _jobs.any(
          (j) => j.state == ComicOfflineJobState.paused && j.userPaused,
        );
        _stopKeepAlive(userStopped: paused || _userStoppedThisRound);
        _userStoppedThisRound = false;
      }
    }
  }

  /// 这一轮里用户点过暂停/取消（用来决定"收工"时留不留"下载完成"的通知）。
  bool _userStoppedThisRound = false;

  /// 跑一话。返回 false 表示队列该停了（暂停/失败）。
  Future<bool> _runJob(ComicOfflineJob job) async {
    job.state = ComicOfflineJobState.running;
    job.error = '';
    notifyListeners();

    final book = await store.loadBook(job.bookUrl) ??
        ComicOfflineBook(bookUrl: job.bookUrl);
    var entry = _findChapter(book, job.chapterUrl);
    if (entry == null) {
      entry = ComicOfflineChapter(url: job.chapterUrl, title: job.chapterTitle);
      book.chapters.add(entry);
    }

    try {
      // 图片地址：清单里已经有就直接用（**断网续传就靠这一条**，不用再问站点）。
      if (entry.images.isEmpty) {
        final loader = _loadImages;
        if (loader == null) {
          throw const FormatException('没有接入"取一话图片地址"的方法');
        }
        entry.images.addAll(await loader(job.chapterUrl));
      }
      if (entry.images.isEmpty) {
        throw const FormatException('这一话没取到图片地址（站点可能改版）');
      }
      job.total = entry.images.length;
      entry.state = ComicOfflineState.running;
      await store.saveBook(book);
      notifyListeners();

      var saved = 0;
      for (final url in entry.images) {
        if (_pauseRequested || _cancelRequested) {
          await _finishInterrupted(job, entry, book);
          return false;
        }
        final dest = await store.fileFor(job.bookUrl, job.chapterUrl, url);
        final already = await dest.exists() ? dest : null;
        if (already != null) {
          // 已经下过（上次下到一半）：算进进度，不重复下载。
          job.done++;
          job.bytes += await already.length();
          continue;
        }
        await _fetchImage(url, dest);
        job.done++;
        job.bytes += await dest.length();
        entry.done = job.done;
        entry.bytes = job.bytes;
        saved++;
        // 每 5 张落一次清单：太勤是白写盘，太懒则杀进程后丢进度。
        if (saved % 5 == 0) await store.saveBook(book);
        notifyListeners();
        _updateKeepAlive(_queueSummary());
      }

      _interrupted.remove(_key(job.bookUrl, job.chapterUrl));
      // **先落清单再改内存状态**：反过来的话，界面已经显示"下完"而清单里还是 running，
      // 这时候被杀掉，下次启动会把这一话当成"下到一半"（进度全丢）。
      entry
        ..state = ComicOfflineState.done
        ..done = entry.images.length
        ..bytes = job.bytes
        ..error = '';
      await store.saveBook(book);
      job.state = ComicOfflineJobState.done;
      notifyListeners();
      return true;
    } on ComicImageException catch (e) {
      entry
        ..state = ComicOfflineState.failed
        ..error = e.message
        ..done = job.done
        ..bytes = job.bytes;
      await store.saveBook(book);
      job.state = ComicOfflineJobState.failed;
      job.error = e.message;
      notifyListeners();
      return false;
    } on FormatException catch (e) {
      entry
        ..state = ComicOfflineState.failed
        ..error = e.message;
      await store.saveBook(book);
      job.state = ComicOfflineJobState.failed;
      job.error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> _finishInterrupted(
    ComicOfflineJob job,
    ComicOfflineChapter entry,
    ComicOfflineBook book,
  ) async {
    _pauseRequested = false;
    _cancelRequested = false;
    entry
      ..state = ComicOfflineState.paused
      ..done = job.done
      ..bytes = job.bytes;
    await store.saveBook(book);
    job.state = ComicOfflineJobState.paused;
    notifyListeners();
  }

  void _persist(ComicOfflineJob job) {
    unawaited(() async {
      final book = await store.loadBook(job.bookUrl);
      if (book == null) return;
      for (final c in book.chapters) {
        if (c.url != job.chapterUrl) continue;
        c
          ..state = job.state == ComicOfflineJobState.done
              ? ComicOfflineState.done
              : job.state == ComicOfflineJobState.failed
                  ? ComicOfflineState.failed
                  : ComicOfflineState.paused
          ..error = job.error
          ..done = job.done
          ..bytes = job.bytes;
      }
      await store.saveBook(book);
    }());
  }
}
