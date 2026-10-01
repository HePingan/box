// 离线下载的队列（"下载到本机，断网也能读"那一半）。
//
// 形状与理由：
//   * **一话一个任务、任务之间串行**（一话下完再下一话）。漫画一话 20~200 张，
//     几话同时去挤图床正是 2026-10-01 那次"连接被掐断（errno 104）"的起因之一；
//     话内的并发交给 `ComicImageCache`（这里传 maxParallel: 2，比阅读时的 4 更保守）。
//   * **续传认"文件在不在"，不认计数**（见 `ComicImageCache.fetch(dest:)`）：杀进程、
//     手机关机、用户点暂停之后，重新开始时缺哪张下哪张 —— 计数会飘，文件不会。
//   * 取图**不另写一套**：走 `ComicImageCache.fetch(dest:)`，于是图床那套"每次连接
//     截止时间 / :666 换 443 / 被掐断按同一地址重试 / 错误说人话"原样继承。
//   * 状态落进清单：`running` 表示"上次下到一半就没了" —— 启动时改成 `paused`，
//     等用户点继续（不偷偷在移动网络上跑）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'comic_image_cache.dart';
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
}

/// 离线下载队列。
class ComicOfflineDownloader extends ChangeNotifier {
  ComicOfflineDownloader({
    ComicOfflineStore? store,
    ComicImageCache? cache,
    Future<List<String>> Function(String chapterUrl)? loadImages,
    Future<bool> Function()? networkAllowed,
  }) : store = store ?? ComicOfflineStore(),
       cache = cache ?? ComicImageCache(maxParallel: 2),
       _loadImages = loadImages,
       _networkAllowed = networkAllowed ?? (() async => true);

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
    unawaited(_pump());
  }

  /// 暂停（正在跑的那一话会在**下完当前这张**之后停下）。
  void pause(String bookUrl, String chapterUrl) {
    final job = jobFor(bookUrl, chapterUrl);
    if (job == null) return;
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
    for (final j in _jobs) {
      if (j.state == ComicOfflineJobState.running) {
        _pauseRequested = true;
      } else if (j.state == ComicOfflineJobState.queued) {
        j.state = ComicOfflineJobState.paused;
      }
    }
    notifyListeners();
  }

  /// 继续（暂停/失败的任务重新排队）。
  void resume(String bookUrl, String chapterUrl) {
    final job = jobFor(bookUrl, chapterUrl);
    if (job == null) return;
    if (job.state == ComicOfflineJobState.done) return;
    job.state = ComicOfflineJobState.queued;
    job.error = '';
    notifyListeners();
    unawaited(_pump());
  }

  /// 继续全部没下完的。
  void resumeAll() {
    for (final j in _jobs) {
      if (j.state == ComicOfflineJobState.paused ||
          j.state == ComicOfflineJobState.failed) {
        j.state = ComicOfflineJobState.queued;
        j.error = '';
      }
    }
    notifyListeners();
    unawaited(_pump());
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

  /// 启动时把"上次下到一半就没了"的任务改成暂停。
  ///
  /// 不自动继续：自动继续意味着**可能在移动网络上**自己开始下几百兆 ——
  /// 用户点一下"继续"才是对的（而且他点的时候知道自己现在什么网）。
  Future<int> loadInterrupted() async {
    var found = 0;
    for (final book in await store.books()) {
      for (final c in book.chapters) {
        if (c.state == ComicOfflineState.running) {
          c.state = ComicOfflineState.paused;
          await store.saveBook(book);
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
      while (true) {
        final job = _nextQueued;
        if (job == null) break;

        if (!await _networkAllowed()) {
          job.state = ComicOfflineJobState.paused;
          job.error = '按设置：只在 Wi-Fi 下下载';
          _persist(job);
          notifyListeners();
          break;
        }

        final ok = await _runJob(job);
        if (!ok) break; // 失败/被暂停：停下，剩下的留在队列里等用户
      }
    } finally {
      _pumping = false;
      notifyListeners();
    }
  }

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
          _finishInterrupted(job, entry, book);
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
        await cache.fetch(url, lowPriority: true, dest: dest);
        job.done++;
        job.bytes += await dest.length();
        entry.done = job.done;
        entry.bytes = job.bytes;
        saved++;
        // 每 5 张落一次清单：太勤是白写盘，太懒则杀进程后丢进度。
        if (saved % 5 == 0) await store.saveBook(book);
        notifyListeners();
      }

      job.state = ComicOfflineJobState.done;
      entry
        ..state = ComicOfflineState.done
        ..done = entry.images.length
        ..bytes = job.bytes
        ..error = '';
      await store.saveBook(book);
      notifyListeners();
      return true;
    } on ComicImageException catch (e) {
      job.state = ComicOfflineJobState.failed;
      job.error = e.message;
      entry
        ..state = ComicOfflineState.failed
        ..error = e.message
        ..done = job.done
        ..bytes = job.bytes;
      await store.saveBook(book);
      notifyListeners();
      return false;
    } on FormatException catch (e) {
      job.state = ComicOfflineJobState.failed;
      job.error = e.message;
      entry
        ..state = ComicOfflineState.failed
        ..error = e.message;
      await store.saveBook(book);
      notifyListeners();
      return false;
    }
  }

  void _finishInterrupted(
    ComicOfflineJob job,
    ComicOfflineChapter entry,
    ComicOfflineBook book,
  ) {
    _pauseRequested = false;
    _cancelRequested = false;
    job.state = ComicOfflineJobState.paused;
    entry
      ..state = ComicOfflineState.paused
      ..done = job.done
      ..bytes = job.bytes;
    unawaited(store.saveBook(book));
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
