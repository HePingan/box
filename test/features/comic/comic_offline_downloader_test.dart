// 离线下载队列：落盘、续传、仅 Wi-Fi、失败不白跑、串行、崩溃恢复、取消。
//
// 图片用一个**真本地 HTTP 服务器**（绑 127.0.0.1，不联网）：要验的正是连接那一层
// （续传靠"文件在不在"、失败要带出图床的原话），假 fetcher 验不出来。
import 'dart:io';

import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_offline_downloader.dart';
import 'package:box/features/comic/domain/comic_offline_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记账用的本地图床：谁被请求了几次、同时有几条在跑。
class _TestImageHost {
  HttpServer? _server;
  final Map<String, int> hits = <String, int>{};
  int _running = 0;
  int peak = 0;

  /// 这些前缀一律 500（模拟图床抽风 / 那张图挂了）。
  final Set<String> failPrefixes = <String>{};

  /// 这些前缀回指定状态码（用来区分"值得再试"和"再来也一样"）。
  final Map<String, int> statusByPrefix = <String, int>{};

  int get port => _server!.port;

  String img(String name) => 'http://127.0.0.1:$port/img/$name';

  int totalHits() => hits.values.fold(0, (a, b) => a + b);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      final path = req.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;
      _running++;
      if (_running > peak) peak = _running;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final forced = statusByPrefix.entries
            .where((e) => path.startsWith(e.key))
            .map((e) => e.value)
            .firstOrNull;
        if (forced != null) {
          req.response.statusCode = forced;
          await req.response.close();
          return;
        }
        if (failPrefixes.any(path.startsWith)) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('image', 'jpeg');
        req.response.add(List<int>.filled(1024, 9));
        await req.response.close();
      } finally {
        _running--;
      }
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 20),
  String what = '条件',
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('等 $what 超时了（${sw.elapsedMilliseconds}ms）');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tmp;
  late Directory cacheTmp;
  late ComicOfflineStore store;
  late _TestImageHost host;

  const bookUrl = 'https://yemancomic.com/comic/42.html';

  ComicOfflineChapter chapter(String title, List<String> images) =>
      ComicOfflineChapter(url: 'https://yemancomic.com/comic/42/$title.html', title: title, images: images);

  ComicOfflineDownloader downloader({
    required Map<String, List<String>> imagesOf,
    bool wifi = true,
    ComicImageCache? cache,
    Duration retryDelay = Duration.zero,
  }) => ComicOfflineDownloader(
    store: store,
    cache:
        cache ??
        ComicImageCache(maxParallel: 2, tempDirProvider: () async => cacheTmp),
    retryDelay: retryDelay,
    loadImages: (chapterUrl) async {
      for (final e in imagesOf.entries) {
        if (chapterUrl.endsWith(e.key)) return e.value;
      }
      throw const FormatException('测试里没给这一话的图片地址');
    },
    networkAllowed: () async => wifi,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_dl_');
    cacheTmp = await Directory.systemTemp.createTemp('offline_dl_cache_');
    store = ComicOfflineStore(dirProvider: () async => tmp);
    host = _TestImageHost();
    await host.start();
  });

  tearDown(() async {
    await host.stop();
    for (final d in [tmp, cacheTmp]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('下完一话：图落进离线目录、清单写 done、进度 3/3', () async {
    final c = chapter('c1', [host.img('a.jpg'), host.img('b.jpg'), host.img('c.jpg')]);
    final dl = downloader(imagesOf: {'c1': c.images});
    await dl.enqueue(bookUrl: bookUrl, chapters: [c], bookTitle: '测试书', cover: host.img('cover.jpg'));

    await _waitFor(() => dl.jobs.single.isDone, what: '这一话下完');
    final job = dl.jobs.single;
    expect(job.total, 3);
    expect(job.done, 3);
    expect(job.progress, 1.0);
    expect(job.bytes, 3 * 1024);
    // 3 张图 + 1 张封面：封面也是"顺手下下来"的（断网时书架要有图）。
    expect(host.totalHits(), 4);
    expect(await store.localCover(bookUrl, host.img('cover.jpg')), isNotNull);

    final book = await store.loadBook(bookUrl);
    expect(book!.title, '测试书');
    expect(book.chapters.single.state, ComicOfflineState.done);
    expect(book.chapters.single.isDone, isTrue);
    final f = await store.fileFor(bookUrl, c.url, c.images.first);
    expect(await f.exists(), isTrue);
    expect(await store.bytesOf(bookUrl, chapterUrl: c.url), 3 * 1024);
  });

  test('续传只补缺的那几张：已经在本机的不再请求图床', () async {
    final c = chapter('c2', [host.img('x.jpg'), host.img('y.jpg'), host.img('z.jpg')]);
    // 假装上次下到一半：第 1 张已经在离线目录里了。
    final first = await store.fileFor(bookUrl, c.url, c.images[0]);
    await first.writeAsBytes(List<int>.filled(1024, 1));

    final dl = downloader(imagesOf: {'c2': c.images});
    await dl.enqueue(bookUrl: bookUrl, chapters: [c]);
    await _waitFor(() => dl.jobs.single.isDone, what: '补齐剩下两张');

    expect(dl.jobs.single.done, 3, reason: '进度要把"早就在本机的"也算上');
    expect(host.totalHits(), 2, reason: '只该请求缺的两张');
    expect(host.hits.keys.any((p) => p.endsWith('x.jpg')), isFalse);
  });

  test('仅 Wi-Fi 拦住：一个请求都不发，任务挂起并写明原因', () async {
    final c = chapter('c3', [host.img('w.jpg')]);
    final dl = downloader(imagesOf: {'c3': c.images}, wifi: false);
    await dl.enqueue(bookUrl: bookUrl, chapters: [c]);
    await _waitFor(() => dl.jobs.single.state == ComicOfflineJobState.paused, what: '被拦下');
    expect(host.totalHits(), 0);
    expect(dl.jobs.single.error, contains('Wi-Fi'));
  });

  test('图床 500：任务标失败并带出原话，后面的话留在队列里不白跑', () async {
    host.failPrefixes.add('/img/bad');
    final c1 = chapter('c4', [host.img('bad/1.jpg'), host.img('bad/2.jpg')]);
    final c2 = chapter('c5', [host.img('ok/1.jpg')]);
    final dl = downloader(imagesOf: {'c4': c1.images, 'c5': c2.images});
    await dl.enqueue(bookUrl: bookUrl, chapters: [c1, c2]);

    await _waitFor(
      () => dl.jobs.first.state == ComicOfflineJobState.failed,
      what: '第一话失败',
    );
    expect(dl.jobs.first.error, contains('HTTP 500'));
    expect(dl.jobs.last.state, ComicOfflineJobState.queued,
        reason: '网络/图床出问题时不接着往下话冲，剩下的等用户继续');
    expect(host.hits.keys.any((p) => p.contains('/img/ok/')), isFalse);

    // 恢复后点继续：第一话成功，第二话接着跑完。
    host.failPrefixes.clear();
    dl.resume(bookUrl, c1.url);
    await _waitFor(() => dl.jobs.every((j) => j.isDone), what: '两话都下完');
    final book = await store.loadBook(bookUrl);
    expect(book!.doneCount, 2);
  });

  test('一话一话来：不跨话同时挤图床（话内也是顺序下）', () async {
    final c1 = chapter('c6', [host.img('s1.jpg'), host.img('s2.jpg')]);
    final c2 = chapter('c7', [host.img('s3.jpg'), host.img('s4.jpg')]);
    final dl = downloader(imagesOf: {'c6': c1.images, 'c7': c2.images});
    await dl.enqueue(bookUrl: bookUrl, chapters: [c1, c2]);
    await _waitFor(() => dl.jobs.every((j) => j.isDone), what: '两话都下完');
    expect(host.totalHits(), 4);
    expect(host.peak, lessThanOrEqualTo(1),
        reason: '一话一话串着下：同时压在图床上的连接只有一条');
  });

  test('崩溃恢复：清单里的 running 变 paused，重启后不自动开始下载', () async {
    // 上次下到一半就没了留下的现场。
    final c = chapter('c8', [host.img('r1.jpg'), host.img('r2.jpg')]);
    final book = ComicOfflineBook(
      bookUrl: bookUrl,
      title: '半截书',
      chapters: [ComicOfflineChapter(url: c.url, title: c.title, images: c.images, done: 1, state: ComicOfflineState.running)],
    );
    await store.saveBook(book);

    final dl = downloader(imagesOf: {'c8': c.images});
    expect(await dl.loadInterrupted(), 1);
    expect(dl.jobs.single.state, ComicOfflineJobState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(host.totalHits(), 0, reason: '不点继续就不该自己开始下（可能在移动网络上）');
    expect((await store.loadBook(bookUrl))!.chapters.single.state, ComicOfflineState.paused);
  });

  test('「这次用流量」：被仅 Wi-Fi 拦下的任务会重新排起来并下完（不是按了没反应）', () async {
    final c = chapter('c10', [host.img('m1.jpg'), host.img('m2.jpg')]);
    // 策略仍然说"只在 Wi-Fi 下"（用户没改设置，只是这一次放行）。
    final dl = downloader(imagesOf: {'c10': c.images}, wifi: false);
    await dl.enqueue(bookUrl: bookUrl, chapters: [c]);
    await _waitFor(
      () => dl.jobs.single.state == ComicOfflineJobState.paused,
      what: '被拦下',
    );
    expect(dl.waitingForWifi, isTrue);
    expect(host.totalHits(), 0, reason: '拦下就该一个请求都不发');

    // 点「这次用流量」的瞬间：它们得**从 paused 排回队列**才会被 _pump 挑走。
    // （用户报过"点击没反应"：按钮没坏，是没人把这些任务叫回来。）
    dl.allowNetworkOnce();
    await _waitFor(() => dl.jobs.single.isDone, what: '放行之后真的下完');
    expect(dl.waitingForWifi, isFalse);
    expect(host.totalHits(), 2, reason: '两张图（这条用例没给封面）');
  });

  test('对"在等 Wi-Fi"的那一话点继续：就按"现在接着下"办（不是又拦一次）', () async {
    final c = chapter('c11', [host.img('n1.jpg')]);
    final dl = downloader(imagesOf: {'c11': c.images}, wifi: false);
    await dl.enqueue(bookUrl: bookUrl, chapters: [c]);
    await _waitFor(
      () => dl.jobs.single.state == ComicOfflineJobState.paused,
      what: '被拦下',
    );

    dl.resume(bookUrl, c.url);
    await _waitFor(() => dl.jobs.single.isDone, what: '点了继续就真的下完');
    expect(host.totalHits(), 1);
  });

  test('取消：任务从队列消失，已经下来的文件也删掉', () async {
    final c = chapter('c9', [host.img('d1.jpg')]);
    final dl = downloader(imagesOf: {'c9': c.images});
    await dl.enqueue(bookUrl: bookUrl, chapters: [c]);
    await _waitFor(() => dl.jobs.single.isDone, what: '下完');
    final f = await store.fileFor(bookUrl, c.url, c.images.first);
    expect(await f.exists(), isTrue);

    await dl.cancel(bookUrl, c.url);
    expect(dl.jobs, isEmpty);
    expect(await f.exists(), isFalse);
    expect(await store.loadBook(bookUrl), isNull, reason: '一话都没下完就不该留空壳书');
  });

  // ── 单张图被掐断：整轮重试一次，不直接废掉整话（2026-10-02 用户截图）──
  group('单张图重试', () {
    test('一张图第一次整轮失败：等一会儿整轮再来，这一话照样下完', () async {
      final cache = _FlakyCache(
        failOnce: {host.img('1.jpg')},
        tempDirProvider: () async => cacheTmp,
      );
      final dl = downloader(
        imagesOf: {
          'ch1.html': [host.img('1.jpg'), host.img('2.jpg')],
        },
        cache: cache,
      );

      await dl.enqueue(
        bookUrl: bookUrl,
        chapters: [chapter('第一话', [host.img('1.jpg'), host.img('2.jpg')])],
      );
      await _waitFor(() => dl.jobs.single.isDone, what: '这一话下完');

      expect(dl.jobs.single.state, ComicOfflineJobState.done, reason: '重试一次就成了，不该标失败');
      expect(dl.jobs.single.done, 2);
      expect(
        cache.budgets,
        everyElement(ComicOfflineDownloader.defaultImageAttempts),
        reason: '下载必须比前台读图多给几次机会',
      );
    });

    test('HTTP 404 这种"再来也一样"的错：不白等一轮，直接报出来', () async {
      host.statusByPrefix['/img/1.jpg'] = 404;
      final cache = ComicImageCache(maxParallel: 2, tempDirProvider: () async => cacheTmp);
      final dl = downloader(
        imagesOf: {
          'ch1.html': [host.img('1.jpg')],
        },
        cache: cache,
        retryDelay: const Duration(milliseconds: 10),
      );

      await dl.enqueue(
        bookUrl: bookUrl,
        chapters: [chapter('第一话', [host.img('1.jpg')])],
      );
      await _waitFor(
        () => dl.jobs.single.state == ComicOfflineJobState.failed,
        what: '这一话标失败',
      );

      expect(dl.jobs.single.error, contains('HTTP 404'));
      expect(host.hits['/img/1.jpg'], 1, reason: '4xx 再来也一样，不该白取第二次');
    });

    test('一直掐断才把这一话标失败，并把原因留给用户', () async {
      final cache = _FlakyCache(
        failAlways: {host.img('1.jpg')},
        tempDirProvider: () async => cacheTmp,
      );
      final dl = downloader(
        imagesOf: {
          'ch1.html': [host.img('1.jpg')],
        },
        cache: cache,
      );

      await dl.enqueue(
        bookUrl: bookUrl,
        chapters: [chapter('第一话', [host.img('1.jpg')])],
      );
      await _waitFor(
        () => dl.jobs.single.state == ComicOfflineJobState.failed,
        what: '这一话标失败',
      );

      expect(dl.jobs.single.error, contains('被掐断'));
      expect(cache.budgets.length, 2, reason: '整轮试了两次（各 6 个地址）');
    });
  });
}

/// 取图会先失败几次的假缓存：只钉"下载侧怎么应对失败"，不碰真网络。
class _FlakyCache extends ComicImageCache {
  _FlakyCache({
    Set<String>? failOnce,
    Set<String>? failAlways,
    super.tempDirProvider,
  }) : _failOnce = {...?failOnce},
       _failAlways = {...?failAlways};

  final Set<String> _failOnce;
  final Set<String> _failAlways;

  /// 每次调用实际传下来的 attempts（钉"下载给了几次机会"）。
  final List<int?> budgets = [];

  @override
  Future<File> fetch(
    String url, {
    bool lowPriority = false,
    File? dest,
    int? maxAttempts,
  }) async {
    budgets.add(maxAttempts);
    if (_failAlways.contains(url)) {
      throw ComicImageException('测试：被掐断（一直不通）', retryable: true, transient: true);
    }
    if (_failOnce.remove(url)) {
      throw ComicImageException('测试：被掐断（下一轮就好）', retryable: true, transient: true);
    }
    return super.fetch(url, lowPriority: lowPriority, dest: dest, maxAttempts: maxAttempts);
  }
}
